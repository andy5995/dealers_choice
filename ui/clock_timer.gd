extends Control
## Pie-style countdown clock matching DealersChoice render_circle_timer().
##
## fill_ratio: 1.0 = just started (no wedge), 0.0 = expired (full brown wedge).
## The brown wedge grows clockwise from 12 o'clock as time elapses.
## A 3D border ring is lit from the top-left and shaded toward the bottom-right.

const OUTER_R  = 50.0
const BORDER   = 10.0
const INNER_R  = OUTER_R - BORDER   # 40
const SEGMENTS = 64

const _GREEN = Color(0.0,       0.490,  0.0)
const _BROWN = Color(101/255.0, 67/255.0, 33/255.0)

var fill_ratio: float = 1.0 : set = _set_fill

func _set_fill(v: float) -> void:
	fill_ratio = clampf(v, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var center = size * 0.5

	# ── 3D border ring ────────────────────────────────────────────────────────
	# Split the ring into SEGMENTS trapezoids; shade each by the dot product of
	# its outward direction with (-1, -1), matching the C formula:
	#   t = (-dx - dy) / (outer_r * sqrt(2))  →  c = 70 + t * 185  (gray 70–255)
	for i in SEGMENTS:
		var a0  = i       * TAU / SEGMENTS
		var a1  = (i + 1) * TAU / SEGMENTS
		var mid = (a0 + a1) * 0.5
		var dx  = cos(mid)
		var dy  = sin(mid)
		var t   = clampf((-dx - dy) / 1.41421, -1.0, 1.0)
		t = (t + 1.0) * 0.5
		var c   = (70.0 + t * 185.0) / 255.0
		var col = Color(c, c, c)
		var o0  = center + Vector2(cos(a0), sin(a0)) * OUTER_R
		var o1  = center + Vector2(cos(a1), sin(a1)) * OUTER_R
		var i0  = center + Vector2(cos(a0), sin(a0)) * INNER_R
		var i1  = center + Vector2(cos(a1), sin(a1)) * INNER_R
		draw_colored_polygon(PackedVector2Array([o0, o1, i1, i0]), col)

	# ── inner circle (table green) ────────────────────────────────────────────
	draw_circle(center, INNER_R, _GREEN)

	# ── brown pie wedge (elapsed time, clockwise from 12 o'clock) ────────────
	var sweep = (1.0 - fill_ratio) * TAU
	if sweep > 0.001:
		var n = max(int(sweep / TAU * SEGMENTS), 2)
		var verts = PackedVector2Array()
		verts.append(center)
		for j in range(n + 1):
			var a = -PI * 0.5 + j * sweep / n   # -PI/2 = 12 o'clock in Godot coords
			verts.append(center + Vector2(cos(a), sin(a)) * INNER_R)
		draw_colored_polygon(verts, _BROWN)
