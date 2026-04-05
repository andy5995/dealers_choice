extends "res://addons/gut/test.gd"

const _DeckScript = preload("res://core/deck.gd")

var _deck = null

func before_each() -> void:
	_deck = _DeckScript.new()

# ── Basic properties ──────────────────────────────────────────────────────────

func test_full_deck_has_52_cards() -> void:
	assert_eq(_deck.cards_remaining(), 52)

func test_reset_restores_52_cards() -> void:
	_deck.draw_n(10)
	_deck.reset()
	assert_eq(_deck.cards_remaining(), 52)

func test_draw_reduces_count_by_one() -> void:
	_deck.draw()
	assert_eq(_deck.cards_remaining(), 51)

func test_draw_n_reduces_count_correctly() -> void:
	_deck.draw_n(5)
	assert_eq(_deck.cards_remaining(), 47)

# ── Uniqueness ────────────────────────────────────────────────────────────────

func test_full_draw_produces_no_duplicates() -> void:
	var seen: Dictionary = {}
	while _deck.cards_remaining() > 0:
		var card = _deck.draw()
		assert_false(seen.has(card), "Duplicate card: %s" % card)
		seen[card] = true

func test_all_52_cards_present() -> void:
	var drawn: Array = _deck.draw_n(52)
	assert_eq(drawn.size(), 52)
	# Every rank × suit combination should appear exactly once
	for rank in CardDB.RANKS:
		for suit in CardDB.SUITS:
			assert_true(drawn.has(rank + suit), "Missing card: %s%s" % [rank, suit])
