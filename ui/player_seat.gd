class_name PlayerSeat
extends Control
## Displays one player's seat: name, chips, bet, status, and cards.
## Uses untyped Array for card views to avoid class_name registry dependency.

const _CardView = preload("res://ui/card_view.tscn")

var peer_id: int = 0
var _card_views: Array = []   # holds CardView nodes
var _coin_icon: TextureRect = null

@onready var _name_label:   Label         = $VBox/NameLabel
@onready var _chips_label:  Label         = $VBox/ChipsLabel
@onready var _bet_label:    Label         = $VBox/BetLabel
@onready var _status_label: Label         = $VBox/StatusLabel
@onready var _cards_box:    HBoxContainer = $VBox/CardsBox
@onready var _dealer_chip:  Label         = $DealerChip

func _ready() -> void:
	custom_minimum_size = Vector2(240, 225)

## Set the coin icon displayed next to the chip count (called once by GameTable).
func set_coin_icon(tex: Texture2D, icon_size: int = 48) -> void:
	if _coin_icon == null:
		_coin_icon = TextureRect.new()
		_coin_icon.expand_mode           = TextureRect.EXPAND_IGNORE_SIZE
		_coin_icon.custom_minimum_size   = Vector2(icon_size, icon_size)
		_coin_icon.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_coin_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_coin_icon.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		var vbox = _chips_label.get_parent()
		vbox.add_child(_coin_icon)
		vbox.move_child(_coin_icon, _chips_label.get_index())
	_coin_icon.texture = tex

## Update publicly-visible player info (sent to all).
func update_public(data: Dictionary) -> void:
	_name_label.text     = data.get("display_name", "?")
	_chips_label.text    = "$ %d" % data.get("chips", 0)
	_bet_label.text      = "Bet: %d" % data.get("round_bet", 0)
	_dealer_chip.visible = data.get("is_dealer", false)

	var status: int = data.get("status", 0)
	match status:
		1: _status_label.text = "FOLDED"   # PlayerState.Status.FOLDED
		2: _status_label.text = "ALL IN"   # PlayerState.Status.ALL_IN
		_: _status_label.text = ""

	var face_up: Array  = data.get("face_up_cards", [])
	var card_count: int = data.get("card_count", 0)
	if not face_up.is_empty():
		_show_stud_public(face_up, card_count)
	elif card_count > 0:
		_show_card_backs(card_count)

## Update private info for the local player (hole cards etc.).
func update_private(data: Dictionary) -> void:
	var hand: Array      = data.get("hand", [])
	var face_down: Array = data.get("face_down_cards", [])

	if not face_down.is_empty():
		_show_stud_private(hand, face_down)
	elif not hand.is_empty():
		_set_card_count(hand.size())
		for i in hand.size():
			_card_views[i].show_card(hand[i], true)

## Enable/disable click-to-select on cards (5-Card Draw phase).
func enable_card_selection(enabled: bool) -> void:
	for cv in _card_views:
		cv.set_selectable(enabled)

## Returns indices of selected (to-discard) cards.
func get_selected_indices() -> Array[int]:
	var result: Array[int] = []
	for i in range(_card_views.size()):
		if _card_views[i].is_selected:
			result.append(i)
	return result

# ── Internal display helpers ──────────────────────────────────────────────────

func _show_card_backs(count: int) -> void:
	_set_card_count(count)
	for cv in _card_views:
		cv.show_card(CardDB.BACK_CARD, false)

func _show_stud_public(face_up: Array, total_count: int) -> void:
	var down_count := total_count - face_up.size()
	_set_card_count(total_count)
	var idx := 0
	for _i in down_count:
		_card_views[idx].show_card(CardDB.BACK_CARD, false)
		idx += 1
	for card in face_up:
		_card_views[idx].show_card(card, true)
		idx += 1

func _show_stud_private(hand: Array, face_down: Array) -> void:
	_set_card_count(hand.size())
	for i in face_down.size():
		if i < _card_views.size():
			_card_views[i].show_card(face_down[i], true)   # local player sees own hole cards
	for i in range(face_down.size(), hand.size()):
		_card_views[i].show_card(hand[i], true)

func _set_card_count(count: int) -> void:
	while _card_views.size() < count:
		var cv = _CardView.instantiate()
		_cards_box.add_child(cv)
		_card_views.append(cv)
	while _card_views.size() > count:
		(_card_views.pop_back() as Node).queue_free()
