extends Node
## Autoload name: CardDB
## Central registry for card data and texture loading.

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
const SUITS := ["C", "D", "H", "S"]
const BACK_CARD := "1B"

func make_deck() -> Array[String]:
	var deck: Array[String] = []
	for r in RANKS:
		for s in SUITS:
			deck.append(r + s)
	return deck

## Returns 0 for "2", 12 for "A"
func rank_index(card: String) -> int:
	return RANKS.find(card.substr(0, 1))

func suit_char(card: String) -> String:
	return card.substr(1, 1) if card.length() >= 2 else ""

func rank_display(card: String) -> String:
	var r := card.substr(0, 1)
	return "10" if r == "T" else r

func load_texture(card_name: String) -> Texture2D:
	var path := "res://assets/cards/%s.png" % card_name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load("res://assets/cards/%s.png" % BACK_CARD) as Texture2D
