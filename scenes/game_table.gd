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
const CARD_VIEW_SCENE := preload("res://ui/card_view.tscn")
const _FiveCardDraw   := preload("res://games/five_card_draw.gd")
const _TexasHoldem    := preload("res://games/texas_holdem.gd")
const _SevenCardStud  := preload("res://games/seven_card_stud.gd")
const _PlayerState    := preload("res://core/player_state.gd")

## Seat display positions for up to 5 players (1280×720 table).
## Index 0 = local player (always bottom-centre); others clockwise from left.
const SEAT_POSITIONS := [
	Vector2(640, 590),
	Vector2(160, 460),
	Vector2(160, 180),
	Vector2(1120, 180),
	Vector2(1120, 460),
]

var _game          = null   # BaseGame subclass, server only
var _seat_nodes: Array = [] # PlayerSeat nodes
var _betting_ctrl  = null   # BettingControls node
var _peer_order: Array[int] = []
var _my_peer_id: int = 0

@onready var _pot_label:       Label         = $UI/PotLabel
@onready var _action_log:      RichTextLabel = $UI/ActionLog
@onready var _community_box:   HBoxContainer = $UI/CommunityCards
@onready var _draw_panel:      VBoxContainer = $UI/DrawPanel
@onready var _results_overlay: Control       = $UI/ResultsOverlay
@onready var _results_label:   Label         = $UI/ResultsOverlay/CenterBox/InnerVBox/ResultsLabel
@onready var _next_btn:        Button        = $UI/ResultsOverlay/CenterBox/InnerVBox/NextBtn

func _ready() -> void:
	_my_peer_id = NetworkManager.get_my_id()
	_draw_panel.visible      = false
	_results_overlay.visible = false
	_community_box.visible   = (GameManager.current_variant == GameManager.GameVariant.TEXAS_HOLDEM)

	_peer_order = NetworkManager.player_names.keys()
	_peer_order.sort()

	_create_seats()

	_betting_ctrl = BETTING_SCENE.instantiate()
	$UI.add_child(_betting_ctrl)
	_betting_ctrl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_betting_ctrl.action_chosen.connect(_on_action_chosen)

	if NetworkManager.is_server():
		_create_game_logic()

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
	_show_results(results)

# ── Called directly by BaseGame for the host player ──────────────────────────

func _apply_private_state(peer_id: int, state: Dictionary) -> void:
	var seat = _get_seat(peer_id)
	if seat:
		seat.update_private(state)

func _show_betting_controls(valid_actions: Array, bet_to_call: int, min_bet: int, my_chips: int) -> void:
	if _betting_ctrl:
		_betting_ctrl.setup(valid_actions, bet_to_call, min_bet, my_chips)

func _show_draw_controls(_hand: Array) -> void:
	var my_seat = _get_seat(_my_peer_id)
	if my_seat:
		my_seat.enable_card_selection(true)
	_draw_panel.visible = true

# ── State application ─────────────────────────────────────────────────────────

func _apply_public_state(state: Dictionary) -> void:
	_pot_label.text = "Pot: %d" % state.get("pot", 0)

	var last_action: String = state.get("last_action", "")
	if last_action != "":
		_action_log.append_text(last_action + "\n")

	_update_community_cards(state.get("community_cards", []))

	for pd in state.get("players", []):
		var seat = _get_seat(pd.get("peer_id", -1))
		if seat:
			seat.update_public(pd)

func _update_community_cards(cards: Array) -> void:
	for child in _community_box.get_children():
		child.queue_free()
	for card_name in cards:
		var cv = CARD_VIEW_SCENE.instantiate()
		_community_box.add_child(cv)
		cv.show_card(card_name, true)

func _show_results(results: Dictionary) -> void:
	if _betting_ctrl:
		_betting_ctrl.visible = false
	_draw_panel.visible = false

	if results.get("final", false):
		_results_label.text = "%s wins the game!" % results.get("winner_name", "Nobody")
		_next_btn.text = "Main Menu"
	else:
		var lines: Array[String] = []
		for pid in results:
			if pid is int:
				var info: Dictionary = results[pid]
				var suffix := " ★" if info.get("is_winner", false) else ""
				var pname: String = NetworkManager.player_names.get(pid, "Player")
				lines.append("%s: %s%s" % [pname, info.get("hand_name", ""), suffix])
		_results_label.text = "\n".join(lines)
		_next_btn.text = "Next Hand"
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

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_seat(peer_id: int):
	for seat in _seat_nodes:
		if seat.peer_id == peer_id:
			return seat
	return null
