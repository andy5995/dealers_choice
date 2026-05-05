class_name FiveCardDraw
extends "res://games/base_game.gd"
## 5-Card Draw: ante → deal 5 → bet → draw (sequential, L→R from dealer) → bet → showdown.

var _draw_queue: Array = []      # peer_ids ordered left-of-dealer, waiting to draw
var _waiting_for_discards: bool = false
var _draw_timer: Timer = null

enum DrawPhase { NONE, FIRST_BETTING, AWAITING_DRAWS, SECOND_BETTING }
var _draw_phase: DrawPhase = DrawPhase.NONE

func _ready() -> void:
	super._ready()
	_draw_timer = Timer.new()
	_draw_timer.one_shot = true
	_draw_timer.timeout.connect(_on_draw_timeout)
	add_child(_draw_timer)

func _start_hand_impl() -> void:
	for p in _players:
		p.hand = _deck.draw_n(5)
	_phase = Phase.BETTING
	_draw_phase = DrawPhase.FIRST_BETTING
	_broadcast_state()
	_start_betting_round(_left_of_dealer())

func _advance_phase() -> void:
	match _draw_phase:
		DrawPhase.FIRST_BETTING:
			_draw_phase = DrawPhase.AWAITING_DRAWS
			_phase = Phase.DRAW
			_begin_draw_round()

		DrawPhase.AWAITING_DRAWS:
			_draw_phase = DrawPhase.SECOND_BETTING
			_phase = Phase.BETTING
			_broadcast_state()
			_start_betting_round(_left_of_dealer())

		DrawPhase.SECOND_BETTING:
			_do_showdown()

# ── Draw mechanic (sequential) ────────────────────────────────────────────────

func _begin_draw_round() -> void:
	_draw_queue = []
	var n := _players.size()
	var start := (_dealer_index + 1) % n
	for i in range(n):
		var idx := (start + i) % n
		if _players[idx].status == PS_ACTIVE:
			_draw_queue.append(_players[idx].peer_id)
	_waiting_for_discards = true
	_broadcast_state()
	_request_next_draw()

func _request_next_draw() -> void:
	if _draw_queue.is_empty():
		_waiting_for_discards = false
		_advance_phase()
		return
	var next_pid: int = _draw_queue[0]
	var seat := _seat_of(next_pid)
	if seat == -1:
		_draw_queue.remove_at(0)
		_request_next_draw()
		return
	var p = _players[seat]
	var my_id := multiplayer.get_unique_id()
	var hmax := _hard_max_discards()
	if next_pid == my_id:
		_table._show_draw_controls(p.hand, hmax)
	else:
		_table.request_discards.rpc_id(next_pid, p.hand, hmax)
	_draw_timer.start(Config.draw_timeout_sec)

## Hard cap on discards for this variant. Subclasses may override.
func _hard_max_discards() -> int:
	return 4

func _get_phase_timer_info() -> Dictionary:
	if _draw_phase == DrawPhase.AWAITING_DRAWS and _waiting_for_discards and not _draw_queue.is_empty():
		# Use the full duration when the timer is stopped (not yet started for the
		# current player, or just fired), so the client clock starts from 1.0.
		var time_left := Config.draw_timeout_sec if _draw_timer.is_stopped() else _draw_timer.time_left
		return {
			"actor_index":    _seat_of(_draw_queue[0]),
			"turn_time_left": time_left,
			"turn_duration":  Config.draw_timeout_sec,
		}
	return super._get_phase_timer_info()

## Max discards allowed. 3 normally; 4 if the player is keeping an ace.
func _max_discards(hand: Array, discard_indices: Array) -> int:
	if discard_indices.size() <= 3:
		return 3
	for i in range(hand.size()):
		if i not in discard_indices and CardDB.rank_index(hand[i]) == 12:
			return 4
	return 3

func _on_draw_timeout() -> void:
	if not _draw_queue.is_empty():
		receive_discards(_draw_queue[0], [])

func receive_discards(peer_id: int, indices: Array) -> void:
	_draw_timer.stop()
	if not _waiting_for_discards:
		return
	if _draw_queue.is_empty() or _draw_queue[0] != peer_id:
		return
	var seat := _seat_of(peer_id)
	if seat == -1:
		return
	var p = _players[seat]
	if p.status != PS_ACTIVE:
		return

	# Validate indices then enforce discard limit.
	var safe_indices: Array[int] = []
	for idx in indices:
		if idx is int and idx >= 0 and idx < p.hand.size():
			safe_indices.append(idx)
	safe_indices = safe_indices.slice(0, _max_discards(p.hand, safe_indices))

	# Remove discarded cards in reverse order, then draw replacements
	var sorted_idx := safe_indices.duplicate()
	sorted_idx.sort()
	sorted_idx.reverse()
	for idx in sorted_idx:
		p.hand.remove_at(idx)
	var new_cards: Array = _deck.draw_n(safe_indices.size())
	p.hand.append_array(new_cards)
	_last_action_text = "%s draws %d" % [p.display_name, safe_indices.size()]

	_draw_queue.remove_at(0)
	_broadcast_state()
	_request_next_draw()
