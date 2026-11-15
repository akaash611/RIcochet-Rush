extends Control
## Custom crosshair. Everything is tweakable in the Inspector
## (select CanvasLayer > Crosshair in room.tscn).
##   - turns GREEN and pulls in tight when your aim path ends on the enemy
##   - opens up a little while you're moving
##   - goes faint while the ball is out (you can't shoot)
##   - flashes a hit-marker X when you land a hit

enum Style { CROSS, CROSS_DOT, CIRCLE_DOT, T_SHAPE, DOT }

@export var style: Style = Style.CROSS_DOT
@export var color := Color(1, 1, 1, 0.95)
@export var lock_color := Color(0.25, 1.0, 0.45, 1.0)   # aim path hits the enemy
@export var empty_color := Color(1, 1, 1, 0.3)          # ball is out
@export var length: float = 9.0
@export var thickness: float = 2.0
@export var gap: float = 6.0
@export var dot_size: float = 2.0
@export var outline: bool = true
@export var outline_color := Color(0, 0, 0, 0.85)
@export var move_spread: float = 5.0

var player: Node

var _spread := 0.0
var _lock := 0.0
var _hit_flash := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func flash_hit() -> void:
	_hit_flash = 0.35


func _process(delta: float) -> void:
	_t += delta
	var moving: bool = player != null and absf(player.velocity.x) > 0.1
	_spread = lerpf(_spread, move_spread if moving else 0.0, 12.0 * delta)
	var locked: bool = player != null and player.has_bullet and player.aim_would_hit
	_lock = lerpf(_lock, 1.0 if locked else 0.0, 14.0 * delta)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).round()
	var has_ball: bool = player == null or player.has_bullet
	var col := color.lerp(lock_color, _lock) if has_ball else empty_color
	var g := gap + _spread - _lock * 2.0

	match style:
		Style.CROSS, Style.CROSS_DOT, Style.T_SHAPE:
			_bar(Rect2(c.x + g, c.y - thickness * 0.5, length, thickness), col)          # right
			_bar(Rect2(c.x - g - length, c.y - thickness * 0.5, length, thickness), col) # left
			_bar(Rect2(c.x - thickness * 0.5, c.y + g, thickness, length), col)          # down
			if style != Style.T_SHAPE:
				_bar(Rect2(c.x - thickness * 0.5, c.y - g - length, thickness, length), col)  # up
		Style.CIRCLE_DOT:
			var r := g + length * 0.5
			if outline:
				draw_arc(c, r, 0.0, TAU, 48, outline_color, thickness + 2.0, true)
			draw_arc(c, r, 0.0, TAU, 48, col, thickness, true)

	if style in [Style.CROSS_DOT, Style.CIRCLE_DOT, Style.DOT]:
		if outline:
			draw_circle(c, dot_size + 1.0, outline_color)
		draw_circle(c, dot_size, col)

	# Spinning lock-on brackets when the shot would land.
	if _lock > 0.05:
		var rr := g + length + 6.0
		var spin := _t * 3.0
		for i in 4:
			var a0 := spin + i * TAU / 4.0
			draw_arc(c, rr, a0, a0 + 0.6, 8, Color(lock_color, _lock), 2.0, true)

	# Hit marker.
	if _hit_flash > 0.0:
		var k := _hit_flash / 0.35
		var hc := Color(1, 1, 1, k)
		var d := 8.0 + (1.0 - k) * 6.0
		for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + dir * d, c + dir * (d + 8.0), hc, 2.5, true)


func _bar(r: Rect2, col: Color) -> void:
	if outline:
		draw_rect(r.grow(1.0), outline_color)
	draw_rect(r, col)
