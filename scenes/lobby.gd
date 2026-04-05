extends Control

@onready var _player_list:   ItemList      = $Center/VBox/PlayerList
@onready var _status_label:  Label         = $Center/VBox/StatusLabel
@onready var _dealer_panel:  VBoxContainer = $Center/VBox/DealerPanel
@onready var _waiting_label: Label         = $Center/VBox/WaitingLabel

func _ready() -> void:
	NetworkManager.lobby_updated.connect(_refresh)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	GameManager.dealer_changed.connect(_on_dealer_changed)

	# Re-broadcast dealer so clients that just loaded the scene are in sync.
	if NetworkManager.is_server():
		GameManager.broadcast_dealer()
	_refresh()

func _refresh(_ignored: int = 0) -> void:
	_player_list.clear()
	var my_id := NetworkManager.get_my_id()
	for pid in NetworkManager.player_names:
		var pname: String = NetworkManager.player_names[pid]
		var star := " ★" if pid == GameManager.dealer_peer_id else ""
		_player_list.add_item(pname + star)
	_status_label.text = "%d / %d players" % [
		NetworkManager.player_names.size(), NetworkManager.MAX_PLAYERS
	]

	var player_count := NetworkManager.player_names.size()
	var i_am_dealer := (GameManager.dealer_peer_id != 0 and my_id == GameManager.dealer_peer_id)
	_dealer_panel.visible = i_am_dealer
	# Disable variant buttons until at least 2 players are present.
	var can_start := player_count >= 2
	for btn in $Center/VBox/DealerPanel/BtnRow.get_children():
		(btn as Button).disabled = not can_start
	_waiting_label.visible = not i_am_dealer
	if not i_am_dealer:
		if GameManager.dealer_peer_id == 0:
			_waiting_label.text = "Waiting for players…"
		else:
			var dname: String = NetworkManager.player_names.get(GameManager.dealer_peer_id, "Dealer")
			_waiting_label.text = "%s is choosing the game…" % dname

func _on_dealer_changed(_id: int) -> void:
	_refresh()

func _on_player_connected(id: int) -> void:
	# Only act on the registered-with-name emit (not the raw WebSocket connect).
	if NetworkManager.is_server() and NetworkManager.player_names.has(id):
		var my_id := NetworkManager.get_my_id()
		for pid in NetworkManager.player_names:
			if pid == id:
				continue  # new joiner is still in main menu — skip
			if pid == my_id:
				AudioManager.play_server_join()  # non-headless host plays locally
			else:
				_play_join_sound.rpc_id(pid)
		# First player to join triggers dealer selection.
		if GameManager.dealer_peer_id == 0:
			GameManager.advance_dealer()
	_refresh()

@rpc("authority", "call_remote", "reliable")
func _play_join_sound() -> void:
	AudioManager.play_server_join()

func _on_player_disconnected(id: int) -> void:
	# If the dealer left, assign a new one.
	if NetworkManager.is_server() and id == GameManager.dealer_peer_id:
		GameManager.dealer_peer_id = 0
		if not NetworkManager.player_names.is_empty():
			GameManager.advance_dealer()
	_refresh()

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_holdem_pressed() -> void:
	_submit_variant(GameManager.GameVariant.TEXAS_HOLDEM)

func _on_draw_pressed() -> void:
	_submit_variant(GameManager.GameVariant.FIVE_CARD_DRAW)

func _on_stud_pressed() -> void:
	_submit_variant(GameManager.GameVariant.SEVEN_CARD_STUD)

func _submit_variant(variant: int) -> void:
	if NetworkManager.is_server():
		_start_game_server_side(variant)
	else:
		submit_variant.rpc_id(1, variant)

@rpc("any_peer", "call_remote", "reliable")
func submit_variant(variant: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != GameManager.dealer_peer_id:
		return
	_start_game_server_side(variant)

func _start_game_server_side(variant: int) -> void:
	GameManager.current_variant = variant as GameManager.GameVariant
	GameManager.start_game()

func _on_back_pressed() -> void:
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
