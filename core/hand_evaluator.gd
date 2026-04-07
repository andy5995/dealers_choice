class_name HandEvaluator
## Pure static class for evaluating poker hand strength.
## All ranks use CardDB index: "2"=0 ... "A"=12.
##
## evaluate_five() returns Array [hand_rank, tiebreak1, ...].
## Compare two results element-by-element; higher = better hand.

enum HandRank {
	HIGH_CARD        = 0,
	ONE_PAIR         = 1,
	TWO_PAIR         = 2,
	THREE_OF_A_KIND  = 3,
	STRAIGHT         = 4,
	FLUSH            = 5,
	FULL_HOUSE       = 6,
	FOUR_OF_A_KIND   = 7,
	STRAIGHT_FLUSH   = 8,
	ROYAL_FLUSH      = 9,
}

const HAND_NAMES := [
	"High Card", "One Pair", "Two Pair", "Three of a Kind",
	"Straight", "Flush", "Full House", "Four of a Kind",
	"Straight Flush", "Royal Flush"
]

## Best 5-card hand from any number of cards (>= 5 for Hold'em/Stud).
static func best_from_n(cards: Array) -> Array:
	if cards.size() <= 5:
		return evaluate_five(cards)
	var best: Array = []
	_each_combination(cards, 5, func(combo: Array) -> void:
		var result := evaluate_five(combo)
		if best.is_empty() or compare(result, best) > 0:
			best.clear()
			best.append_array(result)
	)
	return best

## Evaluate exactly 5 cards.
static func evaluate_five(cards: Array) -> Array:
	var ranks: Array[int] = []
	var suits: Array[String] = []
	for card in cards:
		ranks.append(CardDB.rank_index(card))
		suits.append(CardDB.suit_char(card))

	# Sort descending for tiebreak comparisons
	ranks.sort()
	ranks.reverse()

	# Flush: all same suit
	var is_flush := true
	for i in range(1, suits.size()):
		if suits[i] != suits[0]:
			is_flush = false
			break

	# Rank frequency map, sorted by (freq desc, rank desc)
	var freq: Dictionary = {}
	for r in ranks:
		freq[r] = freq.get(r, 0) + 1
	var rank_keys: Array = freq.keys()
	rank_keys.sort_custom(func(a: int, b: int) -> bool:
		return freq[a] > freq[b] if freq[a] != freq[b] else a > b
	)
	var counts: Array = rank_keys.map(func(r: int) -> int: return freq[r])

	# Straight: 5 unique ranks, span == 4
	# Special case: wheel A-2-3-4-5 → [12,3,2,1,0] → straight_high = 3 (the 5)
	var is_straight := false
	var straight_high := 0
	if freq.size() == 5:
		if ranks[0] - ranks[4] == 4:
			is_straight = true
			straight_high = ranks[0]
		elif ranks[0] == 12 and ranks[1] == 3 and ranks[2] == 2 and ranks[3] == 1 and ranks[4] == 0:
			is_straight = true
			straight_high = 3  # 5 is the top of the wheel

	# Classify
	if is_straight and is_flush:
		if straight_high == 12:  # A-high = Royal Flush
			return [HandRank.ROYAL_FLUSH, 12]
		return [HandRank.STRAIGHT_FLUSH, straight_high]

	if counts[0] == 4:
		return [HandRank.FOUR_OF_A_KIND, rank_keys[0], rank_keys[1]]

	if counts[0] == 3 and counts.size() >= 2 and counts[1] == 2:
		return [HandRank.FULL_HOUSE, rank_keys[0], rank_keys[1]]

	if is_flush:
		var r: Array = [HandRank.FLUSH]
		r.append_array(ranks)
		return r

	if is_straight:
		return [HandRank.STRAIGHT, straight_high]

	if counts[0] == 3:
		var r: Array = [HandRank.THREE_OF_A_KIND, rank_keys[0]]
		r.append_array(rank_keys.slice(1))
		return r

	if counts.size() >= 2 and counts[0] == 2 and counts[1] == 2:
		return [HandRank.TWO_PAIR, rank_keys[0], rank_keys[1],
				rank_keys[2] if rank_keys.size() > 2 else 0]

	if counts[0] == 2:
		var r: Array = [HandRank.ONE_PAIR, rank_keys[0]]
		r.append_array(rank_keys.slice(1))
		return r

	var r: Array = [HandRank.HIGH_CARD]
	r.append_array(ranks)
	return r

## Best 5-card hand treating all cards of wild_rank as wildcards.
## Tries every C(candidates, n_wilds) substitution and returns the best result.
static func best_from_n_with_wilds(cards: Array, wild_rank: int) -> Array:
	var n_wilds := 0
	var naturals: Array = []
	for card in cards:
		if CardDB.rank_index(card) == wild_rank:
			n_wilds += 1
		else:
			naturals.append(card)

	if n_wilds == 0:
		return best_from_n(naturals)

	# Candidate replacements: every non-wild card not already held.
	var held: Dictionary = {}
	for c in naturals:
		held[c] = true
	var candidates: Array = []
	for r in CardDB.RANKS:
		if CardDB.RANKS.find(r) == wild_rank:
			continue
		for s in CardDB.SUITS:
			var c: String = r + s
			if not held.has(c):
				candidates.append(c)

	var best: Array = []
	_each_combination(candidates, n_wilds, func(replacements: Array) -> void:
		var hand: Array = naturals.duplicate()
		hand.append_array(replacements)
		var result := evaluate_five(hand)
		if best.is_empty() or compare(result, best) > 0:
			best.clear()
			best.append_array(result)
	)
	return best

## Returns 1 if a > b, -1 if a < b, 0 if equal.
static func compare(a: Array, b: Array) -> int:
	for i in range(mini(a.size(), b.size())):
		if a[i] > b[i]: return 1
		if a[i] < b[i]: return -1
	return 0

static func hand_name(hand_value: Array) -> String:
	if hand_value.is_empty():
		return "Unknown"
	var rank: int = hand_value[0]
	return HAND_NAMES[rank] if rank >= 0 and rank < HAND_NAMES.size() else "Unknown"

## Iterates all C(arr.size(), k) combinations, calling callback with each.
static func _each_combination(arr: Array, k: int, callback: Callable) -> void:
	var n := arr.size()
	if n < k:
		return
	var indices: Array[int] = []
	for i in range(k):
		indices.append(i)

	while true:
		var combo: Array = []
		for idx in indices:
			combo.append(arr[idx])
		callback.call(combo)

		var i := k - 1
		while i >= 0 and indices[i] == i + n - k:
			i -= 1
		if i < 0:
			break
		indices[i] += 1
		for j in range(i + 1, k):
			indices[j] = indices[j - 1] + 1
