extends Node3D
## Draws a dotted line showing where a bullet fired right now would go,
## including each reflection off walls and obstacles.
## The player calls show_path() / clear_path() every physics frame.
## It also keeps the path as plain data (segments + markers) so the minimap
## can draw exactly the same thing in 2D.
## The floor does NOT bounce: a shot that reaches the floor ends there.

@export var max_bounces: int = 4
@export var max_length: float = 70.0
@export var dot_spacing: float = 0.5
@export var dot_size: float = 0.09
@export var bounce_dot_size: float = 0.3
@export var bullet_radius: float = 0.15   # matches the bullet's collision sphere
@export var wall_mask: int = 1            # walls + obstacles
@export var enemy_mask: int = 4           # the enemy

const MAX_DOTS := 400
const UNARMED_COLOR := Color(1.0, 1.0, 1.0)
# After the first wall bounce the bullet is "armed" (red) and speeds up with
# every bounce, so the line heats up from red toward yellow.
const ARMED_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.25),
	Color(1.0, 0.5, 0.15),
	Color(1.0, 0.75, 0.2),
	Color(1.0, 0.95, 0.35),
]
const HIT_COLOR := Color(0.25, 1.0, 0.45)
const FLOOR_COLOR := Color(0.55, 0.55, 0.55)

## For the minimap: [from: Vector3, to: Vector3, color: Color] per straight piece.
var segments: Array = []
## For the minimap: {pos, color, kind} with kind = "bounce" | "hit" | "floor".
var markers: Array = []
var would_hit: bool = false

var _mm: MultiMesh
var _sphere := SphereShape3D.new()   # same size as the bullet


func _ready() -> void:
	_sphere.radius = bullet_radius
	top_level = true   # dots live in world space, not player space
	global_transform = Transform3D.IDENTITY

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = sphere
	_mm.instance_count = MAX_DOTS
	_mm.visible_instance_count = 0

	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	add_child(inst)


func clear_path() -> void:
	_mm.visible_instance_count = 0
	segments.clear()
	markers.clear()
	would_hit = false


## Returns true if this shot would end in a ricochet hit on the enemy.
## Follows exactly what the real bullet does: a bullet-sized sphere sweeps
## through walls/obstacles and bounces; a thin ray (the bullet's centre line)
## is what can hit the enemy; the first wall bounce "arms" the bullet.
func show_path(origin: Vector3, direction: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var pos := origin
	var dir := direction.normalized()
	var armed := false
	var bounces := 0
	var remaining := max_length
	var carry := dot_spacing * 0.8   # distance from segment start to the next dot
	var count := 0
	would_hit = false
	segments.clear()
	markers.clear()

	for _segment in range(max_bounces + 1):
		var wall := _wall_sweep(space, pos, dir, remaining)
		var seg_len: float = remaining if wall.is_empty() else wall.travel
		var seg_end := pos + dir * seg_len

		# Can this segment reach the enemy before the wall?
		var enemy_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, seg_end, enemy_mask))
		if not enemy_hit.is_empty():
			seg_len = pos.distance_to(enemy_hit.position)

		var color := UNARMED_COLOR
		if armed:
			color = ARMED_COLORS[mini(bounces - 1, ARMED_COLORS.size() - 1)]

		# Dots along this segment.
		var t := carry
		while t < seg_len and count < MAX_DOTS - 2:
			_set_dot(count, pos + dir * t, dot_size, color)
			count += 1
			t += dot_spacing
		carry = t - seg_len
		remaining -= seg_len
		segments.append([pos, pos + dir * seg_len, color])

		if not enemy_hit.is_empty():
			if armed:
				# This shot would land: end the line with a big green marker.
				_set_dot(count, enemy_hit.position, bounce_dot_size * 1.6, HIT_COLOR)
				count += 1
				markers.append({"pos": enemy_hit.position, "color": HIT_COLOR, "kind": "hit"})
				would_hit = true
				break
			# Unarmed bullets just bounce off the enemy (same as bullet.gd).
			var enemy_normal: Vector3 = enemy_hit.normal
			_set_dot(count, enemy_hit.position + enemy_normal * 0.03, bounce_dot_size, color)
			count += 1
			markers.append({"pos": enemy_hit.position, "color": color, "kind": "bounce"})
			pos = enemy_hit.position + enemy_normal * bullet_radius
			dir = dir.bounce(enemy_normal).normalized()
			continue

		if wall.is_empty() or remaining <= 0.0:
			break

		# Floor: no ricochet. The shot dies here (same as bullet.gd).
		if wall.floor:
			_set_dot(count, wall.point - wall.normal * bullet_radius + wall.normal * 0.03, bounce_dot_size, FLOOR_COLOR)
			count += 1
			markers.append({"pos": wall.point, "color": FLOOR_COLOR, "kind": "floor"})
			break

		# Wall/obstacle bounce: marker on the surface, reflect, keep going.
		armed = true
		bounces += 1
		var normal: Vector3 = wall.normal
		pos = wall.point
		_set_dot(count, pos - normal * bullet_radius + normal * 0.03, bounce_dot_size, color)
		count += 1
		markers.append({"pos": pos, "color": color, "kind": "bounce"})
		dir = dir.bounce(normal).normalized()

	_mm.visible_instance_count = count
	return would_hit


## Sweeps the bullet-sized sphere along dir. Returns {} if nothing is in the
## way, otherwise {travel, point (sphere centre at contact), normal}.
func _wall_sweep(space: PhysicsDirectSpaceState3D, pos: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sphere
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.motion = dir * dist
	params.collision_mask = wall_mask
	var fractions := space.cast_motion(params)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return {}

	var travel: float = fractions[0] * dist
	var contact := pos + dir * travel

	# Surface normal at the contact: nudge the sphere into the surface and ask.
	params.transform = Transform3D(Basis.IDENTITY, contact + dir * 0.03)
	params.motion = Vector3.ZERO
	var rest := space.get_rest_info(params)
	var normal := Vector3.ZERO
	var collider: Object = null
	if not rest.is_empty():
		normal = rest.normal
		collider = instance_from_id(rest.collider_id)
	else:
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(contact, contact + dir * (bullet_radius + 0.2), wall_mask))
		if ray.is_empty():
			return {}
		normal = ray.normal
		collider = ray.collider
	if normal.dot(dir) > 0.0:
		normal = -normal
	normal = normal.normalized()
	return {"travel": travel, "point": contact, "normal": normal, "floor": is_floor(collider, contact, normal)}


## True if this surface is the arena floor (shared with bullet.gd).
static func is_floor(collider: Object, point: Vector3, normal: Vector3) -> bool:
	if collider is Node and (collider as Node).is_in_group("Floor"):
		return true
	return normal.y > 0.9 and point.y < 0.3


func _set_dot(i: int, at: Vector3, size: float, color: Color) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
	_mm.set_instance_color(i, color)
