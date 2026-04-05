class_name BaseGame
extends Node
## Server-side game controller. Never instantiated on clients.
## All class-name types resolved via preload to avoid editor cache dependency.

const _Deck        := preload("res://core/deck.gd")
const _PlayerState := preload("res://core/player_state.gd")
const _HandEval    := preload("res://core/hand_evaluator.gd")

## PlayerState.Status enum mirrors — avoids needing PlayerState in the registry.
const PS_ACTIVE      := 0
const PS_FOLDED      := 1
const PS_ALL_IN      := 2
const PS_SITTING_OUT := 3

const TURN_TIMEOUT_SEC = 30.0

var _table                   # GameTable ref — untyped for duck-typed RPC calls
var _deck                    # Deck instance
var _players: Array  = []    # Array of PlayerState
var _dealer_index: int = 0
var _current_actor: int = -1
var _pot: int = 0
var _last_action_text: String = ""

## Betting-round state
var _current_bet: int = 0
var _min_bet: int = 20
var _round_bets: Array[int] = []
var _has_acted: Array[bool]  = []

## Turn timer
var _turn_timer: Timer = null
var _turn_start_usec: int = 0

enum Phase { WAITING, ANTE, DEALING, BETTING, DRAW, SHOWDOWN, HAND_END }
var _phase: Phase = Phase.WAITING

func _init(table_node) -> void:
	_table = table_node
	_deck  = _Deck.new()

func _ready() -> void:
	_turn_timer = Timer.new()
	_turn_timer.one_shot = true
	_turn_timer.timeout.connect(_on_turn_timeout)
	add_child(_turn_timer)

# ── Public API ────────────────────────────────────────────────────────────────

func begin_game(player_list: Array) -> void:
	_players = player_list
	_dealer_index = 0
	for i in range(_players.size()):
		if _players[i].peer_id == GameManager.dealer_peer_id:
			_dealer_index = i
			break
	await get_tree().create_timer(0.5).timeout
	start_hand()

func start_hand() -> void:
	_deck.reset()
	_deck.shuffle()
	_pot = 0
	_last_action_text = ""
	for p in _players:
		p.reset_for_hand()
	_phase = Phase.ANTE
	_collect_antes()

func receive_player_action(peer_id: int, action: String, amount: int) -> void:
	var seat := _seat_of(peer_id)
	if seat != _current_actor:
		return
	_execute_action(seat, action, amount)

func receive_discards(peer_id: int, indices: Array) -> void:
	pass  # overridden by FiveCardDraw

# ── Ante collection ───────────────────────────────────────────────────────────

func _collect_antes() -> void:
	var ante := GameManager.ante_amount
	for p in _players:
		var actual := mini(ante, p.chips)
		p.chips -= actual
		p.total_pot_contrib += actual
		_pot += actual
		if p.chips == 0:
			p.status = PS_ALL_IN
	_phase = Phase.DEALING
	_start_hand_impl()

# ── Overridden by subclasses ──────────────────────────────────────────────────

func _start_hand_impl() -> void:
	pass

func _advance_phase() -> void:
	pass

# ── Betting round management ──────────────────────────────────────────────────

func _start_betting_round(first_to_act: int) -> void:
	_current_bet = 0
	_min_bet = GameManager.min_bet
	_round_bets.resize(_players.size())
	_round_bets.fill(0)
	_has_acted.resize(_players.size())
	_has_acted.fill(false)
	_current_actor = first_to_act
	_find_next_actor()

func _execute_action(seat: int, action: String, amount: int) -> void:
	_turn_timer.stop()
	_turn_start_usec = 0
	var p = _players[seat]
	match action:
		"fold":
			p.status = PS_FOLDED
			_last_action_text = "%s folds" % p.display_name
			_has_acted[seat] = true

		"check":
			if _round_bets[seat] < _current_bet:
				return
			_last_action_text = "%s checks" % p.display_name
			_has_acted[seat] = true

		"call":
			var to_call := mini(_current_bet - _round_bets[seat], p.chips)
			p.chips -= to_call
			p.total_pot_contrib += to_call
			_round_bets[seat] += to_call
			_pot += to_call
			if p.chips == 0:
				p.status = PS_ALL_IN
			_last_action_text = "%s calls %d" % [p.display_name, to_call]
			_has_acted[seat] = true

		"bet", "raise":
			var new_total := mini(amount, p.chips + _round_bets[seat])
			if new_total <= _current_bet:
				return
			var additional := new_total - _round_bets[seat]
			p.chips -= additional
			p.total_pot_contrib += additional
			_round_bets[seat] = new_total
			_pot += additional
			if new_total > _current_bet:
				_min_bet = maxi(new_total - _current_bet, GameManager.min_bet)
			_current_bet = new_total
			if p.chips == 0:
				p.status = PS_ALL_IN
			for i in range(_players.size()):
				if i != seat and _players[i].status == PS_ACTIVE:
					_has_acted[i] = false
			_last_action_text = "%s %ss to %d" % [
				p.display_name,
				"bet" if action == "bet" else "raise",
				new_total
			]
			_has_acted[seat] = true

	_current_actor = (seat + 1) % _players.size()
	_find_next_actor()

func _find_next_actor() -> void:
	if _count_non_folded() <= 1:
		_award_last_standing()
		return
	if _is_betting_complete():
		_end_betting_round()
		return
	var n := _players.size()
	for i in range(n):
		var s := (_current_actor + i) % n
		var p = _players[s]
		if p.status == PS_ACTIVE and not _has_acted[s]:
			_current_actor = s
			_turn_start_usec = Time.get_ticks_usec()
			_turn_timer.start(TURN_TIMEOUT_SEC)
			_broadcast_state()
			_notify_actor(s)
			return
	_end_betting_round()

func _is_betting_complete() -> bool:
	for i in range(_players.size()):
		if _players[i].status == PS_ACTIVE:
			if not _has_acted[i]:
				return false
	return true

func _end_betting_round() -> void:
	for i in range(_players.size()):
		_players[i].current_bet = 0
		_round_bets[i] = 0
	_current_bet = 0
	_current_actor = -1
	_broadcast_state()
	if _count_non_folded() <= 1:
		_award_last_standing()
		return
	_advance_phase()

# ── Pot and winner logic ──────────────────────────────────────────────────────

func _award_last_standing() -> void:
	var reveal: Dictionary = {}
	for i in range(_players.size()):
		var p = _players[i]
		if p.status != PS_FOLDED:
			p.chips += _pot
			_last_action_text = "%s wins %d" % [p.display_name, _pot]
			_pot = 0
			reveal[p.peer_id] = {"hand": [], "hand_name": "last standing", "is_winner": true}
		else:
			reveal[p.peer_id] = {"hand": [], "hand_name": "", "is_winner": false}
	_broadcast_state()
	_table.receive_game_over.rpc(reveal)
	await get_tree().create_timer(15.0).timeout
	_end_hand()

func _do_showdown() -> void:
	_phase = Phase.SHOWDOWN
	for p in _players:
		if p.status != PS_FOLDED:
			p.face_up_cards = p.hand.duplicate()

	var contenders: Array[int] = []
	for i in range(_players.size()):
		if _players[i].status != PS_FOLDED:
			contenders.append(i)

	var best_value: Array = []
	var winners: Array[int] = []
	var hand_values: Dictionary = {}

	for seat in contenders:
		var value: Array = _HandEval.best_from_n(_players[seat].hand)
		hand_values[seat] = value
		var cmp: int = 0 if best_value.is_empty() else _HandEval.compare(value, best_value)
		if best_value.is_empty() or cmp > 0:
			best_value = value
			winners = [seat]
		elif cmp == 0:
			winners.append(seat)

	var share := _pot / winners.size()
	var remainder := _pot % winners.size()
	for seat in winners:
		_players[seat].chips += share
	if remainder > 0:
		_players[winners[0]].chips += remainder
	_pot = 0

	var reveal: Dictionary = {}
	for seat in contenders:
		reveal[_players[seat].peer_id] = {
			"hand":      _players[seat].hand,
			"hand_name": _HandEval.hand_name(hand_values[seat]),
			"is_winner": winners.has(seat),
		}

	_last_action_text = "%s wins with %s!" % [
		_players[winners[0]].display_name,
		_HandEval.hand_name(best_value)
	]
	_broadcast_state()
	_table.receive_game_over.rpc(reveal)
	await get_tree().create_timer(15.0).timeout
	_end_hand()

func _end_hand() -> void:
	_phase = Phase.HAND_END
	_broadcast_state()

	var still_playing: Array = []
	for p in _players:
		if p.chips > 0:
			still_playing.append(p)
	_players = still_playing

	if _players.size() < 2:
		var winner_name: String = _players[0].display_name if _players.size() == 1 else "Nobody"
		_table.receive_game_over.rpc({"final": true, "winner_name": winner_name})
		return

	GameManager.advance_dealer()
	await get_tree().create_timer(0.5).timeout
	_table.return_to_lobby.rpc()

# ── Broadcasting ──────────────────────────────────────────────────────────────

func _broadcast_state() -> void:
	var public_state = _build_public_state()
	_table.receive_public_state.rpc(public_state)

	var my_id := multiplayer.get_unique_id()
	for p in _players:
		var priv = p.to_private_dict()
		if p.peer_id == my_id:
			_table._apply_private_state(p.peer_id, priv)
		else:
			_table.receive_private_state.rpc_id(p.peer_id, priv)

func _notify_actor(seat: int) -> void:
	var p = _players[seat]
	var actions = _valid_actions_for(p, seat)
	var my_id := multiplayer.get_unique_id()
	if p.peer_id == my_id:
		_table._show_betting_controls(actions, _current_bet, _min_bet, p.chips)
	else:
		_table.receive_your_turn.rpc_id(p.peer_id, actions, _current_bet, _min_bet, p.chips)

func _on_turn_timeout() -> void:
	if _current_actor < 0 or _current_actor >= _players.size():
		return
	var owed: int = _current_bet - _round_bets[_current_actor]
	if owed == 0:
		_execute_action(_current_actor, "check", 0)
	else:
		_execute_action(_current_actor, "fold", 0)

func _valid_actions_for(p, seat: int) -> Array:
	var actions: Array = ["fold"]
	var owed := _current_bet - _round_bets[seat]
	if owed == 0:
		actions.append("check")
	else:
		actions.append("call")
	if p.chips > owed:
		actions.append("bet" if _current_bet == 0 else "raise")
	return actions

func _build_public_state() -> Dictionary:
	var player_dicts: Array = []
	for i in range(_players.size()):
		var d = _players[i].to_public_dict()
		d["round_bet"]  = _round_bets[i] if _round_bets.size() > i else 0
		d["is_dealer"]  = (i == _dealer_index)
		player_dicts.append(d)
	var elapsed_sec: float = (Time.get_ticks_usec() - _turn_start_usec) / 1_000_000.0 if _turn_start_usec > 0 else TURN_TIMEOUT_SEC
	var time_left: float = maxf(TURN_TIMEOUT_SEC - elapsed_sec, 0.0) if _current_actor >= 0 else 0.0
	return {
		"phase":           int(_phase),
		"pot":             _pot,
		"current_bet":     _current_bet,
		"dealer_index":    _dealer_index,
		"actor_index":     _current_actor,
		"community_cards": _get_community_cards(),
		"last_action":     _last_action_text,
		"players":         player_dicts,
		"turn_time_left":  time_left,
		"turn_duration":   TURN_TIMEOUT_SEC,
	}

func _get_community_cards() -> Array:
	return []

# ── Helpers ───────────────────────────────────────────────────────────────────

func _left_of_dealer() -> int:
	return (_dealer_index + 1) % _players.size()

func _count_non_folded() -> int:
	var c := 0
	for p in _players:
		if p.status != PS_FOLDED:
			c += 1
	return c

func _seat_of(peer_id: int) -> int:
	for i in range(_players.size()):
		if _players[i].peer_id == peer_id:
			return i
	return -1
