class_name SevenCardStud
extends preload("res://games/base_game.gd")
## 7-Card Stud: ante → (2 down + 1 up) → bet → (3 more up, betting after each) → (1 down) → bet → showdown.
## 5 betting rounds total (3rd through 7th street).
## On 4th–6th street, player with best visible hand acts first.

var _street: int = 0  # 3 = third street ... 7 = seventh street

func _start_hand_impl() -> void:
	_street = 3
	for p in _players:
		p.face_down_cards = _deck.draw_n(2)
		p.face_up_cards   = [_deck.draw()]
		p.hand            = p.face_down_cards + p.face_up_cards
	_phase = Phase.BETTING
	_broadcast_state()
	# Third street: player with lowest up-card brings in first
	_start_betting_round(_bring_in_seat())

func _advance_phase() -> void:
	_street += 1
	match _street:
		4, 5, 6:
			_deal_up_cards()
		7:
			_deal_seventh_street()
		8:
			_do_showdown()
			return

	_phase = Phase.BETTING
	_broadcast_state()
	_start_betting_round(_best_visible_hand_seat())

func _deal_up_cards() -> void:
	for p in _players:
		if p.status != PlayerState.Status.FOLDED:
			var card := _deck.draw()
			p.face_up_cards.append(card)
			p.hand.append(card)

func _deal_seventh_street() -> void:
	# If deck runs low, deal one shared community down-card
	var active_count := _count_non_folded()
	if _deck.cards_remaining() < active_count:
		var shared := _deck.draw()
		for p in _players:
			if p.status != PlayerState.Status.FOLDED:
				p.face_down_cards.append(shared)
				p.hand.append(shared)
	else:
		for p in _players:
			if p.status != PlayerState.Status.FOLDED:
				var card := _deck.draw()
				p.face_down_cards.append(card)
				p.hand.append(card)

# ── Seat selection helpers ────────────────────────────────────────────────────

## Third street: lowest face-up card brings in (ties broken by suit C < D < H < S).
func _bring_in_seat() -> int:
	var lowest_seat := -1
	for i in range(_players.size()):
		var p := _players[i]
		if p.status == PlayerState.Status.ACTIVE and not p.face_up_cards.is_empty():
			if lowest_seat == -1 or _stud_card_lt(p.face_up_cards[0], _players[lowest_seat].face_up_cards[0]):
				lowest_seat = i
	return lowest_seat if lowest_seat != -1 else _left_of_dealer()

## 4th–7th street: highest visible hand acts first.
func _best_visible_hand_seat() -> int:
	var best_seat := -1
	var best_value: Array = []
	for i in range(_players.size()):
		var p := _players[i]
		if p.status != PlayerState.Status.FOLDED and not p.face_up_cards.is_empty():
			var value := HandEvaluator.best_from_n(p.face_up_cards)
			if best_seat == -1 or HandEvaluator.compare(value, best_value) > 0:
				best_seat = i
				best_value = value
	return best_seat if best_seat != -1 else _left_of_dealer()

## Returns true if card a is lower than card b (for bring-in ordering).
func _stud_card_lt(a: String, b: String) -> bool:
	var ra := CardDB.rank_index(a)
	var rb := CardDB.rank_index(b)
	if ra != rb:
		return ra < rb
	const SUIT_ORDER := {"C": 0, "D": 1, "H": 2, "S": 3}
	return SUIT_ORDER.get(CardDB.suit_char(a), 0) < SUIT_ORDER.get(CardDB.suit_char(b), 0)
