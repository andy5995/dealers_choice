extends Node
## Autoload name: GameManager
## Holds game configuration and triggers scene transitions.

enum GameVariant { FIVE_CARD_DRAW, TEXAS_HOLDEM, SEVEN_CARD_STUD, CALIFORNIA_LOWBALL }

var current_variant: GameVariant = GameVariant.TEXAS_HOLDEM
var deuces_wild: bool = false
var starting_chips: int = 1000
var ante_amount: int = 10
var min_bet: int = 20

var dealer_peer_id: int = 0
signal dealer_changed(new_dealer_id: int)


## Advance the dealer to the next player (server only). Broadcasts to all peers.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var toggle: bool = event.keycode == KEY_F11 \
			or (event.keycode == KEY_ENTER and event.alt_pressed)
		if toggle:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func advance_dealer() -> void:
	if not NetworkManager.is_server():
		return
	var peers: Array = NetworkManager.player_names.keys()
	peers.sort()
	if peers.is_empty():
		return
	if dealer_peer_id == 0 or not peers.has(dealer_peer_id):
		dealer_peer_id = peers[0]
	else:
		var idx: int = peers.find(dealer_peer_id)
		dealer_peer_id = peers[(idx + 1) % peers.size()]
	_sync_dealer.rpc(dealer_peer_id)

## Re-broadcast the current dealer to all peers (useful after scene changes).
func broadcast_dealer() -> void:
	if NetworkManager.is_server() and dealer_peer_id != 0:
		_sync_dealer.rpc(dealer_peer_id)

@rpc("authority", "call_local", "reliable")
func _sync_dealer(peer_id: int) -> void:
	dealer_peer_id = peer_id
	dealer_changed.emit(dealer_peer_id)

func start_game() -> void:
	if not NetworkManager.is_server():
		return
	_broadcast_start.rpc(int(current_variant), starting_chips, ante_amount, min_bet, deuces_wild)

@rpc("authority", "call_local", "reliable")
func _broadcast_start(variant: int, chips: int, ante: int, bet: int, dw: bool) -> void:
	current_variant = variant as GameVariant
	starting_chips = chips
	ante_amount = ante
	min_bet = bet
	deuces_wild = dw
	get_tree().change_scene_to_file("res://scenes/game_table.tscn")
