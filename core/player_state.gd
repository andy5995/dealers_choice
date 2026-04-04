class_name PlayerState
extends RefCounted
## Per-player game state. Server holds the full state; clients get public/private views.

enum Status { ACTIVE, FOLDED, ALL_IN, SITTING_OUT }

var peer_id: int = 0
var display_name: String = "Player"
var chips: int = 1000
var current_bet: int = 0         ## chips placed in the current betting round
var total_pot_contrib: int = 0   ## total chips in pot this hand (for side pot math)
var hand: Array[String] = []     ## private: all cards (hole cards + face-ups)
var face_up_cards: Array[String] = []    ## Stud: visible to all players
var face_down_cards: Array[String] = []  ## Stud: private (hole cards only)
var status: Status = Status.ACTIVE

func reset_for_hand() -> void:
	hand.clear()
	face_up_cards.clear()
	face_down_cards.clear()
	current_bet = 0
	total_pot_contrib = 0
	status = Status.ACTIVE

## Safe to broadcast to everyone.
func to_public_dict() -> Dictionary:
	return {
		"peer_id":       peer_id,
		"display_name":  display_name,
		"chips":         chips,
		"current_bet":   current_bet,
		"status":        int(status),
		"face_up_cards": face_up_cards,
		"card_count":    hand.size(),
	}

## Sent ONLY to this player (contains hole cards).
func to_private_dict() -> Dictionary:
	var d := to_public_dict()
	d["hand"]            = hand
	d["face_down_cards"] = face_down_cards
	return d
