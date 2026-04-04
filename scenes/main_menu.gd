extends Control

@onready var _name_input:   LineEdit    = $Center/VBox/NameRow/NameInput
@onready var _ip_input:     LineEdit    = $Center/VBox/JoinRow/IPInput
@onready var _status_label: Label       = $Center/VBox/StatusLabel
@onready var _variant_opt:  OptionButton = $Center/VBox/VariantRow/VariantOption
@onready var _ante_spin:    SpinBox     = $Center/VBox/AnteRow/AnteSpin
@onready var _chips_spin:   SpinBox     = $Center/VBox/ChipsRow/ChipsSpin

func _ready() -> void:
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_variant_opt.clear()
	_variant_opt.add_item("Texas Hold'em",  GameManager.GameVariant.TEXAS_HOLDEM)
	_variant_opt.add_item("5-Card Draw",    GameManager.GameVariant.FIVE_CARD_DRAW)
	_variant_opt.add_item("7-Card Stud",    GameManager.GameVariant.SEVEN_CARD_STUD)

func _on_host_pressed() -> void:
	var name := _name_input.text.strip_edges()
	if name.is_empty():
		name = "Host"
	GameManager.current_variant = _variant_opt.get_selected_id() as GameManager.GameVariant
	GameManager.starting_chips  = int(_chips_spin.value)
	GameManager.ante_amount     = int(_ante_spin.value)
	GameManager.min_bet         = int(_ante_spin.value) * 2

	var err := NetworkManager.host(name)
	if err != OK:
		_status_label.text = "Failed to host: %s" % error_string(err)
		return
	_status_label.text = "Hosting on port %d …" % NetworkManager.PORT
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_join_pressed() -> void:
	var name := _name_input.text.strip_edges()
	if name.is_empty():
		name = "Player"
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	# Strip any protocol prefix or port the user may have pasted in
	for prefix in ["https://", "http://", "wss://", "ws://"]:
		if ip.begins_with(prefix):
			ip = ip.substr(prefix.length())
			break
	# Strip trailing :port
	var colon := ip.rfind(":")
	if colon != -1 and ip.substr(colon + 1).is_valid_int():
		ip = ip.substr(0, colon)
	# Strip trailing slashes
	ip = ip.rstrip("/")

	var err := NetworkManager.join(ip, name)
	if err != OK:
		_status_label.text = "Failed to connect: %s" % error_string(err)
		return
	_status_label.text = "Connecting to %s …" % ip

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed. Check the IP and try again."

func _on_server_disconnected() -> void:
	_status_label.text = "Disconnected from server."
