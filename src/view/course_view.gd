extends Node2D
## Тонкая линия заданного курса от машины по земле (раздел 7.3).

const LENGTH: float = 3000.0

var line_color: Color = Color(0.55, 0.95, 1.0, 0.55)
var _active: bool = false
var _origin: Vector2 = Vector2.ZERO
var _course: float = 0.0


## origin — положение машины в координатах Godot (x — восток, y — юг);
## course — курс в радианах: 0 — север, по часовой стрелке.
func set_course(active: bool, origin: Vector2, course: float) -> void:
	if not active and not _active:
		return
	_active = active
	_origin = origin
	_course = course
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var direction: Vector2 = Vector2(sin(_course), -cos(_course))
	draw_line(_origin, _origin + direction * LENGTH, line_color)
