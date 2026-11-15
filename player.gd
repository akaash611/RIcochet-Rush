extends CharacterBody3D

const TrajectoryPreview = preload("res://trajectory_preview.gd")

@export var move_speed: float = 7.5
@export var mouse_sensitivity: float = 0.0025
@export var bullet_scene: PackedScene
@export var normal_fov:float=95.0
@export var zoom_fov: float=40.0

# Aim ray sees walls/obstacles (layer 1) and the enemy (layer 3 = value 4).
const AIM_MASK := 1 | 4
# Where the gun sits in camera space, and where the bullet leaves it.
const GUN_POS := Vector3(0.28, -0.26, -0.55)
const MUZZLE_POS := Vector3(0.28, -0.245, -1.02)

var has_bullet: bool = true
## Set by the room each level. 1.0 = normal ball speed.
var ball_speed_multiplier:float =1.0
## True when the aim path currently ends on the enemy (crosshair goes green).
var aim_would_hit: bool = false
## The room turns this off when the round ends (win or lose).
var controls_enabled: bool = true

@onready var camera: Camera3D = $Camera3D
@onready var muzzle: Marker3D = $Camera3D/Muzzle
@onready var shoot_sound : AudioStreamPlayer= $"Shoot sound"
@onready var reload_sound : AudioStreamPlayer= $"Reload sound"

var gun: Node3D
var ammo_orb: MeshInstance3D
var preview: TrajectoryPreview


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	muzzle.position = MUZZLE_POS
	_build_gun()
	preview = TrajectoryPreview.new()
	add_child(preview)


func set_controls_enabled(on: bool) -> void:
	controls_enabled = on
	if not on:
		velocity = Vector3.ZERO
		aim_would_hit = false
		preview.clear_path()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		quick_reload()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Look freely in every direction (yaw on the body, pitch on the camera).
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# First click just grabs the mouse, it doesn't fire.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			shoot()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return
	# The player is stuck on a rail along the world X axis: left/right only.
	# "Right" follows where you are looking, so the keys never feel reversed.
	var input_x := Input.get_axis("ui_left", "ui_right")
	var facing_sign := 1.0 if global_transform.basis.x.x >= 0.0 else -1.0
	velocity = Vector3(input_x * facing_sign * move_speed, 0.0, 0.0)
	var target_fov:=zoom_fov if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)else normal_fov
	camera.fov=lerp(camera.fov,target_fov,10.0 * delta)
	move_and_slide()

	# Dotted trajectory preview, only while you are holding a bullet.
	if has_bullet and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var origin := muzzle.global_position
		aim_would_hit = preview.show_path(origin, get_aim_direction(origin))
	else:
		aim_would_hit = false
		preview.clear_path()


## Direction from the muzzle to whatever the crosshair is pointing at.
func get_aim_direction(origin: Vector3) -> Vector3:
	var cam_origin := camera.global_position
	var cam_forward := -camera.global_transform.basis.z
	var far_point := cam_origin + cam_forward * 100.0
	var query := PhysicsRayQueryParameters3D.create(cam_origin, far_point, AIM_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.position if not hit.is_empty() else far_point
	var to_target := target - origin
	if to_target.length() < 0.5:
		return cam_forward
	return to_target.normalized()


func shoot() -> void:
	if not has_bullet or bullet_scene == null:
		return

	var origin = muzzle.global_position
	var bullet = bullet_scene.instantiate() as CharacterBody3D

	bullet.direction = get_aim_direction(origin)
	bullet.base_speed *= ball_speed_multiplier
	bullet.max_speed *= ball_speed_multiplier

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin


	has_bullet = false
	_update_ammo_visual()
	_recoil()
	_play_sfx(shoot_sound)


## R: instant reload. The ball in flight disappears and you have it again.
func quick_reload() -> void:
	if has_bullet:
		return
	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	catch_bullet()


func catch_bullet() -> void:
	has_bullet = true
	_update_ammo_visual()
	_play_sfx(reload_sound)


# ---------------------------------------------------------------- gun model

func _build_gun() -> void:
	gun = Node3D.new()
	gun.name = "Gun"
	gun.position = GUN_POS
	camera.add_child(gun)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.14, 0.17)
	metal.metallic = 0.7
	metal.roughness = 0.35

	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.45, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.8, 1.0)
	glow.emission_energy_multiplier = 1.0

	_add_box(Vector3(0.07, 0.10, 0.34), Vector3(0.0, 0.0, 0.0), 0.0, metal)      # receiver
	_add_box(Vector3(0.06, 0.15, 0.07), Vector3(0.0, -0.11, 0.11), 15.0, metal)  # grip
	_add_box(Vector3(0.075, 0.015, 0.20), Vector3(0.0, 0.057, 0.0), 0.0, glow)   # glowing top strip

	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.022
	barrel_mesh.bottom_radius = 0.022
	barrel_mesh.height = 0.30
	barrel.mesh = barrel_mesh
	barrel.material_override = metal
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.015, -0.31)
	gun.add_child(barrel)

	# Glowing round on top of the gun: visible while you are holding a bullet.
	ammo_orb = MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.022
	orb_mesh.height = 0.044
	ammo_orb.mesh = orb_mesh
	ammo_orb.material_override = glow
	ammo_orb.position = Vector3(0.0, 0.09, 0.02)
	gun.add_child(ammo_orb)
	_update_ammo_visual()


func _add_box(size: Vector3, pos: Vector3, tilt_deg: float, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees.x = tilt_deg
	gun.add_child(inst)


func _update_ammo_visual() -> void:
	if ammo_orb:
		ammo_orb.visible = has_bullet


func _recoil() -> void:
	var tween := create_tween()
	gun.position = GUN_POS
	tween.tween_property(gun, "position", GUN_POS + Vector3(0.0, 0.02, 0.09), 0.05)
	tween.tween_property(gun, "position", GUN_POS, 0.18).set_ease(Tween.EASE_OUT)
	
	## Plays a sound effect with a tiny random pitch change so it doesn't
	## sound robotic when you hear it over and over
func _play_sfx(sound: AudioStreamPlayer) -> void:
	sound.pitch_scale = randf_range(0.93,1.07)
	sound.play()
