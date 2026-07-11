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
const _FiveCardDraw    := preload("res://games/five_card_draw.gd")
const _TexasHoldem     := preload("res://games/texas_holdem.gd")
const _SevenCardStud   := preload("res://games/seven_card_stud.gd")
const _DeucesWild          := preload("res://games/deuces_wild.gd")
const _DeucesWildStud      := preload("res://games/deuces_wild_stud.gd")
const _CaliforniaLowball   := preload("res://games/california_lowball.gd")
const _PlayerState    := preload("res://core/player_state.gd")

## Seat top-left positions as fractions of viewport size, for up to 5 players.
## Index 0 = local player (upper-left lower slot).
## Index 1 = directly above local player (upper-left upper slot).
## Indices 2-4 = right column top→bottom (index 2 opposite index 1).
const SEAT_POS_FRACS := [
	Vector2(0.016, 0.269),  # 0: local — upper-left, lower
	Vector2(0.016, 0.028),  # 1: upper-left, above local
	Vector2(0.526, 0.028),  # 2: right col top
	Vector2(0.526, 0.269),  # 3: right col middle
	Vector2(0.526, 0.509),  # 4: right col lower
]

## Seat minimum size as a fraction of viewport width.
const SEAT_W_FRAC  = 0.125   # 120 / 960
const SEAT_H_FRAC  = 0.207   # 112 / 540

## Coin image paths — loaded at runtime so missing .import files don't block parse.
const _COIN_PATHS: Array = [
	"res://assets/images/coins/96x96-1984_rv_marie_curie.png",
	"res://assets/images/coins/96x96_front_1907_Saint_Gaudens_gold_coin.png",
	"res://assets/images/coins/96x96_front_Gaius-Julius-Caesar-denarius-44-BC-RRC-480-3.png",
	"res://assets/images/coins/96x96-head_of_Aphrodite_with_turreted_crown.png",
	"res://assets/images/coins/96x96-Marcus Antonius - Cleopatra 32 BC 90020163_front.png",
	"res://assets/images/coins/96x96-Marcus Antonius - Cleopatra 32 BC 90020163_back.png",
]
const MAX_POT_COINS = 40
const COIN_ADD_INTERVAL := 0.3   # seconds between coins entering the pot (one at a time)
const COIN_VALUE := 100          # chips represented by one pot coin

## Layout values computed from viewport size at _ready.
var _coin_display_size: int  = 48
var _pot_center: Vector2     = Vector2(480, 370)
var _pot_scatter_radius: float = 90.0

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
var _coin_target: int           = 0      # how many coins the pot should show
var _coin_actor_idx: int        = -1     # seat the newest coins fly in from (-1 = no fly)
var _coin_add_cooldown: float   = 0.0    # time until the next coin may enter

@onready var _deuces_label:    Label         = $UI/DeucesLabel
@onready var _pot_label:       Label         = $UI/PotLabel
@onready var _action_log:      RichTextLabel = $UI/ActionLog
@onready var _community_box:   HBoxContainer = $UI/CommunityCards
@onready var _draw_panel:      VBoxContainer = $UI/DrawPanel
@onready var _draw_label:      Label         = $UI/DrawPanel/DrawLabel
@onready var _confirm_btn:     Button        = $UI/DrawPanel/ConfirmBtn
@onready var _results_overlay: Control       = $UI/ResultsOverlay
@onready var _results_label:   Label         = $UI/ResultsOverlay/CenterBox/InnerVBox/ResultsLabel
@onready var _next_btn:        Button        = $UI/ResultsOverlay/CenterBox/InnerVBox/NextBtn
@onready var _clock_timer = $UI/TurnTimer

var _client_time_left: float = 0.0
var _turn_duration: float = 30.0
var _draw_hand: Array = []
var _draw_hard_max: int = 3

func _ready() -> void:
	_my_peer_id = NetworkManager.get_my_id()
	_draw_panel.visible      = false
	_results_overlay.visible = false

	var lbl_bg := StyleBoxFlat.new()
	lbl_bg.bg_color = Color(0.05, 0.05, 0.05, 0.88)
	lbl_bg.set_corner_radius_all(5)
	lbl_bg.set_content_margin_all(8)
	_draw_label.add_theme_stylebox_override("normal", lbl_bg)
	_draw_label.add_theme_color_override("font_color", Color.WHITE)
	_community_box.visible   = (GameManager.current_variant == GameManager.GameVariant.TEXAS_HOLDEM)
	_deuces_label.visible    = GameManager.deuces_wild

	_peer_order = NetworkManager.player_names.keys()
	_peer_order.sort()

	# ── Viewport-derived layout values ────────────────────────────────────────
	var vp := get_viewport().get_visible_rect().size
	_coin_display_size  = int(vp.x * 0.05)
	_pot_center         = vp * Vector2(0.5, 0.685)
	_pot_scatter_radius = vp.y * 0.167

	# ── Coins ─────────────────────────────────────────────────────────────────
	_coin_tex = load(_COIN_PATHS[randi() % _COIN_PATHS.size()])

	# Precompute MAX_POT_COINS random scatter positions (stable for the session).
	for _i in MAX_POT_COINS:
		var angle = randf() * TAU
		var dist  = randf() * _pot_scatter_radius
		_pot_positions.append(_pot_center + Vector2(cos(angle), sin(angle)) * dist)

	# Container rendered just above the table background, below seats/UI.
	_pot_root = Node2D.new()
	add_child(_pot_root)
	move_child(_pot_root, 1)   # index 0 = TableBackground, 1 = pot coins

	_create_seats()

	# Pass coin icon to every seat.
	if _coin_tex:
		for seat in _seat_nodes:
			seat.set_coin_icon(_coin_tex, _coin_display_size / 2)

	_betting_ctrl = BETTING_SCENE.instantiate()
	$UI.add_child(_betting_ctrl)
	# Left-aligned, ending before the centre timer. Height auto-sized by content.
	_betting_ctrl.anchor_left   = 0.0
	_betting_ctrl.anchor_right  = 370.0 / 960.0
	_betting_ctrl.anchor_top    = 1.0
	_betting_ctrl.anchor_bottom = 1.0
	_betting_ctrl.offset_left   = int(vp.x * 0.016)
	_betting_ctrl.offset_right  = 0
	_betting_ctrl.offset_top    = -int(vp.y * 0.133)
	_betting_ctrl.offset_bottom = -int(vp.y * 0.037)
	_betting_ctrl.action_chosen.connect(_on_action_chosen)

	var timer_size   := vp.y * 0.139
	var timer_margin := vp.y * 0.019
	_clock_timer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_clock_timer.offset_left   = -timer_size * 0.5
	_clock_timer.offset_right  =  timer_size * 0.5
	_clock_timer.offset_top    = -timer_size - timer_margin
	_clock_timer.offset_bottom = -timer_margin

	if NetworkManager.is_server():
		_create_game_logic()

func _process(delta: float) -> void:
	if _client_time_left > 0.0:
		_client_time_left = maxf(_client_time_left - delta, 0.0)
		_clock_timer.fill_ratio = _client_time_left / _turn_duration

	# Feed coins into the pot one at a time, catching up to the target across
	# frames so only a single coin is ever in flight (matches Dealer's Choice).
	if _pot_sprites.size() < _coin_target:
		_coin_add_cooldown = maxf(_coin_add_cooldown - delta, 0.0)
		if _coin_add_cooldown == 0.0:
			_spawn_pot_coin()
			_coin_add_cooldown = COIN_ADD_INTERVAL

func _create_seats() -> void:
	var my_index := _peer_order.find(_my_peer_id)
	var n := _peer_order.size()
	var vp := get_viewport().get_visible_rect().size
	var seat_min := Vector2(vp.x * SEAT_W_FRAC, vp.y * SEAT_H_FRAC)
	for i in n:
		var seat = SEAT_SCENE.instantiate()
		add_child(seat)
		seat.peer_id = _peer_order[i]
		seat.custom_minimum_size = seat_min
		_seat_nodes.append(seat)
		var display_pos := (i - my_index + n) % n
		seat.position = vp * SEAT_POS_FRACS[display_pos]

func _create_game_logic() -> void:
	var dw := GameManager.deuces_wild
	match GameManager.current_variant:
		GameManager.GameVariant.FIVE_CARD_DRAW:
			_game = _DeucesWild.new(self) if dw else _FiveCardDraw.new(self)
		GameManager.GameVariant.TEXAS_HOLDEM:
			_game = _TexasHoldem.new(self)
		GameManager.GameVariant.SEVEN_CARD_STUD:
			_game = _DeucesWildStud.new(self) if dw else _SevenCardStud.new(self)
		GameManager.GameVariant.CALIFORNIA_LOWBALL:
			_game = _CaliforniaLowball.new(self)

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
func request_discards(hand: Array, hard_max: int) -> void:
	_show_draw_controls(hand, hard_max)

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

func _show_draw_controls(hand: Array, hard_max: int) -> void:
	_draw_hand     = hand
	_draw_hard_max = hard_max
	AudioManager.play_my_turn()
	var my_seat = _get_seat(_my_peer_id)
	if my_seat:
		my_seat.enable_card_selection(true)
		my_seat.card_selection_changed.connect(_on_card_selection_changed)
	_draw_panel.visible  = true
	_confirm_btn.disabled = false
	_draw_label.text = "Discard up to 3, or 4 keeping an ace" if hard_max >= 4 \
		else "Discard up to 3"

func _on_card_selection_changed() -> void:
	var my_seat = _get_seat(_my_peer_id)
	if not my_seat:
		return
	var selected: Array[int] = my_seat.get_selected_indices()
	var count: int           = selected.size()
	if count <= 3:
		_confirm_btn.disabled = false
		_draw_label.text = "Stand pat" if count == 0 else "Discard %d" % count
	elif _draw_hard_max >= 4:
		var keeping_ace := false
		for i in range(_draw_hand.size()):
			if i not in selected and CardDB.rank_index(_draw_hand[i]) == 12:
				keeping_ace = true
				break
		_confirm_btn.disabled = not keeping_ace
		_draw_label.text = "Discard 4 (keeping ace)" if keeping_ace \
			else "Keep an ace to discard 4"
	else:
		_confirm_btn.disabled = true
		_draw_label.text = "Maximum 3 discards"

# ── State application ─────────────────────────────────────────────────────────

func _apply_public_state(state: Dictionary) -> void:
	var pot: int       = state.get("pot", 0)
	var actor_idx: int = state.get("actor_index", -1)
	var phase: int     = state.get("phase", 0)

	# Dismiss the draw panel if it's no longer our turn to draw.
	# Phase 4 = BaseGame.Phase.DRAW
	if _draw_panel.visible:
		var my_seat_idx := _peer_order.find(_my_peer_id)
		if not (phase == 4 and actor_idx == my_seat_idx):
			_disconnect_draw_selection()
			_draw_panel.visible = false
			var my_seat = _get_seat(_my_peer_id)
			if my_seat:
				my_seat.enable_card_selection(false)

	_pot_label.text = "Pot: %d" % pot
	_apply_pot_coins(pot, actor_idx)
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

func _disconnect_draw_selection() -> void:
	var my_seat = _get_seat(_my_peer_id)
	if my_seat and my_seat.card_selection_changed.is_connected(_on_card_selection_changed):
		my_seat.card_selection_changed.disconnect(_on_card_selection_changed)

func _on_draw_confirm_pressed() -> void:
	var my_seat = _get_seat(_my_peer_id)
	var indices: Array[int] = []
	if my_seat:
		indices = my_seat.get_selected_indices()
		my_seat.enable_card_selection(false)
	_disconnect_draw_selection()
	_draw_panel.visible = false
	if NetworkManager.is_server():
		_game.receive_discards(_my_peer_id, indices)
	else:
		submit_discards.rpc_id(1, indices)

# ── Pot coin display ──────────────────────────────────────────────────────────

func _apply_pot_coins(pot: int, actor_idx: int) -> void:
	if _coin_tex == null:
		return
	# One coin per 100 chips in the pot (matches Dealer's Choice's default feel).
	_coin_target     = mini(pot / COIN_VALUE, MAX_POT_COINS)
	_coin_actor_idx  = actor_idx   # seat the next coins fly in from

	# Remove excess sprites immediately (e.g. pot awarded, new hand reset).
	while _pot_sprites.size() > _coin_target:
		(_pot_sprites.pop_back() as Node).queue_free()
	# Coins below the target are added one at a time by _process.

func _spawn_pot_coin() -> void:
	var idx: int   = _pot_sprites.size()
	var sp         = Sprite2D.new()
	sp.texture     = _coin_tex
	var tex_size   = maxf(_coin_tex.get_width(), _coin_tex.get_height())
	var scale_f    = float(_coin_display_size) / tex_size
	sp.scale       = Vector2(scale_f, scale_f)
	sp.rotation    = randf() * TAU   # random resting angle, like DC
	sp.position    = _pot_positions[idx]
	_pot_root.add_child(sp)
	_pot_sprites.append(sp)

	# Fly the coin in from the acting player's seat, if known.
	if _coin_actor_idx >= 0 and _coin_actor_idx < _seat_nodes.size():
		var seat       = _seat_nodes[_coin_actor_idx]
		var start_pos: Vector2 = seat.position + seat.size * 0.5
		sp.position = start_pos
		var tw = create_tween()
		tw.tween_property(sp, "position", _pot_positions[idx], COIN_ADD_INTERVAL)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_seat(peer_id: int):
	for seat in _seat_nodes:
		if seat.peer_id == peer_id:
			return seat
	return null
