extends Control

@onready var _player_list: ItemList = $Center/VBox/PlayerList
@onready var _start_btn:   Button   = $Center/VBox/StartBtn
@onready var _status_label: Label   = $Center/VBox/StatusLabel
@onready var _game_label:  Label    = $Center/VBox/GameLabel

func _ready() -> void:
	NetworkManager.player_connected.connect(_refresh_player_list)
	NetworkManager.player_disconnected.connect(_refresh_player_list)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_start_btn.visible = NetworkManager.is_server()
	_refresh_player_list(0)
	_update_game_label()

func _refresh_player_list(_id: int = 0) -> void:
	_player_list.clear()
	for pid in NetworkManager.player_names:
		var name: String = NetworkManager.player_names[pid]
		var suffix := " (Host)" if pid == 1 else ""
		_player_list.add_item(name + suffix)
	_status_label.text = "%d / %d players connected" % [
		NetworkManager.player_names.size(), NetworkManager.MAX_PLAYERS
	]

func _update_game_label() -> void:
	const VARIANT_NAMES := ["Texas Hold'em", "5-Card Draw", "7-Card Stud"]
	var v := GameManager.current_variant as int
	_game_label.text = "Game: %s  |  Ante: %d  |  Chips: %d" % [
		VARIANT_NAMES[v], GameManager.ante_amount, GameManager.starting_chips
	]

func _on_start_pressed() -> void:
	if NetworkManager.player_names.size() < 2:
		_status_label.text = "Need at least 2 players to start."
		return
	GameManager.start_game()

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_back_pressed() -> void:
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
