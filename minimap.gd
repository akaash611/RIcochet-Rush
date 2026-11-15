extends Control
## Top-right minimap: a 2D, top-down copy of what's happening in 3D.
##   - structures (their real footprints, in their colours)
##   - you (arrow + view cone), the enemy (red, pulsing)
##   - the aim path: same dashes, same colours, same bounce markers and the
##     same GREEN DOT when the shot would land, taken straight from the 3D
##     trajectory preview so the two always match
##   - the live ball and its trail while it's in flight

@export var map_size: float = 230.0
@export var margin: float = 16.0
@export var world_half: float = 20.0          # the room is 40 x 40
@export var background := Color(0.05, 0.06, 0.09, 0.8)
@export var floor_color := Color(0.16, 0.36, 0.2, 0.9)
@export var border_color := Color(0.37, 0.83, 1.0, 0.9)
@export var player_color := Color(0.37, 0.83, 1.0)
@export var enemy_color := Color(1.0, 0.25, 0.3)
@export var hit_color := Color(0.25, 1.0, 0.45)

var player: Node3D
var enemy: Node3D
var room: Node

var _scale := 1.0
var _trail: Array[Vector3] = []
var _t := 0.0


func setup(p: Node3D, e: Node3D, r: Node) -> void:
	player = p
	enemy = e
	room = r


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -margin - map_size
	offset_right = -margin
	offset_top = margin
	offset_bottom = margin + map_size


func _process(delta: float) -> void:
	_t += delta
	# Keep a short trail of the ball while it's flying.
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty():
		_trail.clear()
	else:
		_trail.append((bullets[0] as Node3D).global_position)
		if _trail.size() > 40:
			_trail.pop_front()
	queue_redraw()


func _w2m(p: Vector3) -> Vector2:
	return size * 0.5 + Vector2(p.x, p.z) * _scale


func _draw() -> void:
	var pad := 10.0
	_scale = (minf(size.x, size.y) - pad * 2.0) / (world_half * 2.0)

	# Panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = background
	sb.border_color = border_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

	# Arena floor
	var a := _w2m(Vector3(-19.5, 0, -19.5))
	var b := _w2m(Vector3(19.5, 0, 19.5))
	draw_rect(Rect2(a, b - a), floor_color)
	draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.35), false, 1.0)

	if room == null or player == null:
		return

	# Structures
	if room.has_method("get_map_bodies"):
		for body in room.get_map_bodies():
			if not is_instance_valid(body):
				continue
			for part in body.get_meta("parts", []):
				_draw_part(body.global_transform * part.xf, part.size, part.color)

	# Aim path, copied from the 3D preview
	var preview = player.get("preview")
	if preview != null:
		for seg in preview.segments:
			draw_dashed_line(_w2m(seg[0]), _w2m(seg[1]), seg[2], 2.0, 4.0)
		for m in preview.markers:
			var mp := _w2m(m.pos)
			match m.kind:
				"bounce":
					draw_circle(mp, 3.0, m.color)
				"hit":
					var pulse := 0.5 + 0.5 * sin(_t * 10.0)
					draw_arc(mp, 7.0 + pulse * 3.0, 0.0, TAU, 24, Color(hit_color, 0.6), 1.5)
					draw_circle(mp, 5.0, hit_color)
				"floor":
					var c := Color(0.6, 0.6, 0.6)
					draw_line(mp + Vector2(-4, -4), mp + Vector2(4, 4), c, 2.0)
					draw_line(mp + Vector2(-4, 4), mp + Vector2(4, -4), c, 2.0)

	# Live ball + trail
	if _trail.size() > 1:
		for i in range(1, _trail.size()):
			var alpha := float(i) / _trail.size()
			draw_line(_w2m(_trail[i - 1]), _w2m(_trail[i]), Color(1, 0.4, 0.3, alpha), 2.0)
	for bl in get_tree().get_nodes_in_group("bullets"):
		var col := Color.WHITE
		if bl.get("mat") != null:
			col = bl.mat.albedo_color
		draw_circle(_w2m(bl.global_position), 3.5, col)

	# Enemy
	if is_instance_valid(enemy) and enemy.visible:
		var ep := _w2m(enemy.global_position)
		var r := maxf(4.0, 0.5 * float(enemy.get("body_scale") if enemy.get("body_scale") != null else 1.0) * _scale)
		var pulse2 := 0.5 + 0.5 * sin(_t * 6.0)
		draw_arc(ep, r + 3.0 + pulse2 * 3.0, 0.0, TAU, 24, Color(enemy_color, 0.5), 1.5)
		draw_circle(ep, r, enemy_color)

	# Player: view cone + arrow
	var pp := _w2m(player.global_position)
	var fwd3 := -player.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var cone := 40.0
	var half_fov := deg_to_rad(40.0)
	draw_colored_polygon(PackedVector2Array([pp, pp + fwd.rotated(-half_fov) * cone, pp + fwd.rotated(half_fov) * cone]), Color(player_color, 0.15))
	var side := fwd.orthogonal()
	draw_colored_polygon(PackedVector2Array([pp + fwd * 8.0, pp - fwd * 5.0 + side * 5.0, pp - fwd * 2.0, pp - fwd * 5.0 - side * 5.0]), player_color)



func _draw_part(xf: Transform3D, part_size: Vector3, color: Color) -> void:
	var h := part_size * 0.5
	var pts := PackedVector2Array()
	for c in [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]:
		pts.append(_w2m(xf * c))
	draw_colored_polygon(pts, color.darkened(0.1))
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.5), 1.0)
