extends Node3D
## Runs the arena.
##
## Round flow (only ONE of these can be true at a time, so the win and lose
## screens can never overlap any more):
##   SPAWNING -> building a new layout + placing the enemy (clock paused)
##   PLAYING  -> the countdown is running; land a ricochet before it hits 0
##   WON      -> congrats screen + music
##   LOST     -> time ran out, lose screen
##
## Each hit adds a point. If you still need more hits, the clock resets and the
## layout reshuffles. Press R (or click PLAY AGAIN) on either end screen to restart.

const ArenaBuilder = preload("res://arena_builder.gd")

enum State { SPAWNING, PLAYING, WON, LOST }

const ARENA_HALF := 18.0          # usable half-size of the 40x40 room
const OBSTACLE_COUNT := 7
const OBSTACLE_Z_MIN := -18.0
const OBSTACLE_Z_MAX := 8.0       # structures never reach the player's rail (z = 14)
const ENEMY_Z_MAX := 9.0
const PLAYER_CLEARANCE := 10.0    # enemy never spawns closer than this to you
const MIN_MOVE_DISTANCE := 9.0    # new spot must be this far from the last one
const STRUCTURE_GAP := 1.5        # space between structures so shots/enemy fit through
var OBSTACLE_COLORS: Array[Color] = [
	Color.html("#6a44b8"), # Royal Purple
	Color.html("#e0a343"), # Warm Golden Mustard
	Color.html("#c782f2"), # Bright Pastel Lavender
	Color.html("#38b6ff"), # Bright Sky Blue Accent
]

## One entry per level: how long you get, and how many ricochet hits you need.
const LEVELS := [
	{"time":45.0,"hits":1, "speed": 1.0}, # Level 1
	{"time":30.0,"hits":2, "speed": 1.5}, # Level 2
	{"time":25.0,"hits":3, "speed": 2.0}, # Level 3
	{"time":20.0,"hits":4, "speed": 2.5}, # Level 4 "FINAL"
]
## How ling the "Level X" banner stays up (the clock is paused meanwhile).
@export var level_banner_time: float = 2.0
## Timer turns red and pulses below this many seconds.
@export var warning_time: float = 3.0
@export_file("*.mp3", "*.ogg", "*.wav") var win_music_path: String = "res://vaitsez-video-game-video-game-music-574163.mp3"
@export_file("*.mp3", "*.ogg", "*.wav") var lose_sound_path: String = "res://chicken-on-tree-screaming.mp3"

@onready var player: CharacterBody3D = $player
@onready var enemy: CharacterBody3D = $Enemy
@onready var score_label: Label = $CanvasLayer/ScoreLabel
@onready var timer_label: Label = $CanvasLayer/TimerLabel
@onready var win_screen: ColorRect = $CanvasLayer/WinScreen
@onready var lose_screen: ColorRect = $CanvasLayer/LoseScreen
@onready var crosshair: Control = $CanvasLayer/Crosshair
@onready var minimap: Control = $CanvasLayer/Minimap
@onready var level_label: Label = $CanvasLayer/LevelLabel

var obstacles: Array[StaticBody3D] = []
var static_bodies: Array = []      # corner pillars (drawn on the minimap too)
var score: int = 0
var level : int = 0 # index into LEVELS (0= Level 1)
var level_hits: int=0 # hits landed in the CURRENT level
var last_enemy_pos: Vector3 = Vector3(0, 0, -10)
var state: State = State.SPAWNING
var time_left: float
var _audio: AudioStreamPlayer


func _ready() -> void:
	Engine.time_scale = 1.0   # in case a restart happened during a hit-stop
	win_screen.visible = false
	lose_screen.visible = false
	_add_restart_button(win_screen)
	_add_restart_button(lose_screen)

	_audio = AudioStreamPlayer.new()
	_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_audio)

	static_bodies = ArenaBuilder.decorate_room(self)
	crosshair.player = player
	minimap.setup(player, enemy, self)
	enemy.ricocheted.connect(_on_enemy_ricocheted)

	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_level(0)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	time_left = maxf(time_left - delta, 0.0)
	_update_timer_label()
	if time_left <= 0.0:
		_lose()


func _unhandled_input(event: InputEvent) -> void:
	if (state == State.WON or state == State.LOST) and event is InputEventKey \
			and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_restart()


## Everything the minimap should draw as solid structures.
func get_map_bodies() -> Array:
	return static_bodies + obstacles


# ------------------------------------------------------------- round flow

func _on_enemy_ricocheted() -> void:
	if state != State.PLAYING:
		return
	score += 1
	level_hits += 1
	_update_score()
	crosshair.flash_hit()
	if level_hits >= LEVELS[level].hits:
		# Level cleared!
		if level == LEVELS.size() - 1:
			_win() # that was the final level
		else:
			_start_level(level +1) # next level: new, shorter clock
	else:
		_reshuffle() # same level: enemy moves, clock keeps running

func _start_level(index: int) -> void:
	level = index
	level_hits=0
	time_left = LEVELS[level].time
	player.ball_speed_multiplier = LEVELS[level].speed
	state = State.SPAWNING # clock is paused while the banner shows
	enemy.set_active(false) # hide the enemy until the level really starts
	_update_score()
	_update_timer_label()
	_show_level_banner()
	await get_tree().create_timer(level_banner_time).timeout
	_reshuffle() # builds a new layout, then sets state = PLAYING 
	
	
func _show_level_banner() -> void:
	var info: Dictionary= LEVELS[level]
	var hits: int = info.hits
	var plural:= "" if hits == 1 else "S"
	var title:= "FINAL LEVEL" if level == LEVELS.size() - 1 else "LEVEL %d" % (level+1)
	level_label.text="%s\n%d RICOCHET%s IN %d SECONDS" % [title, hits, plural,
int(info.time)]
	level_label.visible=true
	level_label.modulate.a=1.0
	var tween := create_tween()
	tween.tween_interval(level_banner_time - 0.5)
	tween.tween_property(level_label,"modulate:a", 0.0, 0.5 ) # fade out
func _win() -> void:
	state = State.WON
	lose_screen.visible = false
	win_screen.visible = true
	_end_round()
	_play(win_music_path)


func _lose() -> void:
	state = State.LOST
	win_screen.visible = false
	lose_screen.visible = true
	lose_screen.get_node("Label").text = "TIME'S UP ON LEVEL %d\nNOW HOP OFF THE GAME. GET A JOB YOU UNEMPLOYED UNC>" % (level +1)
	_end_round()
	_play(lose_sound_path)


func _end_round() -> void:
	player.set_controls_enabled(false)
	crosshair.visible = false
	level_label.visible=false
	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_timer_label()


func _restart() -> void:
	_audio.stop()
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _play(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Sound not found: " + path)
		return
	_audio.stream = load(path)
	_audio.play()


func _add_restart_button(screen: Control) -> void:
	var btn := Button.new()
	btn.text = "PLAY AGAIN  (R)"
	btn.add_theme_font_size_override("font_size", 28)
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 0.62
	btn.anchor_bottom = 0.62
	btn.offset_left = -150
	btn.offset_right = 150
	btn.offset_bottom = 60
	btn.pressed.connect(_restart)
	screen.add_child(btn)


func _update_score() -> void:
	score_label.text = "LEVEL %d / %d | Hits: %d/%d" % [level+1, LEVELS.size(), level_hits, LEVELS[level].hits]


func _update_timer_label() -> void:
	timer_label.text = "TIME  %.1f" % time_left
	if time_left <= warning_time and state != State.WON:
		var pulse := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.008))
		timer_label.modulate = Color(1.0, 0.25, 0.25, pulse)
	else:
		timer_label.modulate = Color.WHITE


func _reshuffle() -> void:
	state = State.SPAWNING           # clock is paused while the layout is rebuilt
	enemy.set_active(false)
	_rebuild_obstacles()
	# Wait for the physics server to know about the new obstacles.
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.respawn(_pick_enemy_spot())
	if state == State.SPAWNING:
		state = State.PLAYING


# ------------------------------------------------------------ obstacles

func _rebuild_obstacles() -> void:
	for o in obstacles:
		if is_instance_valid(o):
			o.queue_free()
	obstacles.clear()

	var placed: Array = []   # [Vector2 centre, float radius]
	var colors := OBSTACLE_COLORS.duplicate()
	colors.shuffle()
	for i in OBSTACLE_COUNT:
		var body := ArenaBuilder.make_structure(colors[i % colors.size()])
		var radius: float = body.get_meta("radius")
		var spot := Vector2.INF
		for attempt in 60:
			var centre := Vector2(
				randf_range(-(ARENA_HALF - radius), ARENA_HALF - radius),
				randf_range(OBSTACLE_Z_MIN + radius, OBSTACLE_Z_MAX - radius))
			if _fits(centre, radius, placed):
				spot = centre
				break
		if spot == Vector2.INF:
			body.free()   # didn't fit this time, skip it
			continue
		placed.append([spot, radius])
		add_child(body)
		body.position = Vector3(spot.x, 0.0, spot.y)
		body.rotation.y = randf_range(0.0, TAU)   # new orientation every time
		obstacles.append(body)


func _fits(centre: Vector2, radius: float, placed: Array) -> bool:
	for other in placed:
		if centre.distance_to(other[0]) < radius + other[1] + STRUCTURE_GAP:
			return false
	return true


# --------------------------------------------------------------- enemy

func _pick_enemy_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var eye := player.global_position + Vector3(0, 1.6, 0)
	var any_valid := Vector3.INF
	var hidden_valid := Vector3.INF
	var enemy_height: float = 2.0 * enemy.size
	var enemy_radius: float = 0.5 * enemy.size

	for i in 120:
		var p := Vector3(
			randf_range(-ARENA_HALF + 1.5, ARENA_HALF - 1.5), 0.0,
			randf_range(-ARENA_HALF + 1.5, ENEMY_Z_MAX))
		if Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() < PLAYER_CLEARANCE:
			continue
		if Vector2(p.x - last_enemy_pos.x, p.z - last_enemy_pos.z).length() < MIN_MOVE_DISTANCE:
			continue
		if _inside_obstacle(p, enemy_radius + 0.5):
			continue
		if any_valid == Vector3.INF:
			any_valid = p
		# "Hidden" = obstacles block the line from your eye to both its head and feet.
		if _blocked(space, eye, p + Vector3(0, 0.3, 0)) and _blocked(space, eye, p + Vector3(0, enemy_height - 0.2, 0)):
			hidden_valid = p
			break

	var chosen := hidden_valid if hidden_valid != Vector3.INF else any_valid
	if chosen == Vector3.INF:
		chosen = Vector3(0, 0, -15)   # should basically never happen
	last_enemy_pos = chosen
	return chosen


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)   # layer 1 = walls/obstacles
	return not space.intersect_ray(query).is_empty()


func _inside_obstacle(p: Vector3, margin: float) -> bool:
	for o in get_map_bodies():
		if not is_instance_valid(o):
			continue
		for part in o.get_meta("parts", []):
			var local: Vector3 = (o.global_transform * part.xf).affine_inverse() * p
			var half: Vector3 = part.size * 0.5
			if absf(local.x) < half.x + margin and absf(local.z) < half.z + margin:
				return true
	return false
