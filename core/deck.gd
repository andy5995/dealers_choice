class_name Deck
## Standard 52-card deck. Server-side only — never sent over the network.

var _cards: Array[String] = []

func _init() -> void:
	reset()

func reset() -> void:
	_cards = CardDB.make_deck()

func shuffle() -> void:
	_cards.shuffle()

func draw() -> String:
	if _cards.is_empty():
		push_error("Deck is empty")
		return ""
	return _cards.pop_back()

func draw_n(n: int) -> Array[String]:
	var result: Array[String] = []
	for i in n:
		result.append(draw())
	return result

func cards_remaining() -> int:
	return _cards.size()
