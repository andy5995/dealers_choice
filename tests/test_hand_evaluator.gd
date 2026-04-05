extends "res://addons/gut/test.gd"

const _HandEval = preload("res://core/hand_evaluator.gd")

# ── Hand classification ───────────────────────────────────────────────────────

func test_royal_flush() -> void:
	var r = _HandEval.evaluate_five(["AS", "KS", "QS", "JS", "TS"])
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

func test_straight_flush() -> void:
	var r = _HandEval.evaluate_five(["9S", "8S", "7S", "6S", "5S"])
	assert_eq(r[0], _HandEval.HandRank.STRAIGHT_FLUSH)
	assert_eq(r[1], 7)  # 9 = rank index 7

func test_four_of_a_kind() -> void:
	var r = _HandEval.evaluate_five(["AS", "AH", "AD", "AC", "KS"])
	assert_eq(r[0], _HandEval.HandRank.FOUR_OF_A_KIND)

func test_full_house() -> void:
	var r = _HandEval.evaluate_five(["AS", "AH", "AD", "KS", "KH"])
	assert_eq(r[0], _HandEval.HandRank.FULL_HOUSE)

func test_flush() -> void:
	var r = _HandEval.evaluate_five(["AS", "KS", "QS", "JS", "9S"])
	assert_eq(r[0], _HandEval.HandRank.FLUSH)

func test_straight() -> void:
	var r = _HandEval.evaluate_five(["AS", "KH", "QD", "JC", "TS"])
	assert_eq(r[0], _HandEval.HandRank.STRAIGHT)
	assert_eq(r[1], 12)  # A-high

func test_wheel_straight() -> void:
	var r = _HandEval.evaluate_five(["AS", "2H", "3D", "4C", "5S"])
	assert_eq(r[0], _HandEval.HandRank.STRAIGHT)
	assert_eq(r[1], 3)  # straight_high = 3 (the 5, rank index 3)

func test_three_of_a_kind() -> void:
	var r = _HandEval.evaluate_five(["AS", "AH", "AD", "KS", "QH"])
	assert_eq(r[0], _HandEval.HandRank.THREE_OF_A_KIND)

func test_two_pair() -> void:
	var r = _HandEval.evaluate_five(["AS", "AH", "KD", "KC", "QS"])
	assert_eq(r[0], _HandEval.HandRank.TWO_PAIR)

func test_one_pair() -> void:
	var r = _HandEval.evaluate_five(["AS", "AH", "KD", "QC", "JS"])
	assert_eq(r[0], _HandEval.HandRank.ONE_PAIR)

func test_high_card() -> void:
	var r = _HandEval.evaluate_five(["AS", "KH", "QD", "JC", "9S"])
	assert_eq(r[0], _HandEval.HandRank.HIGH_CARD)

# ── Hand ranking order ────────────────────────────────────────────────────────

func test_royal_flush_beats_straight_flush() -> void:
	var rf = _HandEval.evaluate_five(["AS", "KS", "QS", "JS", "TS"])
	var sf = _HandEval.evaluate_five(["9S", "8S", "7S", "6S", "5S"])
	assert_true(_HandEval.compare(rf, sf) > 0)

func test_straight_flush_beats_four_of_a_kind() -> void:
	var sf  = _HandEval.evaluate_five(["9S", "8S", "7S", "6S", "5S"])
	var fok = _HandEval.evaluate_five(["AS", "AH", "AD", "AC", "KS"])
	assert_true(_HandEval.compare(sf, fok) > 0)

func test_higher_straight_beats_lower() -> void:
	var high = _HandEval.evaluate_five(["AS", "KH", "QD", "JC", "TS"])
	var low  = _HandEval.evaluate_five(["6S", "5H", "4D", "3C", "2S"])
	assert_true(_HandEval.compare(high, low) > 0)

func test_wheel_loses_to_six_high_straight() -> void:
	var wheel  = _HandEval.evaluate_five(["AS", "2H", "3D", "4C", "5S"])
	var normal = _HandEval.evaluate_five(["6S", "5H", "4D", "3C", "2S"])
	assert_true(_HandEval.compare(normal, wheel) > 0)

func test_equal_hands_compare_zero() -> void:
	var a = _HandEval.evaluate_five(["AS", "KS", "QS", "JS", "TS"])
	var b = _HandEval.evaluate_five(["AH", "KH", "QH", "JH", "TH"])
	assert_eq(_HandEval.compare(a, b), 0)

# ── best_from_n ───────────────────────────────────────────────────────────────

func test_best_from_seven_finds_royal_flush() -> void:
	var cards = ["AS", "KS", "QS", "JS", "TS", "2H", "3D"]
	var r = _HandEval.best_from_n(cards)
	assert_eq(r[0], _HandEval.HandRank.ROYAL_FLUSH)

func test_best_from_five_same_as_evaluate_five() -> void:
	var cards = ["AS", "KH", "QD", "JC", "9S"]
	assert_eq(
		_HandEval.best_from_n(cards),
		_HandEval.evaluate_five(cards)
	)
