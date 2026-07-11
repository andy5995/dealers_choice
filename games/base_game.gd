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

var TURN_TIMEOUT_SEC: float:
	get: return Config.turn_timeout_sec

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
	NetworkManager.player_disconnected.connect(_on_peer_disconnected)

## Awaitable pause that ties the timer lifetime to this node, preventing
## SceneTreeTimer leaks when the game node is freed mid-await.
func _wait(seconds: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	add_child(t)
	t.start(seconds)
	await t.timeout
	t.queue_free()

# ── Public API ────────────────────────────────────────────────────────────────

func begin_game(player_list: Array) -> void:
	_players = player_list
	_dealer_index = 0
	for i in range(_players.size()):
		if _players[i].peer_id == GameManager.dealer_peer_id:
			_dealer_index = i
			break
	await _wait(0.5)
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
			# DC model: raise = call (pay owed) then bet the increment.
			# For bet (no prior bet, owed == 0) this is just the bet size.
			# amount = raise/bet INCREMENT, not a raise-to total.
			if action == "raise":
				var owed: int = _current_bet - _round_bets[seat]
				var call_chips: int = mini(owed, p.chips)
				p.chips -= call_chips
				p.total_pot_contrib += call_chips
				_round_bets[seat] += call_chips
				_pot += call_chips

			var bet_chips: int = mini(amount, p.chips)
			if bet_chips == 0:
				return
			p.chips -= bet_chips
			p.total_pot_contrib += bet_chips
			_round_bets[seat] += bet_chips
			_pot += bet_chips
			_min_bet = maxi(bet_chips, GameManager.min_bet)
			_current_bet = _round_bets[seat]
			if p.chips == 0:
				p.status = PS_ALL_IN
			for i in range(_players.size()):
				if i != seat and _players[i].status == PS_ACTIVE:
					_has_acted[i] = false
			_last_action_text = "%s %ss %d" % [
				p.display_name,
				"bet" if action == "bet" else "raise",
				bet_chips,
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
	await _wait(15.0)
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
		var value: Array = _evaluate_hand(_players[seat].hand)
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
			"hand_name": _showdown_hand_name(hand_values[seat], _players[seat].hand),
			"is_winner": winners.has(seat),
		}

	_last_action_text = "%s wins with %s!" % [
		_players[winners[0]].display_name,
		_showdown_hand_name(best_value, _players[winners[0]].hand)
	]
	_broadcast_state()
	_table.receive_game_over.rpc(reveal)
	await _wait(15.0)
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
		var timeout: float = Config.end_of_game_timeout
		_table.receive_game_over.rpc({"final": true, "winner_name": winner_name, "timeout": timeout})
		await _wait(timeout)
		_table.return_to_lobby.rpc()
		return

	GameManager.advance_dealer()
	await _wait(0.5)
	_table.return_to_lobby.rpc()

# ── Broadcasting ──────────────────────────────────────────────────────────────

func _broadcast_state() -> void:
	var public_state = _build_public_state()
	_table.receive_public_state.rpc(public_state)

	var my_id := multiplayer.get_unique_id()
	var connected := multiplayer.get_peers()
	for p in _players:
		var priv = p.to_private_dict()
		if p.peer_id == my_id:
			_table._apply_private_state(p.peer_id, priv)
		elif connected.has(p.peer_id):
			_table.receive_private_state.rpc_id(p.peer_id, priv)

func _notify_actor(seat: int) -> void:
	var p = _players[seat]
	var actions = _valid_actions_for(p, seat)
	var owed := _current_bet - _round_bets[seat]
	var my_id := multiplayer.get_unique_id()
	if p.peer_id == my_id:
		_table._show_betting_controls(actions, owed, _min_bet, p.chips)
	elif multiplayer.get_peers().has(p.peer_id):
		_table.receive_your_turn.rpc_id(p.peer_id, actions, owed, _min_bet, p.chips)

func _on_peer_disconnected(peer_id: int) -> void:
	var seat := _seat_of(peer_id)
	if seat < 0:
		return
	# Force-fold the disconnected player.
	_players[seat].status = PS_FOLDED
	_last_action_text = "%s disconnected" % _players[seat].display_name
	if seat == _current_actor:
		# It's their turn — drive the action forward.
		_turn_timer.stop()
		_current_actor = (seat + 1) % _players.size()
		_find_next_actor()

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

## Returns {actor_index, turn_time_left, turn_duration} for the current phase.
## Subclasses with their own timers (e.g. draw round) override this.
func _get_phase_timer_info() -> Dictionary:
	var elapsed_sec: float = (Time.get_ticks_usec() - _turn_start_usec) / 1_000_000.0 if _turn_start_usec > 0 else TURN_TIMEOUT_SEC
	var time_left: float = maxf(TURN_TIMEOUT_SEC - elapsed_sec, 0.0) if _current_actor >= 0 else 0.0
	return {"actor_index": _current_actor, "turn_time_left": time_left, "turn_duration": TURN_TIMEOUT_SEC}

func _build_public_state() -> Dictionary:
	var player_dicts: Array = []
	for i in range(_players.size()):
		var d = _players[i].to_public_dict()
		d["round_bet"]  = _round_bets[i] if _round_bets.size() > i else 0
		d["is_dealer"]  = (i == _dealer_index)
		player_dicts.append(d)
	var timer := _get_phase_timer_info()
	return {
		"phase":           int(_phase),
		"pot":             _pot,
		"current_bet":     _current_bet,
		"dealer_index":    _dealer_index,
		"actor_index":     timer["actor_index"],
		"community_cards": _get_community_cards(),
		"last_action":     _last_action_text,
		"players":         player_dicts,
		"turn_time_left":  timer["turn_time_left"],
		"turn_duration":   timer["turn_duration"],
	}

func _evaluate_hand(cards: Array) -> Array:
	return _HandEval.best_from_n(cards)

func _showdown_hand_name(value: Array, _cards: Array) -> String:
	return _HandEval.hand_name(value)

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
