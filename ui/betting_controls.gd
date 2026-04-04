class_name BettingControls
extends Control
## Betting action panel — shown only when it's the local player's turn.

signal action_chosen(action: String, amount: int)

var _current_bet: int = 0
var _min_bet: int = 20
var _my_chips: int = 1000

@onready var _fold_btn:        Button  = $VBox/Row1/FoldBtn
@onready var _call_check_btn:  Button  = $VBox/Row1/CallCheckBtn
@onready var _raise_btn:       Button  = $VBox/Row1/RaiseBtn
@onready var _raise_row:       HBoxContainer = $VBox/RaiseRow
@onready var _raise_slider:    HSlider = $VBox/RaiseRow/RaiseSlider
@onready var _raise_label:     Label   = $VBox/RaiseRow/RaiseLabel

func setup(valid_actions: Array, bet_to_call: int, min_bet: int, my_chips: int) -> void:
	_current_bet = bet_to_call
	_min_bet     = min_bet
	_my_chips    = my_chips
	visible      = true

	_fold_btn.visible       = valid_actions.has("fold")
	_call_check_btn.visible = valid_actions.has("check") or valid_actions.has("call")
	_raise_btn.visible      = valid_actions.has("bet") or valid_actions.has("raise")

	if valid_actions.has("check"):
		_call_check_btn.text = "Check"
	else:
		var to_call := mini(bet_to_call, my_chips)
		_call_check_btn.text = "Call %d" % to_call

	_raise_row.visible = false
	if _raise_btn.visible:
		var min_total := bet_to_call + min_bet
		var max_total := my_chips + _round_bet_this_seat()
		_raise_slider.min_value = mini(min_total, max_total)
		_raise_slider.max_value = max_total
		_raise_slider.value     = _raise_slider.min_value
		_update_raise_label()

func _round_bet_this_seat() -> int:
	# We don't have this info here; game_table passes my_chips = chips remaining
	return 0

func _update_raise_label() -> void:
	_raise_label.text = "Raise to: %d" % int(_raise_slider.value)

func _on_fold_pressed()       -> void: _emit("fold",  0)
func _on_call_check_pressed() -> void:
	if _current_bet == 0:
		_emit("check", 0)
	else:
		_emit("call",  0)

func _on_raise_btn_pressed() -> void:
	_raise_row.visible = not _raise_row.visible

func _on_raise_slider_changed(value: float) -> void:
	_update_raise_label()

func _on_confirm_raise_pressed() -> void:
	_emit("raise", int(_raise_slider.value))

func _emit(action: String, amount: int) -> void:
	visible = false
	_raise_row.visible = false
	action_chosen.emit(action, amount)
