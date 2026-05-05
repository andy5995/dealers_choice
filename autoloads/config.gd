extends Node
## Autoload name: Config
## Reads server.cfg at startup. Pass --config <path> (after -- on the command line)
## to load an alternate file instead.

const _DEFAULT_PATH := "res://server.cfg"

var turn_timeout_sec: float = 30.0
var draw_timeout_sec: float = 30.0
## 1 = forward through player order, -1 = backward.
var dealer_rotation: int = 1

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path()) != OK:
		return
	turn_timeout_sec = maxf(cfg.get_value("game", "turn_timeout_sec", turn_timeout_sec), 5.0)
	draw_timeout_sec = maxf(cfg.get_value("game", "draw_timeout_sec", draw_timeout_sec), 5.0)
	var dir: int = cfg.get_value("game", "dealer_rotation", dealer_rotation)
	dealer_rotation = 1 if dir >= 0 else -1

func _config_path() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--config":
			return args[i + 1]
	return _DEFAULT_PATH
