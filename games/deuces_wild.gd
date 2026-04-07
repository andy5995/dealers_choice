class_name DeucesWild
extends "res://games/five_card_draw.gd"
## 5-Card Draw with deuces (2s) as wild cards.
## At showdown, wilds are automatically assigned the best possible value.

func _evaluate_hand(cards: Array) -> Array:
	return _HandEval.best_from_n_with_wilds(cards, 0)  # rank index 0 = "2"
