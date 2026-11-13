extends Node2D
## След машины: истинный путь за последние минуты. Отладочный инструмент шага 1,
## позже из него вырастет показ пути в разборе после финиша.

const MAX_POINTS: int = 3000

var trail_color: Color = Color(1.0, 0.75, 0.35, 0.55)
var _points: PackedVector2Array = PackedVector2Array()


func clear() -> void:
	_points = PackedVector2Array()
	queue_redraw()


## point — в координатах Godot (x — восток, y — юг).
func add_point(point: Vector2) -> void:
	_points.append(point)
	if _points.size() > MAX_POINTS:
		_points = _points.slice(_points.size() - MAX_POINTS)
	queue_redraw()


func _draw() -> void:
	if _points.size() >= 2:
		draw_polyline(_points, trail_color)
