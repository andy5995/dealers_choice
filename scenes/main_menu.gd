extends Control

@onready var _name_input:   LineEdit    = $Form/NameRow/NameInput
@onready var _ip_input:     LineEdit    = $Form/ServerRow/IPInput
@onready var _server_row:   HBoxContainer = $Form/ServerRow
@onready var _status_label: Label       = $Form/StatusLabel

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_start_headless_server()
		return

	if OS.get_name() == "Web":
		_server_row.visible = false

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _start_headless_server() -> void:
	var err := NetworkManager.host_server()
	if err != OK:
		push_error("Headless server failed: %s" % error_string(err))
		get_tree().quit()
		return
	print("Headless server started on port %d" % NetworkManager.SERVER_PORT)
	get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")

func _on_join_pressed() -> void:
	var name := _name_input.text.strip_edges()
	if name.is_empty():
		name = "Player"
	var ip: String
	if OS.get_name() == "Web":
		ip = JavaScriptBridge.eval("window.location.hostname")
	else:
		ip = _ip_input.text.strip_edges()
		if ip.is_empty():
			ip = "127.0.0.1"
		for prefix in ["https://", "http://", "wss://", "ws://"]:
			if ip.begins_with(prefix):
				ip = ip.substr(prefix.length())
				break
		var colon := ip.rfind(":")
		if colon != -1 and ip.substr(colon + 1).is_valid_int():
			ip = ip.substr(0, colon)
		ip = ip.rstrip("/")

	var err := NetworkManager.join(ip, name)
	if err != OK:
		_status_label.text = "Failed to connect: %s" % error_string(err)
		return
	_status_label.text = "Connecting to %s…" % ip

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed. Check the address and try again."

func _on_server_disconnected() -> void:
	_status_label.text = "Disconnected from server."
