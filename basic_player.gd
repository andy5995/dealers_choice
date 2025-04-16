extends Node2D

var hand: Array[String] = []

@onready var card_sprites := [
	$Card1,
	$Card2,
	$Card3,
	$Card4,
	$Card5
]

func _ready():
	add_to_group("players")

@rpc("authority")
func receive_hand(cards: Array[String]) -> void:
	print("Received hand: ", cards)  # Debugging line
	hand = cards
	for i in range(hand.size()):  # Updated to use 'range' for valid iteration
		var path = "res://assets/cards/%s.png" % hand[i]
		card_sprites[i].texture = load(path)

		# Set the position of each card (Example: spread out in a row)
		var x_offset = 100 * i  # Space each card 100 units apart on the x-axis
		var y_offset = 0  # You can adjust the y offset for vertical stacking if needed
		card_sprites[i].position = Vector2(x_offset, y_offset)

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
