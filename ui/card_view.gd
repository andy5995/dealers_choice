class_name CardView
extends Control
## Displays one playing card using 2D draw calls — no texture assets required.

signal selection_changed(card_name: String, selected: bool)

var card_name: String   = ""
var is_face_up: bool    = true
var is_selectable: bool = false
var is_selected: bool   = false

const _RED         = Color(0.82, 0.10, 0.10)
const _BLACK       = Color(0.08, 0.08, 0.08)
const _CARD_BG     = Color(0.98, 0.97, 0.95)
const _CARD_BORDER = Color(0.30, 0.30, 0.30)
const _BACK_BG     = Color(0.14, 0.28, 0.65)
const _BACK_STRIPE = Color(0.10, 0.20, 0.50)
const _BACK_BORDER = Color(0.08, 0.18, 0.48)
const _SELECT_TINT = Color(1.0, 0.9, 0.0, 0.40)

const _SUIT_TEX = {
	"S": preload("res://assets/suits/spade.svg"),
	"H": preload("res://assets/suits/heart.svg"),
	"D": preload("res://assets/suits/diamond.svg"),
	"C": preload("res://assets/suits/club.svg"),
}

func _ready() -> void:
	custom_minimum_size = Vector2(48, 42)

func show_card(name: String, face_up: bool = true) -> void:
	card_name = name
	is_face_up = face_up
	queue_redraw()

func set_selectable(enabled: bool) -> void:
	is_selectable = enabled
	mouse_filter = MOUSE_FILTER_STOP if enabled else MOUSE_FILTER_IGNORE
	if not enabled:
		_set_selected(false)

func _set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not is_selectable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected(not is_selected)
		selection_changed.emit(card_name, is_selected)

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if is_face_up and card_name != CardDB.BACK_CARD:
		_draw_face(r)
	else:
		_draw_back(r)
	if is_selected:
		draw_rect(r, _SELECT_TINT)

func _draw_face(r: Rect2) -> void:
	draw_rect(r, _CARD_BG)
	draw_rect(r, _CARD_BORDER, false, 1.5)
	if card_name.length() < 2:
		return
	var suit_ch: String  = CardDB.suit_char(card_name)
	var rank_str: String = CardDB.rank_display(card_name)
	var col: Color       = _RED if suit_ch in ["D", "H"] else _BLACK
	var font: Font       = ThemeDB.fallback_font

	# Rank on the left, vertically centred — proportional to card height
	var rank_sz := int(r.size.y * 0.52)
	var ry: float = (r.size.y + rank_sz * 0.72) * 0.5
	draw_string(font, Vector2(r.size.x * 0.08, ry), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_sz, col)

	# Suit texture on the right, vertically centred — proportional to card height
	var tex: Texture2D = _SUIT_TEX.get(suit_ch)
	if tex:
		var s    := r.size.y * 0.45
		var cx   := r.size.x - s - r.size.x * 0.06
		var cy   := (r.size.y - s) * 0.5
		draw_texture_rect(tex, Rect2(Vector2(cx, cy), Vector2(s, s)), false, col)

func _draw_back(r: Rect2) -> void:
	draw_rect(r, _BACK_BG)
	var step := r.size.x / 12.0
	var w    := r.size.x
	var h    := r.size.y
	var i    := -h
	while i < w + h:
		draw_line(Vector2(i, 0),     Vector2(i + h, h), _BACK_STRIPE, 1.0)
		draw_line(Vector2(i + h, 0), Vector2(i, h),     _BACK_STRIPE, 1.0)
		i += step
	draw_rect(r, _BACK_BORDER, false, 1.5)
