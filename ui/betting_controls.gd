class_name BettingControls
extends Control
## Betting action panel — shown only when it's the local player's turn.
## Action buttons (Fold / Call / Bet / Raise) are on one row.
## Fixed amount buttons (100 / 250 / 500) are on the row below, white+brown DC style.
## Clicking Bet or Raise immediately uses the currently selected amount.

signal action_chosen(action: String, amount: int)

const AMOUNTS := [100, 250, 500]

var _bet_to_call: int = 0
var _min_valid:   int = 0   # minimum total chips for a bet/raise
var _my_chips:    int = 1000
var _selected_idx: int = 0  # which amount button is active
var _has_bet_action: bool = false
var _has_raise_action: bool = false

@onready var _fold_btn:       Button        = $VBox/ActionRow/FoldBtn
@onready var _call_check_btn: Button        = $VBox/ActionRow/CallCheckBtn
@onready var _bet_btn:        Button        = $VBox/ActionRow/BetBtn
@onready var _raise_btn:      Button        = $VBox/ActionRow/RaiseBtn
@onready var _amount_row:     HBoxContainer = $VBox/AmountRow
@onready var _amt_btns: Array[Button] = []

func _ready() -> void:
	for child in _amount_row.get_children():
		if child is Button:
			_amt_btns.append(child as Button)

func setup(valid_actions: Array, bet_to_call: int, min_bet: int, my_chips: int) -> void:
	_bet_to_call = bet_to_call
	_my_chips    = my_chips
	visible      = true

	_has_bet_action   = valid_actions.has("bet")
	_has_raise_action = valid_actions.has("raise")

	_fold_btn.visible       = valid_actions.has("fold")
	_call_check_btn.visible = valid_actions.has("check") or valid_actions.has("call")
	_bet_btn.visible        = _has_bet_action
	_raise_btn.visible      = _has_raise_action

	if valid_actions.has("check"):
		_call_check_btn.text = "Check"
	else:
		_call_check_btn.text = "Call %d" % mini(bet_to_call, my_chips)

	# Minimum valid total for a bet/raise.
	# For a bet (no prior bet): minimum is min_bet.
	# For a raise: must be at least bet_to_call + min_bet (raise BY at least min_bet).
	_min_valid = bet_to_call + min_bet

	var show_amounts := _has_bet_action or _has_raise_action
	_amount_row.visible = show_amounts

	if show_amounts:
		_refresh_amounts()

func _refresh_amounts() -> void:
	for i in AMOUNTS.size():
		var amt: int    = AMOUNTS[i]
		var btn: Button = _amt_btns[i]
		btn.disabled = amt < _min_valid or amt > _my_chips
	# If the stored selection is now disabled, advance to the first valid one.
	if _selected_idx < _amt_btns.size() and _amt_btns[_selected_idx].disabled:
		_selected_idx = 0
		for i in AMOUNTS.size():
			if not _amt_btns[i].disabled:
				_selected_idx = i
				break
	_update_selection_visuals()

func _update_selection_visuals() -> void:
	for i in _amt_btns.size():
		var btn: Button = _amt_btns[i]
		btn.button_pressed = (i == _selected_idx and not btn.disabled)

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_fold_pressed() -> void:
	_emit("fold", 0)

func _on_call_check_pressed() -> void:
	if _bet_to_call == 0:
		_emit("check", 0)
	else:
		_emit("call", 0)

func _on_bet_pressed() -> void:
	_emit("bet", _selected_amount())

func _on_raise_pressed() -> void:
	_emit("raise", _selected_amount())

func _on_amount_pressed(idx: int) -> void:
	if not _amt_btns[idx].disabled:
		_selected_idx = idx
		_update_selection_visuals()

func _selected_amount() -> int:
	if _selected_idx < AMOUNTS.size():
		return clampi(AMOUNTS[_selected_idx], _min_valid, _my_chips)
	return _min_valid

func _emit(action: String, amount: int) -> void:
	visible = false
	action_chosen.emit(action, amount)
