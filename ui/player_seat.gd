class_name PlayerSeat
extends Control
## Displays one player's seat: name, chips, bet, status, and cards.

const CARD_SCENE := preload("res://ui/card_view.tscn")

var peer_id: int = 0
var _card_views: Array[CardView] = []

@onready var _name_label:   Label     = $VBox/NameLabel
@onready var _chips_label:  Label     = $VBox/ChipsLabel
@onready var _bet_label:    Label     = $VBox/BetLabel
@onready var _status_label: Label     = $VBox/StatusLabel
@onready var _cards_box:    HBoxContainer = $VBox/CardsBox
@onready var _dealer_chip:  Label     = $DealerChip

func _ready() -> void:
	custom_minimum_size = Vector2(160, 150)

## Update publicly-visible player info (sent to all).
func update_public(data: Dictionary) -> void:
	_name_label.text  = data.get("display_name", "?")
	_chips_label.text = "$ %d" % data.get("chips", 0)
	_bet_label.text   = "Bet: %d" % data.get("round_bet", 0)
	_dealer_chip.visible = data.get("is_dealer", false)

	var status: int = data.get("status", 0)
	match status:
		PlayerState.Status.FOLDED:  _status_label.text = "FOLDED"
		PlayerState.Status.ALL_IN:  _status_label.text = "ALL IN"
		_:                          _status_label.text = ""

	# Show face-up cards (Stud) — safe to display to everyone
	var face_up: Array = data.get("face_up_cards", [])
	var card_count: int = data.get("card_count", 0)
	if not face_up.is_empty():
		_show_stud_public(face_up, card_count)
	elif face_up.is_empty() and card_count > 0:
		_show_card_backs(card_count)

## Update private info for the local player (hole cards etc.).
func update_private(data: Dictionary) -> void:
	var hand: Array = data.get("hand", [])
	var face_down: Array = data.get("face_down_cards", [])

	if not face_down.is_empty():
		# Stud: render as [down, down, up..., down]
		_show_stud_private(hand, face_down)
	elif not hand.is_empty():
		# Draw or Hold'em: show all cards face up
		_set_card_count(hand.size())
		for i in hand.size():
			_card_views[i].show_card(hand[i], true)

## Enable/disable click-to-select on cards (Draw phase).
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
	# Other players: show backs for hole cards, face-up for up-cards
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
	# Stud layout: face_down first, then the rest face-up
	for i in face_down.size():
		if i < _card_views.size():
			_card_views[i].show_card(face_down[i], false)
	for i in range(face_down.size(), hand.size()):
		_card_views[i].show_card(hand[i], true)

func _set_card_count(count: int) -> void:
	# Add or remove CardView children to match count
	while _card_views.size() < count:
		var cv: CardView = CARD_SCENE.instantiate()
		_cards_box.add_child(cv)
		_card_views.append(cv)
	while _card_views.size() > count:
		var cv := _card_views.pop_back()
		cv.queue_free()
