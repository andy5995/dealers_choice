class_name FiveCardDraw
extends "res://games/base_game.gd"
## 5-Card Draw: ante → deal 5 → bet → draw → bet → showdown.

var _discard_responses: Dictionary = {}  # peer_id -> Array[int] indices
var _waiting_for_discards: bool = false

enum DrawPhase { NONE, FIRST_BETTING, AWAITING_DRAWS, SECOND_BETTING }
var _draw_phase: DrawPhase = DrawPhase.NONE

func _start_hand_impl() -> void:
	# Deal 5 cards to each active player
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
			_request_discards_from_all()

		DrawPhase.AWAITING_DRAWS:
			_draw_phase = DrawPhase.SECOND_BETTING
			_phase = Phase.BETTING
			_broadcast_state()
			_start_betting_round(_left_of_dealer())

		DrawPhase.SECOND_BETTING:
			_do_showdown()

# ── Draw mechanic ─────────────────────────────────────────────────────────────

func _request_discards_from_all() -> void:
	_discard_responses.clear()
	_waiting_for_discards = true
	_broadcast_state()

	var my_id := multiplayer.get_unique_id()
	for p in _players:
		if p.status == PS_ACTIVE:
			if p.peer_id == my_id:
				_table._show_draw_controls(p.hand)
			else:
				_table.request_discards.rpc_id(p.peer_id, p.hand)

func receive_discards(peer_id: int, indices: Array) -> void:
	if not _waiting_for_discards:
		return
	var seat := _seat_of(peer_id)
	if seat == -1:
		return
	var p = _players[seat]
	if p.status != PS_ACTIVE:
		return

	# Validate: max 4 discards (or 5 with special rule — allow up to 5 here)
	var safe_indices: Array[int] = []
	for idx in indices:
		if idx is int and idx >= 0 and idx < p.hand.size():
			safe_indices.append(idx)
	safe_indices = safe_indices.slice(0, 4)  # cap at 4

	_discard_responses[peer_id] = safe_indices

	# Check if all active players have responded
	var all_responded := true
	for op in _players:
		if op.status == PS_ACTIVE:
			if not _discard_responses.has(op.peer_id):
				all_responded = false
				break

	if all_responded:
		_waiting_for_discards = false
		_execute_draws()
		_advance_phase()

func _execute_draws() -> void:
	for peer_id in _discard_responses:
		var seat := _seat_of(peer_id)
		if seat == -1:
			continue
		var p = _players[seat]
		var indices: Array = _discard_responses[peer_id]
		# Remove in reverse order to preserve valid indices
		indices = indices.duplicate()
		indices.sort()
		indices.reverse()
		for idx in indices:
			if idx < p.hand.size():
				p.hand.remove_at(idx)
		# Draw replacements
		var new_cards: Array = _deck.draw_n(indices.size())
		p.hand.append_array(new_cards)
	_last_action_text = "Cards drawn"
