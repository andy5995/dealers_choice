extends Node
## Autoload name: AudioManager
## Plays poker game sounds. Mirrors the event-driven sound model from DealersChoice:
##   server_join  — a new player entered the lobby
##   my_turn      — it is the local player's turn to act
##   game_over    — hand (or game) is over
##   coin_hit_*   — a bet, call, or raise was made (random from 7 variants)

var _server_join: AudioStreamPlayer
var _my_turn:     AudioStreamPlayer
var _game_over:   AudioStreamPlayer
var _coins:       Array = []

func _ready() -> void:
	_server_join = _make_player("res://assets/sounds/server_join.wav")
	_my_turn     = _make_player("res://assets/sounds/my_turn.wav")
	_game_over   = _make_player("res://assets/sounds/game_over.wav")
	for i in range(1, 8):
		_coins.append(_make_player("res://assets/sounds/coin/coin_hit_%03d.wav" % i))

func play_server_join() -> void:
	_server_join.play()

func play_my_turn() -> void:
	_my_turn.play()

func play_game_over() -> void:
	_game_over.play()

func play_coin_hit() -> void:
	_coins[randi() % _coins.size()].play()

func _make_player(path: String) -> AudioStreamPlayer:
	var asp = AudioStreamPlayer.new()
	asp.stream = load(path)
	add_child(asp)
	return asp
