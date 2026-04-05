extends Node
## Autoload name: NetworkManager
## Owns the WebSocket peer and all connection signals.
## IMPORTANT: peer.poll() is called every frame — without this, WebSocket stalls.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connected_to_server()
signal server_disconnected()
signal lobby_updated()  ## fired on ALL peers whenever the player list changes

const PORT         := 22777  ## public-facing port (nginx)
const SERVER_PORT  := 22778  ## internal Godot WebSocket server port (not forwarded)
const MAX_PLAYERS  := 5

var peer: WebSocketMultiplayerPeer = null
## Maps peer_id -> display name, maintained on all peers via _sync_player_names RPC.
var player_names: Dictionary = {}

func _process(_delta: float) -> void:
	if peer != null:
		peer.poll()

func host(my_name: String) -> Error:
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(SERVER_PORT)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_names[1] = my_name
	return OK

func join(address: String, my_name: String) -> Error:
	disconnect_all()  # clean up any previous attempt
	peer = WebSocketMultiplayerPeer.new()
	var url: String
	if address == "127.0.0.1" or address == "localhost":
		url = "ws://%s:%d" % [address, SERVER_PORT]
	else:
		url = "wss://%s:%d/ws" % [address, PORT]
	var err := peer.create_client(url)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	player_names[-1] = my_name  # stored temporarily until we get our ID
	return OK

func get_my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0

func is_server() -> bool:
	return multiplayer.is_server()

func disconnect_all() -> void:
	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null
	player_names.clear()

func _on_connected_to_server() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_name: String = player_names.get(-1, "Player")
	player_names.erase(-1)
	player_names[my_id] = my_name
	connected_to_server.emit()
	_register_with_server.rpc_id(1, my_name)

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_names.erase(id)
	player_disconnected.emit(id)

func _on_connection_failed() -> void:
	peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	peer = null
	player_names.clear()
	server_disconnected.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register_with_server(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if player_names.size() >= MAX_PLAYERS:
		return
	player_names[sender_id] = player_name
	_sync_player_names.rpc(player_names)
	player_connected.emit(sender_id)

@rpc("authority", "call_local", "reliable")
func _sync_player_names(names: Dictionary) -> void:
	player_names = names
	lobby_updated.emit()
