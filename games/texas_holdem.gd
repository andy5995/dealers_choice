class_name TexasHoldem
extends "res://games/base_game.gd"
## Texas Hold'em: ante → 2 hole cards → preflop bet → flop → bet → turn → bet → river → bet → showdown.
## Uses antes only (no blinds). First player left of dealer acts first every round.

var _community: Array[String] = []
var _street: int = 0  # 0=preflop, 1=flop, 2=turn, 3=river

func _start_hand_impl() -> void:
	_community.clear()
	_street = 0
	for p in _players:
		p.hand = _deck.draw_n(2)
	_phase = Phase.BETTING
	_broadcast_state()
	_start_betting_round(_left_of_dealer())

func _advance_phase() -> void:
	_street += 1
	match _street:
		1:
			_community.append_array(_deck.draw_n(3))  # Flop
		2:
			_community.append(_deck.draw())            # Turn
		3:
			_community.append(_deck.draw())            # River
		4:
			# All five community cards have been dealt — showdown
			# Build full 7-card hand for each player
			for p in _players:
				if p.status != PS_FOLDED:
					p.hand = p.hand + _community
			_do_showdown()
			return

	_phase = Phase.BETTING
	_broadcast_state()
	_start_betting_round(_left_of_dealer())

func _get_community_cards() -> Array:
	return _community
