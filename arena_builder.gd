extends RefCounted
## Builds the arena's look: chunky, multi-part sci-fi structures (sloped end
## caps, tiled panels, dark plinths, glowing trim strips, pipes, holes you can
## shoot through) instead of plain boxes.
##
## Every structure is ONE StaticBody3D on collision layer 1 (walls/obstacles),
## so bullets, the trajectory preview and the enemy-hiding check all just work.
## Each collidable piece is also recorded in the body's "parts" metadata so the
## minimap can draw its footprint and the room can avoid spawning the enemy
## inside it.

const TILE := Color("dcd3e8")      # pale lavender-white tiles (the slanted blocks in the reference)
const DARK := Color("3b3b48")      # plinths, roof frames, vents
const METAL := Color("8c909b")     # pipes, roof spines
const GLOW := Color("5fd4ff")      # cyan trim strips
const FLOOR_GREEN := Color("4caf50")
const WALL_GREY := Color("cfd0d8")

static var _grid_tex: Texture2D
static var _hazard_tex: Texture2D
static var _mat_cache := {}


# ------------------------------------------------------------- public API

## A random structure, painted mainly in `main`. Origin is its centre on the floor.
static func make_structure(main: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Structure"
	body.add_to_group("Obstacles")
	body.set_meta("parts", [])
	match randi() % 6:
		0: _bunker(body, main)
		1: _gate(body, main)
		2: _window_wall(body, main)
		3: _l_block(body, main)
		4: _tower(body, main)
		_: _ramp_block(body, main)
	_finalize(body)
	return body


## Skins the floor / walls / ceiling from room.tscn and adds trim + corner pillars.
## Returns the extra static bodies it created (so the minimap can draw them).
static func decorate_room(room: Node3D) -> Array:
	var floor_node := room.get_node_or_null("Floor") as CSGBox3D
	if floor_node:
		floor_node.material = mat(FLOOR_GREEN)
	for wall_name in ["Wall_North", "Wall_South", "Wall_East", "Wall_West"]:
		var w := room.get_node_or_null(wall_name) as CSGBox3D
		if w:
			w.material = mat(WALL_GREY)
	var ceiling := room.get_node_or_null("Ceiling") as CSGBox3D
	if ceiling:
		ceiling.material = mat(Color("e4e2ea"))

	var decor := Node3D.new()
	decor.name = "Decor"
	room.add_child(decor)

	# Dark skirt + glowing line along the bottom of every wall (visual only).
	var inner := 19.5
	for side in [-1.0, 1.0]:
		_deco_box(decor, Vector3(39.0, 0.8, 0.3), Vector3(0, 0.4, side * (inner - 0.15)), mat(DARK, false))
		_deco_box(decor, Vector3(39.0, 0.07, 0.32), Vector3(0, 0.84, side * (inner - 0.15)), mat(GLOW, false, 3.0))
		_deco_box(decor, Vector3(0.3, 0.8, 39.0), Vector3(side * (inner - 0.15), 0.4, 0), mat(DARK, false))
		_deco_box(decor, Vector3(0.32, 0.07, 39.0), Vector3(side * (inner - 0.15), 0.84, 0), mat(GLOW, false, 3.0))
	# Light strips on the ceiling.
	for x in [-10.0, 0.0, 10.0]:
		_deco_box(decor, Vector3(0.6, 0.05, 30.0), Vector3(x, 9.47, 0), mat(Color(1, 1, 1), false, 2.0))

	# Chunky pillars in the four corners (these do collide).
	var bodies: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := StaticBody3D.new()
			p.name = "CornerPillar"
			p.set_meta("parts", [])
			_box(p, Vector3(2.0, 0.6, 2.0), Vector3(0, 0.3, 0), mat(DARK))
			_box(p, Vector3(1.5, 8.9, 1.5), Vector3(0, 0.6 + 4.45, 0), mat(TILE))
			_box(p, Vector3(1.56, 0.08, 1.56), Vector3(0, 0.62, 0), mat(GLOW, false, 3.0), 0.0, false)
			room.add_child(p)
			p.position = Vector3(sx * 18.75, 0, sz * 18.75)
			_finalize(p)
			bodies.append(p)
	return bodies


static func mat(color: Color, tiled := true, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), tiled, glow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if tiled:
		m.albedo_texture = _grid()
		m.uv1_triplanar = true          # tiles show on every face without UV work
		m.uv1_scale = Vector3.ONE * 0.5 # one tile = 2 m
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mat_cache[key] = m
	return m


static func hazard_mat() -> StandardMaterial3D:
	if _mat_cache.has("hazard"):
		return _mat_cache["hazard"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _hazard()
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8
	m.roughness = 0.6
	_mat_cache["hazard"] = m
	return m


# -------------------------------------------------------------- structures

## Long block with sloped tiled end caps, roof frame, vents and a pipe
## (closest to the purple building in the reference picture).
static func _bunker(body: StaticBody3D, main: Color) -> void:
	var L := randf_range(7.5, 10.0)
	var W := randf_range(3.0, 3.8)
	var H := randf_range(2.6, 3.4)
	var cap := randf_range(1.8, 2.4)
	var core := L - 2.0 * cap
	var base := 0.35

	_box(body, Vector3(L + 0.4, base, W + 0.4), Vector3(0, base * 0.5, 0), mat(DARK))
	_box(body, Vector3(L + 0.42, 0.06, W + 0.42), Vector3(0, base + 0.02, 0), mat(GLOW, false, 3.0), 0.0, false)
	_box(body, Vector3(core, H, W), Vector3(0, base + H * 0.5, 0), mat(main))
	# Roof frame and a raised metal spine.
	_box(body, Vector3(core + 0.2, 0.3, W + 0.2), Vector3(0, base + H + 0.15, 0), mat(DARK, false))
	_box(body, Vector3(core * 0.8, 0.45, W * 0.4), Vector3(0, base + H + 0.52, 0), mat(METAL, false))

	for side in [-1.0, 1.0]:
		var x: float = side * (core * 0.5 + cap * 0.5)
		var low := H * 0.5
		var slope_h := H - low + 0.3
		_box(body, Vector3(cap, low, W), Vector3(x, base + low * 0.5, 0), mat(TILE))
		_wedge(body, Vector3(cap, slope_h, W), Vector3(x, base + low + slope_h * 0.5, 0), mat(TILE), 0.0 if side > 0 else 180.0)
		# Vent panels on both long sides (decor).
		_box(body, Vector3(core * 0.5, H * 0.45, 0.08), Vector3(0, base + H * 0.45, side * (W * 0.5 + 0.04)), mat(DARK, false), 0.0, false)
		_box(body, Vector3(core * 0.5, 0.05, 0.1), Vector3(0, base + H * 0.7, side * (W * 0.5 + 0.05)), mat(GLOW, false, 3.0), 0.0, false)

	_cyl(body, 0.16, H + 0.6, Vector3(core * 0.5 - 0.5, base + (H + 0.6) * 0.5, W * 0.5 + 0.25), mat(METAL, false))


## Two pillars with a beam on top: a big hole you can shoot through.
static func _gate(body: StaticBody3D, main: Color) -> void:
	var gap := randf_range(2.6, 3.6)
	var open_h := randf_range(3.6, 4.6)
	var pw := 1.4
	var depth := randf_range(1.6, 2.2)
	for side in [-1.0, 1.0]:
		var x: float = side * (gap * 0.5 + pw * 0.5)
		_box(body, Vector3(pw + 0.3, 0.5, depth + 0.3), Vector3(x, 0.25, 0), mat(DARK))
		_box(body, Vector3(pw, open_h - 0.5, depth), Vector3(x, 0.5 + (open_h - 0.5) * 0.5, 0), mat(TILE))
		_box(body, Vector3(0.06, open_h - 0.9, depth * 0.6), Vector3(x - side * (pw * 0.5 + 0.03), 0.5 + (open_h - 0.5) * 0.5, 0), mat(GLOW, false, 3.0), 0.0, false)
	var span := gap + 2.0 * pw
	_box(body, Vector3(span + 0.6, 1.1, depth + 0.2), Vector3(0, open_h + 0.55, 0), mat(main))
	_box(body, Vector3(span + 0.8, 0.25, depth + 0.4), Vector3(0, open_h + 1.225, 0), mat(DARK, false))
	_box(body, Vector3(gap, 0.06, depth * 0.6), Vector3(0, open_h - 0.03, 0), mat(GLOW, false, 3.0), 0.0, false)
	# Sloped shoulders on the beam ends.
	_wedge(body, Vector3(1.0, 1.1, depth + 0.2), Vector3(span * 0.5 + 0.8, open_h + 0.55, 0), mat(main), 0.0)
	_wedge(body, Vector3(1.0, 1.1, depth + 0.2), Vector3(-span * 0.5 - 0.8, open_h + 0.55, 0), mat(main), 180.0)


## A wall with a window hole and sloped buttresses on each end.
static func _window_wall(body: StaticBody3D, main: Color) -> void:
	var L := randf_range(6.5, 9.0)
	var H := randf_range(4.2, 5.2)
	var T := 0.9
	var hw := randf_range(1.8, 2.6)          # hole width
	var hh := randf_range(1.4, 2.0)          # hole height
	var hy := randf_range(1.2, 1.8)          # bottom of hole
	var hx := randf_range(-L * 0.5 + hw * 0.5 + 1.0, L * 0.5 - hw * 0.5 - 1.0)
	var y0 := 0.4
	var wall_h := H - y0

	_box(body, Vector3(L + 0.3, y0, T + 0.4), Vector3(0, y0 * 0.5, 0), mat(DARK))
	var left_w := (hx - hw * 0.5) + L * 0.5
	var right_w := L * 0.5 - (hx + hw * 0.5)
	_box(body, Vector3(left_w, wall_h, T), Vector3(-L * 0.5 + left_w * 0.5, y0 + wall_h * 0.5, 0), mat(main))
	_box(body, Vector3(right_w, wall_h, T), Vector3(L * 0.5 - right_w * 0.5, y0 + wall_h * 0.5, 0), mat(main))
	_box(body, Vector3(hw, hy - y0, T), Vector3(hx, y0 + (hy - y0) * 0.5, 0), mat(TILE))
	var top := hy + hh
	_box(body, Vector3(hw, H - top, T), Vector3(hx, top + (H - top) * 0.5, 0), mat(TILE))
	# Glowing frame around the hole (decor).
	var g := mat(GLOW, false, 3.0)
	_box(body, Vector3(hw, 0.07, T + 0.04), Vector3(hx, hy, 0), g, 0.0, false)
	_box(body, Vector3(hw, 0.07, T + 0.04), Vector3(hx, top, 0), g, 0.0, false)
	_box(body, Vector3(0.07, hh, T + 0.04), Vector3(hx - hw * 0.5, hy + hh * 0.5, 0), g, 0.0, false)
	_box(body, Vector3(0.07, hh, T + 0.04), Vector3(hx + hw * 0.5, hy + hh * 0.5, 0), g, 0.0, false)
	# Cap rail and end buttresses.
	_box(body, Vector3(L + 0.2, 0.3, T + 0.3), Vector3(0, H + 0.15, 0), mat(DARK, false))
	_wedge(body, Vector3(1.4, H * 0.6, T), Vector3(L * 0.5 + 0.7, H * 0.3, 0), mat(TILE), 0.0)
	_wedge(body, Vector3(1.4, H * 0.6, T), Vector3(-L * 0.5 - 0.7, H * 0.3, 0), mat(TILE), 180.0)


## L-shaped block: a low sloped arm and a taller tiled tower arm, plus a hazard crate.
static func _l_block(body: StaticBody3D, main: Color) -> void:
	var a := randf_range(4.5, 6.5)
	var b := randf_range(3.5, 5.0)
	var t := randf_range(1.6, 2.2)
	var h1 := randf_range(2.6, 3.6)
	var h2 := h1 + randf_range(1.0, 2.0)
	var arm_z := -b * 0.5 + t * 0.5
	var tower_x := -a * 0.5 + t * 0.5

	_box(body, Vector3(a, h1, t), Vector3(0, h1 * 0.5, arm_z), mat(main))
	_wedge(body, Vector3(a - t, 0.9, t), Vector3(t * 0.5, h1 + 0.45, arm_z), mat(main), -90.0)
	_box(body, Vector3(t, h2, b), Vector3(tower_x, h2 * 0.5, 0), mat(TILE))
	_box(body, Vector3(t + 0.25, 0.3, b + 0.25), Vector3(tower_x, h2 + 0.15, 0), mat(DARK, false))
	_box(body, Vector3(a + 0.04, 0.07, t + 0.04), Vector3(0, 0.5, arm_z), mat(GLOW, false, 3.0), 0.0, false)
	_box(body, Vector3(t + 0.04, 0.07, b + 0.04), Vector3(tower_x, 0.5, 0), mat(GLOW, false, 3.0), 0.0, false)
	_box(body, Vector3(1.2, 1.2, 1.2), Vector3(tower_x + t * 0.5 + 0.9, 0.6, arm_z + t * 0.5 + 0.9), hazard_mat(), 15.0)


## Square tower on a plinth with side fins and an antenna.
static func _tower(body: StaticBody3D, main: Color) -> void:
	var h := randf_range(4.0, 5.5)
	_box(body, Vector3(3.4, 1.0, 3.4), Vector3(0, 0.5, 0), mat(DARK))
	_box(body, Vector3(3.44, 0.07, 3.44), Vector3(0, 1.0, 0), mat(GLOW, false, 3.0), 0.0, false)
	_box(body, Vector3(2.6, h, 2.6), Vector3(0, 1.0 + h * 0.5, 0), mat(main))
	var fin_y := 1.0 + h * 0.4
	for s in [-1.0, 1.0]:
		_box(body, Vector3(0.6, h * 0.7, 0.25), Vector3(s * 1.6, fin_y, 0), mat(TILE))
		_box(body, Vector3(0.25, h * 0.7, 0.6), Vector3(0, fin_y, s * 1.6), mat(TILE))
	_box(body, Vector3(3.0, 0.5, 3.0), Vector3(0, 1.0 + h + 0.25, 0), mat(TILE))
	_cyl(body, 0.06, 1.2, Vector3(0.8, 1.0 + h + 0.5 + 0.6, 0.8), mat(METAL, false), false)


## Block with a ramp running up one side and crates on top.
static func _ramp_block(body: StaticBody3D, main: Color) -> void:
	var w := randf_range(3.0, 4.0)
	var d := randf_range(3.0, 4.0)
	var h := randf_range(2.0, 3.0)
	var rl := randf_range(2.5, 3.5)
	var ox := -rl * 0.5   # keep the whole thing centred
	_box(body, Vector3(w, h, d), Vector3(ox, h * 0.5, 0), mat(main))
	_wedge(body, Vector3(rl, h, d), Vector3(ox + w * 0.5 + rl * 0.5, h * 0.5, 0), mat(TILE), 0.0)
	_box(body, Vector3(w + 0.04, 0.07, d + 0.04), Vector3(ox, h - 0.3, 0), mat(GLOW, false, 3.0), 0.0, false)
	_box(body, Vector3(1.4, 1.0, 1.4), Vector3(ox - w * 0.25, h + 0.5, 0), hazard_mat(), 10.0)
	_box(body, Vector3(w * 0.9, 0.3, d * 0.9), Vector3(ox, h + 0.15, 0), mat(DARK, false))


# -------------------------------------------------------------- primitives

static func _box(body: Node3D, size: Vector3, pos: Vector3, m: StandardMaterial3D, yaw_deg := 0.0, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	body.add_child(mi)
	if collide:
		var sh := BoxShape3D.new()
		sh.size = size
		_add_shape(body, sh, mi.transform)
		_add_part(body, mi.transform, size, m)


## Right-angle prism: tall flat face on local -X, slope running down to +X.
static func _wedge(body: Node3D, size: Vector3, pos: Vector3, m: StandardMaterial3D, yaw_deg := 0.0, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	pm.left_to_right = 0.0
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	body.add_child(mi)
	if collide:
		_add_shape(body, pm.create_convex_shape(), mi.transform)
		_add_part(body, mi.transform, size, m)


static func _cyl(body: Node3D, radius: float, height: float, pos: Vector3, m: StandardMaterial3D, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	body.add_child(mi)
	if collide:
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		_add_shape(body, sh, mi.transform)
		_add_part(body, mi.transform, Vector3(radius * 2.0, height, radius * 2.0), m)


static func _deco_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _add_shape(body: Node3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


static func _add_part(body: Node3D, xf: Transform3D, size: Vector3, m: StandardMaterial3D) -> void:
	var parts: Array = body.get_meta("parts", [])
	var col := m.albedo_color
	if m.albedo_texture == _hazard_tex and _hazard_tex != null:
		col = Color("e8b820")
	parts.append({"xf": xf, "size": size, "color": col, "top": xf.origin.y + size.y * 0.5})
	body.set_meta("parts", parts)


## Footprint radius (for spacing structures apart) + parts sorted low→high
## so the minimap draws taller pieces on top.
static func _finalize(body: Node3D) -> void:
	var parts: Array = body.get_meta("parts", [])
	parts.sort_custom(func(a, b): return a.top < b.top)
	var r := 0.0
	for p in parts:
		var half: Vector3 = p.size * 0.5
		for c in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
			var w: Vector3 = p.xf * c
			r = maxf(r, Vector2(w.x, w.z).length())
	body.set_meta("parts", parts)
	body.set_meta("radius", r)


# ---------------------------------------------------------------- textures

static func _grid() -> Texture2D:
	if _grid_tex:
		return _grid_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1))
	var seam := Color(0.70, 0.70, 0.76)
	var mark := Color(0.80, 0.80, 0.85)
	for i in n:
		for t in 2:
			img.set_pixel(i, t, seam)
			img.set_pixel(i, n - 1 - t, seam)
			img.set_pixel(t, i, seam)
			img.set_pixel(n - 1 - t, i, seam)
	# Small "+" in the middle of each tile, like the reference panels.
	for i in range(-6, 7):
		img.set_pixel(n / 2 + i, n / 2, mark)
		img.set_pixel(n / 2, n / 2 + i, mark)
	img.generate_mipmaps()
	_grid_tex = ImageTexture.create_from_image(img)
	return _grid_tex


static func _hazard() -> Texture2D:
	if _hazard_tex:
		return _hazard_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var yellow := Color("f2c230")
	var black := Color("1d1d22")
	for y in n:
		for x in n:
			img.set_pixel(x, y, yellow if ((x + y) / 16) % 2 == 0 else black)
	img.generate_mipmaps()
	_hazard_tex = ImageTexture.create_from_image(img)
	return _hazard_tex
