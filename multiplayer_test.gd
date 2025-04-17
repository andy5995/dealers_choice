extends Node2D

var peer = ENetMultiplayerPeer.new()
@export var player_scene: PackedScene

var card_names = [
	"2H", "3H", "4H", "5H", "6H", "7H", "8H", "9H", "TH", "JH", "QH", "KH", "AH",
	"2S", "3S", "4S", "5S", "6S", "7S", "8S", "9S", "TS", "JS", "QS", "KS", "AS",
	"2D", "3D", "4D", "5D", "6D", "7D", "8D", "9D", "TD", "JD", "QD", "KD", "AD",
	"2C", "3C", "4C", "5C", "6C", "7C", "8C", "9C", "TC", "JC", "QC", "KC", "AC",
	"1B", "2B"
]

func _on_host_pressed() -> void:
	peer.create_server(61357)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_add_player)
	
	# Add host player
	_add_player(1)  # Host is always player 1
	
func _add_player(id: int) -> void:
	if has_node(str(id)):
		return  # Already added

	var player = player_scene.instantiate()
	player.name = str(id)
	call_deferred("add_child", player)

	if multiplayer.get_peers().size() == 2:
		await get_tree().create_timer(0.5).timeout
		deal_cards()

func _on_join_pressed() -> void:
	peer.create_client("localhost", 61357)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_client_connected)

func _on_client_connected() -> void:
	print("Client connected successfully!")

	var player_id = multiplayer.get_unique_id()
	await get_tree().create_timer(0.1).timeout  # Slight delay for node to be added

	var player = get_node_or_null(str(player_id))
	if player:
		var random_card = card_names[randi() % card_names.size()]
		var tex_path = "res://assets/cards/%s.png" % random_card
		var card_texture = load(tex_path)

		# Only if sprite_node exists on the player
		if player.has_node("Sprite"):
			player.get_node("Sprite").texture = card_texture
	else:
		print("Player node not found after connect")

func deal_cards():
	print("Dealing cards...")
		
	var deck = card_names.duplicate()
	deck.shuffle()

	var host_hand: Array[String] = []
	var client_hand: Array[String] = []

	for i in range(10):
		var card = deck.pop_front()
		if i % 2 == 0:
			host_hand.append(card)
		else:
			client_hand.append(card)

	# Ensure the host and client receive their hands
	var host_player = get_node("1")  # Assuming node name is "1" for the host
	var client_player = get_node("2")  # Assuming node name is "2" for the client

	host_player.rpc("receive_hand", host_hand)
	client_player.rpc("receive_hand", client_hand)
