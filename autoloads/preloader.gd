extends Node
## Autoload name: Preloader  (must be FIRST autoload in project.godot)
##
## Loads all game scripts sequentially at runtime so their class_names are
## registered in the global ScriptServer before any scene needs them.
##
## Uses load() (runtime) rather than preload() (compile-time) so that each
## script's class_name is registered before the next script is loaded —
## a compile-time const array evaluates in one pass and can't see class_names
## registered by earlier entries in the same pass.

func _ready() -> void:
	var scripts := [
		"res://core/player_state.gd",
		"res://core/deck.gd",
		"res://core/hand_evaluator.gd",
		"res://games/base_game.gd",
		"res://games/five_card_draw.gd",
		"res://games/texas_holdem.gd",
		"res://games/seven_card_stud.gd",
		"res://ui/card_view.gd",
		"res://ui/player_seat.gd",
		"res://ui/betting_controls.gd",
	]
	for path in scripts:
		var s = load(path)
		if s == null:
			push_error("Preloader: failed to load %s" % path)
