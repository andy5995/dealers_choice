extends Node
## Autoload name: Config
## Reads server.cfg at startup. Pass --config <path> (after -- on the command line)
## to load an alternate file instead.

const _DEFAULT_PATH := "res://server.cfg"

var turn_timeout_sec: float = 30.0
var draw_timeout_sec: float = 30.0
## 1 = forward through player order, -1 = backward.
var dealer_rotation: int = 1
var starting_chips: int = 20000
var ante_amount: int = 50
var min_bet: int = 100
var end_of_game_timeout: float = 15.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path()) != OK:
		return
	turn_timeout_sec = maxf(cfg.get_value("game", "turn_timeout_sec", turn_timeout_sec), 5.0)
	draw_timeout_sec = maxf(cfg.get_value("game", "draw_timeout_sec", draw_timeout_sec), 5.0)
	var dir: int = cfg.get_value("game", "dealer_rotation", dealer_rotation)
	dealer_rotation = 1 if dir >= 0 else -1
	starting_chips = maxi(cfg.get_value("game", "starting_chips", starting_chips), 1)
	ante_amount = maxi(cfg.get_value("game", "ante", ante_amount), 0)
	min_bet = maxi(cfg.get_value("game", "min_bet", min_bet), 1)
	end_of_game_timeout = maxf(cfg.get_value("game", "end_of_game_timeout", end_of_game_timeout), 0.0)

func _config_path() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--config":
			return args[i + 1]
	return _DEFAULT_PATH
