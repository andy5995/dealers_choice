extends Node
## Autoload name: Preloader  (must be FIRST autoload in project.godot)
##
## Forces all game scripts to compile at startup so their class_names are
## registered before any scene needs them.  Without this, GDScript compiles
## scripts on demand when a scene first loads, and types like CardView /
## PlayerSeat / BaseGame aren't in the global registry yet.
##
## Preloads must be listed in dependency order (leaves first).

const _SCRIPTS = [
	preload("res://core/player_state.gd"),
	preload("res://core/deck.gd"),
	preload("res://core/hand_evaluator.gd"),
	preload("res://games/base_game.gd"),
	preload("res://games/five_card_draw.gd"),
	preload("res://games/texas_holdem.gd"),
	preload("res://games/seven_card_stud.gd"),
	preload("res://ui/card_view.gd"),
	preload("res://ui/player_seat.gd"),
	preload("res://ui/betting_controls.gd"),
]
