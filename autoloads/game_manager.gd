extends Node
## Autoload name: GameManager
## Holds game configuration and triggers scene transitions.

enum GameVariant { FIVE_CARD_DRAW, TEXAS_HOLDEM, SEVEN_CARD_STUD }

var current_variant: GameVariant = GameVariant.TEXAS_HOLDEM
var starting_chips: int = 1000
var ante_amount: int = 10
var min_bet: int = 20

func start_game() -> void:
	if not NetworkManager.is_server():
		return
	_broadcast_start.rpc(int(current_variant), starting_chips, ante_amount, min_bet)

@rpc("authority", "call_local", "reliable")
func _broadcast_start(variant: int, chips: int, ante: int, bet: int) -> void:
	current_variant = variant as GameVariant
	starting_chips = chips
	ante_amount = ante
	min_bet = bet
	get_tree().change_scene_to_file("res://scenes/game_table.tscn")
