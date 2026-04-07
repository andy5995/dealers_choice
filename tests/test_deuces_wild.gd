extends "res://addons/gut/test.gd"

const _HandEval = preload("res://core/hand_evaluator.gd")

# Convenience: evaluate a hand with deuces as wilds (rank index 0).
func _eval(cards: Array) -> Array:
	return _HandEval.best_from_n_with_wilds(cards, 0)

# ── No wilds: must agree with best_from_n ─────────────────────────────────────

func test_no_wilds_matches_best_from_n() -> void:
	var cards = ["AS", "KH", "QD", "JC", "9S"]
	assert_eq(_eval(cards), _HandEval.best_from_n(cards))

# ── One deuce ─────────────────────────────────────────────────────────────────

func test_one_deuce_completes_royal_flush() -> void:
	# AS KS QS JS + wild → TS = royal flush
	var r = _eval(["AS", "KS", "QS", "JS", "2H"])
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

func test_one_deuce_completes_straight_flush() -> void:
	# 9S 8S 7S 6S + wild → TS (best) = straight flush
	var r = _eval(["9S", "8S", "7S", "6S", "2H"])
	assert_eq(r[0], _HandEval.HandRank.STRAIGHT_FLUSH)

func test_one_deuce_makes_four_of_a_kind() -> void:
	# AAA K + wild → AC = four aces
	var r = _eval(["AS", "AH", "AD", "KS", "2C"])
	assert_eq(r[0], _HandEval.HandRank.FOUR_OF_A_KIND)

func test_one_deuce_improves_pair_to_trips() -> void:
	# AA K Q + wild → A = three aces (can't do better with these naturals)
	var r = _eval(["AS", "AH", "KD", "QC", "2S"])
	assert_true(r[0] >= _HandEval.HandRank.THREE_OF_A_KIND)

func test_one_deuce_completes_broadway_straight() -> void:
	# AK QJ off-suit + wild → T = broadway straight
	var r = _eval(["AS", "KH", "QD", "JC", "2S"])
	assert_eq(r[0], _HandEval.HandRank.STRAIGHT)

# ── Two deuces ────────────────────────────────────────────────────────────────

func test_two_deuces_complete_royal_flush() -> void:
	# AS KS QS + 2 wilds → JS TS = royal flush
	var r = _eval(["AS", "KS", "QS", "2H", "2D"])
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

func test_two_deuces_make_four_of_a_kind() -> void:
	# KS KH Q + 2 wilds → KC KD = four kings
	var r = _eval(["KS", "KH", "QD", "2H", "2D"])
	assert_eq(r[0], _HandEval.HandRank.FOUR_OF_A_KIND)

func test_two_deuces_make_at_least_trips() -> void:
	# Any hand with 2 wilds must be at least three of a kind
	var r = _eval(["AS", "KH", "2D", "2C", "QS"])
	assert_true(r[0] >= _HandEval.HandRank.THREE_OF_A_KIND)

# ── Three deuces ──────────────────────────────────────────────────────────────

func test_three_deuces_complete_royal_flush() -> void:
	# AS KS + 3 wilds → QS JS TS = royal flush
	var r = _eval(["AS", "KS", "2H", "2D", "2C"])
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

# ── Four deuces ───────────────────────────────────────────────────────────────

func test_four_deuces_make_royal_flush() -> void:
	# AS + 4 wilds → KS QS JS TS = royal flush
	var r = _eval(["AS", "2H", "2D", "2C", "2S"])
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

# ── Deuce is never substituted with another deuce ─────────────────────────────

func test_wild_does_not_replace_with_deuce() -> void:
	# Even with a weak hand, the replacement must not be a 2
	# Result should be valid and at least a pair (wild can pair with any natural)
	var r = _eval(["AS", "KH", "QD", "JC", "2S"])
	assert_true(r[0] >= _HandEval.HandRank.STRAIGHT)  # broadway straight at minimum

# ── Wild beats the natural equivalent ─────────────────────────────────────────

func test_wild_hand_beats_natural_lower_hand() -> void:
	# One wild completes a flush; natural hand is only a pair
	var wild_hand   = _eval(["AS", "KS", "QS", "JS", "2H"])    # → royal flush
	var natural_hand = _HandEval.best_from_n(["AS", "AH", "KD", "QC", "JS"])  # → one pair
	assert_true(_HandEval.compare(wild_hand, natural_hand) > 0)
