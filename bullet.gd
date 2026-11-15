extends CharacterBody3D

const TrajectoryPreview = preload("res://trajectory_preview.gd")

@export var base_speed: float = 25.0
@export var speed_gain_per_bounce: float = 10.0
@export var max_speed: float = 80.0
@export var max_lifetime: float = 15.0   # safety net: bullet returns to you after this long


var direction: Vector3 = Vector3.ZERO
var current_speed: float
var bounce_count: int = 0
var is_armed: bool = false
var consumed: bool = false
var age: float = 0.0
var mat: StandardMaterial3D

@onready var mesh: MeshInstance3D = $MeshInstance3D

# Collision layers: 1 = walls/obstacles, 2 = player, 3 (value 4) = enemy.
# Walls are handled by move_and_collide(). The enemy and player are also
# CharacterBody3Ds, and Jolt doesn't let two kinematic bodies collide, so for
# those we sweep the bullet's path through the physics space instead
# (a ray for the enemy, which is exactly what the trajectory preview draws,
# and a small sphere cast for catching the bullet). Sweeps mean even a
# 55 u/s bullet can't tunnel through anything.
const ENEMY_MASK := 4
const PLAYER_MASK := 2
const BULLET_RADIUS := 0.15
const CATCH_RADIUS := 0.35

var _catch_shape := SphereShape3D.new()

func _ready() -> void:
	add_to_group("bullets")
	current_speed = base_speed
	_catch_shape.radius = CATCH_RADIUS

	# Give the bullet a glowing material we can change color on
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat

func _physics_process(delta: float) -> void:
	if consumed:
		return

	age += delta
	if age > max_lifetime:
		_return_to_player()
		return

	var start := global_position
	var collision := move_and_collide(direction * current_speed * delta)
	var end := global_position

	# Did we pass through the enemy this tick?
	var space := get_world_3d().direct_space_state
	var enemy_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, ENEMY_MASK))
	if not enemy_hit.is_empty():
		_hit_enemy(enemy_hit)
		return

	# Did we pass through the player? (only once armed, so you can catch it)
	if is_armed and _touched_player(space, start, end):
		_return_to_player()
		return

	if collision:
		# No ricochets off the floor: the shot dies there and you get the ball back.
		if TrajectoryPreview.is_floor(collision.get_collider(), collision.get_position(), collision.get_normal()):
			_fizzle()
			return
		_handle_wall_bounce(collision.get_normal())


## Space (held) calls this: the ball flies straight back to you, through
## anything, and can't hit the enemy on the way. Basically a quick reload.


func _fizzle() -> void:
	consumed = true
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.2)
	tween.tween_callback(_return_to_player)

func _hit_enemy(hit: Dictionary) -> void:
	var enemy: Node = hit.collider
	if is_armed:
		_consume_on_enemy_hit(enemy)
	else:
		# Unarmed bullet harmlessly bounces off enemies: no direct kills!
		var normal: Vector3 = hit.normal
		global_position = hit.position + normal * BULLET_RADIUS
		direction = direction.bounce(normal).normalized()

func _touched_player(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _catch_shape
	params.transform = Transform3D(Basis.IDENTITY, start)
	params.motion = end - start
	params.collision_mask = PLAYER_MASK
	var result := space.cast_motion(params)
	return result.size() == 2 and result[1] < 1.0

func _handle_wall_bounce(wall_normal: Vector3) -> void:
	direction = direction.bounce(wall_normal).normalized()
	bounce_count += 1
	current_speed = min(current_speed + speed_gain_per_bounce, max_speed)

	# Arm the bullet on its first wall bounce!
	if not is_armed:
		is_armed = true
		mat.albedo_color = Color(1.0, 0.15, 0.15)
		mat.emission = Color(1.0, 0.15, 0.15)
		mat.emission_energy_multiplier = 5.0

func _consume_on_enemy_hit(enemy: Node) -> void:
	consumed = true
	mesh.visible = false

	# The ricochet connected: the bullet is spent and you get it back.
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("catch_bullet"):
		player.catch_bullet()
	if enemy.has_method("take_ricochet_hit"):
		enemy.take_ricochet_hit()

	_hit_stop(0.05)
	queue_free()

func _return_to_player() -> void:
	consumed = true
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("catch_bullet"):
		player.catch_bullet()
	queue_free()

func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	# The timer restores time itself, so it still works after this bullet is freed
	# (before, freeing the bullet mid-pause could leave the game in slow motion).
	get_tree().create_timer(duration, true, false, true).timeout.connect(Engine.set_time_scale.bind(1.0))
