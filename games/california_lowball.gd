class_name CaliforniaLowball
extends "res://games/five_card_draw.gd"
## California (Ace-to-Five) Lowball: lowest hand wins.
## Aces are always low; straights and flushes don't count against you.
## Best possible hand: A-2-3-4-5.

func _evaluate_hand(cards: Array) -> Array:
	return _HandEval.evaluate_lowball(cards)

func _showdown_hand_name(_value: Array, cards: Array) -> String:
	var high := -2
	for card in cards:
		var r: int = CardDB.rank_index(card)
		var lr := -1 if r == 12 else r  # Ace → -1
		if lr > high:
			high = lr
	if high == -1:
		return "A-low"
	return "%s-low" % CardDB.RANKS[high]
