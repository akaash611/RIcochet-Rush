extends CharacterBody3D
## A faceless humanoid. It can only be hurt by a ricochet (see bullet.gd).
## When hit it tells the room (signal) so the room can move it and reshuffle
## the obstacles.

signal ricocheted

## Off by default: a ricochet takes a while to arrive, so a moving target is very hard to hit.
## Turn on for extra difficulty; it wanders faster after every hit.
@export var wanders: bool = false
## Overall size of the enemy. 1.0 = the old 2 m tall figure; 1.6 = about 3.2 m.
@export var size: float = 1.6
@export var base_speed: float = 1.5
@export var speed_increase_per_hit: float = 0.5
@export var shrink_per_hit: float = 0.04
@export var min_scale: float = 0.6

var hits_taken: int = 0
var current_speed: float = 0.0
var move_dir: Vector3 = Vector3.ZERO
var change_dir_timer: float = 0.0
var body_scale: float = 1.0

var figure: Node3D
var _player: Node3D

@onready var collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	body_scale = size
	_build_figure()
	_apply_scale()

func _physics_process(delta: float) -> void:
	# Always turn to face the player (it has no face, so it just stares).
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player:
		var target := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
		if target.distance_squared_to(global_position) > 0.01:
			look_at(target, Vector3.UP)

	# Stands still unless "wanders" is on (and then only after the first hit).
	if not wanders or hits_taken == 0:
		return

	change_dir_timer -= delta
	if change_dir_timer <= 0.0:
		_pick_new_direction()

	velocity = Vector3(move_dir.x * current_speed, 0.0, move_dir.z * current_speed)
	var collision_info := move_and_collide(velocity * delta)
	if collision_info:
		move_dir = move_dir.bounce(collision_info.get_normal()).normalized()
		move_dir.y = 0.0

## Called by the bullet when an armed (already-bounced) bullet connects.
func take_ricochet_hit() -> void:
	hits_taken += 1
	current_speed = base_speed + hits_taken * speed_increase_per_hit
	body_scale = size * max(1.0 - hits_taken * shrink_per_hit, min_scale)
	set_active(false)   # vanish until the room finds a new spot
	ricocheted.emit()

## Hide and freeze while the room reshuffles things.
func set_active(active: bool) -> void:
	visible = active
	set_physics_process(active)

## Called by the room once it has picked a new spot.
func respawn(pos: Vector3) -> void:
	_apply_scale()
	global_position = Vector3(pos.x, body_scale + 0.02, pos.z)  # feet on the floor (floor top is y = 0)
	_pick_new_direction()
	set_active(true)

func _pick_new_direction() -> void:
	change_dir_timer = randf_range(0.8, 2.0)
	var angle := randf_range(0.0, TAU)
	move_dir = Vector3(cos(angle), 0, sin(angle)).normalized()

func _apply_scale() -> void:
	figure.scale = Vector3.ONE * body_scale
	var capsule := collision.shape as CapsuleShape3D
	capsule.radius = 0.5 * body_scale
	capsule.height = 2.0 * body_scale

# ---------------------------------------------------------------- the body
# Everything is positioned around the body's centre; feet at y = -1, top of
# the head at y = +1 (matches the 2m capsule collision shape).

func _build_figure() -> void:
	figure = Node3D.new()
	figure.name = "Figure"
	add_child(figure)

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.84, 0.80)
	skin.roughness = 0.9

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.9

	# Legs
	for side in [-1.0, 1.0]:
		_part(CapsuleMesh.new(), 0.09, 0.9, Vector3(0.12 * side, -0.55, 0.0), Vector3.ZERO, dark)

	# Torso (dark suit)
	var torso := BoxMesh.new()
	torso.size = Vector3(0.5, 0.7, 0.26)
	_part_mesh(torso, Vector3(0.0, 0.25, 0.0), Vector3.ZERO, dark)

	# Arms hanging slightly away from the body
	for side in [-1.0, 1.0]:
		_part(CapsuleMesh.new(), 0.06, 0.75, Vector3(0.33 * side, 0.2, 0.0), Vector3(0.0, 0.0, 4.0 * side), dark)

	# Neck + smooth, completely blank head: no eyes, no mouth, no nose.
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.06
	neck.height = 0.14
	_part_mesh(neck, Vector3(0.0, 0.65, 0.0), Vector3.ZERO, skin)

	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.34
	_part_mesh(head, Vector3(0.0, 0.83, 0.0), Vector3.ZERO, skin)

func _part(mesh: Mesh, radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	if mesh is CapsuleMesh:
		mesh.radius = radius
		mesh.height = height
	_part_mesh(mesh, pos, rot_deg, mat)

func _part_mesh(mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees = rot_deg
	figure.add_child(inst)
