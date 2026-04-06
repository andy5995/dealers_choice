class_name GameTable
extends Node2D
## Present on ALL peers. Server-side: creates game logic and forwards client RPCs.
## Client-side: renders state received via RPCs.
##
## Custom class_name types (BaseGame, PlayerSeat, etc.) are NOT used as type
## annotations here because the class registry isn't guaranteed when this
## script is compiled during change_scene_to_file.  Use preload constants and
## untyped vars instead.

const SEAT_SCENE      := preload("res://ui/player_seat.tscn")
const BETTING_SCENE   := preload("res://ui/betting_controls.tscn")
const _CardView = preload("res://ui/card_view.tscn")
const _FiveCardDraw   := preload("res://games/five_card_draw.gd")
const _TexasHoldem    := preload("res://games/texas_holdem.gd")
const _SevenCardStud  := preload("res://games/seven_card_stud.gd")
const _PlayerState    := preload("res://core/player_state.gd")

## Seat display positions for up to 5 players (1920×1080 table).
## Index 0 = local player (upper-left lower slot).
## Index 1 = directly above local player (upper-left upper slot).
## Indices 2-4 = right column top→bottom (index 2 opposite index 1).
## seat.position = SEAT_POSITIONS[display_pos] - Vector2(80, 75) → top-left of 240×225 seat.
const SEAT_POSITIONS := [
	Vector2(110, 365),   # 0: local — upper-left, lower   (top-left ≈ 30, 290)
	Vector2(110, 105),   # 1: upper-left, above local      (top-left ≈ 30, 30)
	Vector2(1090, 105),  # 2: right col top    (top-left ≈ 1010, 30)  = w/2+50
	Vector2(1090, 365),  # 3: right col middle (top-left ≈ 1010, 290)
	Vector2(1090, 625),  # 4: right col lower  (top-left ≈ 1010, 550)
]

## Coin image paths — loaded at runtime so missing .import files don't block parse.
const _COIN_PATHS: Array = [
	"res://assets/images/coins/96x96-1984_rv_marie_curie.png",
	"res://assets/images/coins/96x96_front_1907_Saint_Gaudens_gold_coin.png",
	"res://assets/images/coins/96x96_front_Gaius-Julius-Caesar-denarius-44-BC-RRC-480-3.png",
	"res://assets/images/coins/96x96-head_of_Aphrodite_with_turreted_crown.png",
	"res://assets/images/coins/96x96-Marcus Antonius - Cleopatra 32 BC 90020163_front.png",
	"res://assets/images/coins/96x96-Marcus Antonius - Cleopatra 32 BC 90020163_back.png",
]
const COIN_DISPLAY_SIZE  = 96   # full 96px in the pot; icon on seats is smaller
const MAX_POT_COINS      = 40
## Centre of the scatter field — between community cards and player seats.
const POT_CENTER         = Vector2(960, 735)
const POT_SCATTER_RADIUS = 180.0

var _game          = null   # BaseGame subclass, server only
var _seat_nodes: Array = [] # PlayerSeat nodes
var _betting_ctrl  = null   # BettingControls node
var _peer_order: Array = []
var _my_peer_id: int = 0
var _last_coin_action: String = ""

## Coin state
var _coin_tex: Texture2D        = null
var _pot_root: Node2D           = null   # container drawn below seats
var _pot_sprites: Array         = []     # Sprite2D nodes currently in the pot
var _pot_positions: Array       = []     # precomputed scatter Vector2s (MAX_POT_COINS)
var _prev_pot: int              = 0

@onready var _pot_label:       Label         = $UI/PotLabel
@onready var _action_log:      RichTextLabel = $UI/ActionLog
@onready var _community_box:   HBoxContainer = $UI/CommunityCards
@onready var _draw_panel:      VBoxContainer = $UI/DrawPanel
@onready var _results_overlay: Control       = $UI/ResultsOverlay
@onready var _results_label:   Label         = $UI/ResultsOverlay/CenterBox/InnerVBox/ResultsLabel
@onready var _next_btn:        Button        = $UI/ResultsOverlay/CenterBox/InnerVBox/NextBtn
@onready var _clock_timer = $UI/TurnTimer

var _client_time_left: float = 0.0
var _turn_duration: float = 30.0

func _ready() -> void:
	_my_peer_id = NetworkManager.get_my_id()
	_draw_panel.visible      = false
	_results_overlay.visible = false
	_community_box.visible   = (GameManager.current_variant == GameManager.GameVariant.TEXAS_HOLDEM)

	_peer_order = NetworkManager.player_names.keys()
	_peer_order.sort()

	# ── Coins ─────────────────────────────────────────────────────────────────
	_coin_tex = load(_COIN_PATHS[randi() % _COIN_PATHS.size()])

	# Precompute MAX_POT_COINS random scatter positions (stable for the session).
	for _i in MAX_POT_COINS:
		var angle = randf() * TAU
		var dist  = randf() * POT_SCATTER_RADIUS
		_pot_positions.append(POT_CENTER + Vector2(cos(angle), sin(angle)) * dist)

	# Container rendered just above the table background, below seats/UI.
	_pot_root = Node2D.new()
	add_child(_pot_root)
	move_child(_pot_root, 1)   # index 0 = TableBackground, 1 = pot coins

	_create_seats()

	# Pass coin icon to every seat.
	if _coin_tex:
		for seat in _seat_nodes:
			seat.set_coin_icon(_coin_tex, COIN_DISPLAY_SIZE / 2)

	_betting_ctrl = BETTING_SCENE.instantiate()
	$UI.add_child(_betting_ctrl)
	# Position at lower-left starting at ~1/3 screen width, auto-sized by content.
	_betting_ctrl.anchor_left   = 0.0
	_betting_ctrl.anchor_right  = 0.0
	_betting_ctrl.anchor_top    = 1.0
	_betting_ctrl.anchor_bottom = 1.0
	_betting_ctrl.offset_left   = 640
	_betting_ctrl.offset_top    = -145
	_betting_ctrl.offset_right  = 1380
	_betting_ctrl.offset_bottom = -20
	_betting_ctrl.action_chosen.connect(_on_action_chosen)

	if NetworkManager.is_server():
		_create_game_logic()

func _process(delta: float) -> void:
	if _client_time_left > 0.0:
		_client_time_left = maxf(_client_time_left - delta, 0.0)
		_clock_timer.fill_ratio = _client_time_left / _turn_duration

func _create_seats() -> void:
	var my_index := _peer_order.find(_my_peer_id)
	var n := _peer_order.size()
	for i in n:
		var seat = SEAT_SCENE.instantiate()
		add_child(seat)
		seat.peer_id = _peer_order[i]
		_seat_nodes.append(seat)
		var display_pos := (i - my_index + n) % n
		seat.position = SEAT_POSITIONS[display_pos] - Vector2(80, 75)

func _create_game_logic() -> void:
	match GameManager.current_variant:
		GameManager.GameVariant.FIVE_CARD_DRAW:
			_game = _FiveCardDraw.new(self)
		GameManager.GameVariant.TEXAS_HOLDEM:
			_game = _TexasHoldem.new(self)
		GameManager.GameVariant.SEVEN_CARD_STUD:
			_game = _SevenCardStud.new(self)

	add_child(_game)

	var player_states: Array = []
	for pid in _peer_order:
		var ps = _PlayerState.new()
		ps.peer_id      = pid
		ps.display_name = NetworkManager.player_names[pid]
		ps.chips        = GameManager.starting_chips
		player_states.append(ps)

	_game.begin_game(player_states)

# ── RPCs: Client → Server ─────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func submit_action(action: String, amount: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_game.receive_player_action(sender, action, amount)

@rpc("any_peer", "call_remote", "reliable")
func submit_discards(indices: Array) -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_game.receive_discards(sender, indices)

# ── RPCs: Server → Clients ────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func receive_public_state(state: Dictionary) -> void:
	_apply_public_state(state)

@rpc("authority", "call_remote", "reliable")
func receive_private_state(state: Dictionary) -> void:
	_apply_private_state(_my_peer_id, state)

@rpc("authority", "call_remote", "reliable")
func receive_your_turn(valid_actions: Array, bet_to_call: int, min_bet: int, my_chips: int) -> void:
	_show_betting_controls(valid_actions, bet_to_call, min_bet, my_chips)

@rpc("authority", "call_remote", "reliable")
func request_discards(hand: Array) -> void:
	_show_draw_controls(hand)

@rpc("authority", "call_local", "reliable")
func receive_game_over(results: Dictionary) -> void:
	AudioManager.play_game_over()
	_show_results(results)

@rpc("authority", "call_local", "reliable")
func return_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# ── Called directly by BaseGame for the host player ──────────────────────────

func _apply_private_state(peer_id: int, state: Dictionary) -> void:
	var seat = _get_seat(peer_id)
	if seat:
		seat.update_private(state)

func _show_betting_controls(valid_actions: Array, bet_to_call: int, min_bet: int, my_chips: int) -> void:
	AudioManager.play_my_turn()
	if _betting_ctrl:
		_betting_ctrl.setup(valid_actions, bet_to_call, min_bet, my_chips)

func _show_draw_controls(_hand: Array) -> void:
	AudioManager.play_my_turn()
	var my_seat = _get_seat(_my_peer_id)
	if my_seat:
		my_seat.enable_card_selection(true)
	_draw_panel.visible = true

# ── State application ─────────────────────────────────────────────────────────

func _apply_public_state(state: Dictionary) -> void:
	var pot: int       = state.get("pot", 0)
	var actor_idx: int = state.get("actor_index", -1)

	_pot_label.text = "Pot: %d" % pot
	_apply_pot_coins(pot, actor_idx)
	_prev_pot = pot
	if actor_idx >= 0:
		_turn_duration = state.get("turn_duration", 30.0)
		_client_time_left = state.get("turn_time_left", 0.0)
		_clock_timer.fill_ratio = _client_time_left / _turn_duration
		_clock_timer.visible = true
	else:
		_client_time_left = 0.0
		_clock_timer.visible = false

	var last_action: String = state.get("last_action", "")
	if last_action != "" and last_action != _last_coin_action:
		_last_coin_action = last_action
		_action_log.append_text(last_action + "\n")
		if "bet" in last_action or "call" in last_action or "raise" in last_action:
			AudioManager.play_coin_hit()

	_update_community_cards(state.get("community_cards", []))

	for pd in state.get("players", []):
		var seat = _get_seat(pd.get("peer_id", -1))
		if seat:
			seat.update_public(pd)

func _update_community_cards(cards: Array) -> void:
	for child in _community_box.get_children():
		child.queue_free()
	for card_name in cards:
		var cv = _CardView.instantiate()
		_community_box.add_child(cv)
		cv.show_card(card_name, true)

func _show_results(results: Dictionary) -> void:
	if _betting_ctrl:
		_betting_ctrl.visible = false
	_draw_panel.visible = false

	if results.get("final", false):
		_results_label.text = "%s wins the game!" % results.get("winner_name", "Nobody")
		_next_btn.text = "Main Menu"
		_next_btn.visible = true
		_clock_timer.visible = false
	else:
		var lines: Array[String] = []
		for pid in results:
			if pid is int:
				var info: Dictionary = results[pid]
				var suffix := " *" if info.get("is_winner", false) else ""
				var pname: String = NetworkManager.player_names.get(pid, "Player")
				lines.append("%s: %s%s" % [pname, info.get("hand_name", ""), suffix])
		_results_label.text = "\n".join(lines)
		_next_btn.visible = false
		_turn_duration = 15.0
		_client_time_left = 15.0
		_clock_timer.fill_ratio = 1.0
		_clock_timer.visible = true
	_results_overlay.visible = true

func _on_results_next_pressed() -> void:
	_results_overlay.visible = false
	if _next_btn.text == "Main Menu":
		NetworkManager.disconnect_all()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_action_chosen(action: String, amount: int) -> void:
	if NetworkManager.is_server():
		_game.receive_player_action(_my_peer_id, action, amount)
	else:
		submit_action.rpc_id(1, action, amount)

func _on_draw_confirm_pressed() -> void:
	var my_seat = _get_seat(_my_peer_id)
	var indices: Array[int] = []
	if my_seat:
		indices = my_seat.get_selected_indices()
		my_seat.enable_card_selection(false)
	_draw_panel.visible = false
	if NetworkManager.is_server():
		_game.receive_discards(_my_peer_id, indices)
	else:
		submit_discards.rpc_id(1, indices)

# ── Pot coin display ──────────────────────────────────────────────────────────

func _apply_pot_coins(pot: int, actor_idx: int) -> void:
	if _coin_tex == null:
		return
	var ante: int    = maxi(GameManager.ante_amount, 1)
	var target: int  = mini(pot / ante, MAX_POT_COINS)

	# Remove excess sprites (e.g. new hand reset).
	while _pot_sprites.size() > target:
		(_pot_sprites.pop_back() as Node).queue_free()

	# Add new sprites, animating from the actor's seat when pot is rising.
	while _pot_sprites.size() < target:
		var idx: int   = _pot_sprites.size()
		var sp         = Sprite2D.new()
		sp.texture     = _coin_tex
		var scale_f    = float(COIN_DISPLAY_SIZE) / 96.0
		sp.scale       = Vector2(scale_f, scale_f)
		sp.position    = _pot_positions[idx]
		_pot_root.add_child(sp)
		_pot_sprites.append(sp)

		# Animate from actor seat when the pot increased.
		if pot > _prev_pot and actor_idx >= 0 and actor_idx < _seat_nodes.size():
			var seat       = _seat_nodes[actor_idx]
			var start_pos: Vector2 = seat.position + Vector2(120, 112)
			sp.position = start_pos
			var tw = create_tween()
			tw.tween_property(sp, "position", _pot_positions[idx], 0.3)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_seat(peer_id: int):
	for seat in _seat_nodes:
		if seat.peer_id == peer_id:
			return seat
	return null
