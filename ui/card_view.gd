class_name CardView
extends Control
## Displays one playing card. Can be toggled selected (for draw phase discards).

signal selection_changed(card_name: String, selected: bool)

var card_name: String = ""
var is_face_up: bool = true
var is_selectable: bool = false
var is_selected: bool = false

@onready var _texture_rect: TextureRect = $CardTexture
@onready var _overlay: ColorRect     = $SelectOverlay

func show_card(name: String, face_up: bool = true) -> void:
	card_name = name
	is_face_up = face_up
	if face_up:
		_texture_rect.texture = CardDB.load_texture(name)
	else:
		_texture_rect.texture = CardDB.load_texture(CardDB.BACK_CARD)

func set_selectable(enabled: bool) -> void:
	is_selectable = enabled
	mouse_filter = MOUSE_FILTER_STOP if enabled else MOUSE_FILTER_IGNORE
	if not enabled:
		_set_selected(false)

func _set_selected(value: bool) -> void:
	is_selected = value
	_overlay.visible = value

func _gui_input(event: InputEvent) -> void:
	if not is_selectable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected(not is_selected)
		selection_changed.emit(card_name, is_selected)
