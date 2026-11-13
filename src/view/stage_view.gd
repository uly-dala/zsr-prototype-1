extends Node2D
## Объекты этапа на местности: контрольные точки и ориентиры.

const LandmarkArt = preload("res://src/view/landmark_art.gd")

var checkpoint_color: Color = Color(1.0, 0.85, 0.3, 0.9)
var passed_color: Color = Color(0.6, 0.9, 0.6, 0.45)

var _layout = null
var _next_checkpoint: int = 0


## layout — StageLayout или null, если этапа нет.
func set_layout(layout) -> void:
	_layout = layout
	queue_redraw()


## Номер следующей контрольной точки игрока: пройденные рисуются бледнее.
func set_next_checkpoint(index: int) -> void:
	if index != _next_checkpoint:
		_next_checkpoint = index
		queue_redraw()


func _draw() -> void:
	if _layout == null:
		return
	for landmark in _layout.landmarks:
		# Мир: y — север; экран Godot: y — вниз.
		LandmarkArt.draw(self, landmark["kind"], Vector2(landmark["x"], -landmark["y"]), landmark["size"], landmark["angle"])
	var font: Font = ThemeDB.fallback_font
	var radius: float = _layout.checkpoint_radius
	for i in _layout.checkpoints.size():
		var center: Vector2 = Vector2(_layout.checkpoints[i].x, -_layout.checkpoints[i].y)
		var color: Color = checkpoint_color
		if i < _next_checkpoint:
			color = passed_color
		draw_arc(center, radius, 0.0, TAU, 64, color, 1.5)
		draw_arc(center, radius * 0.25, 0.0, TAU, 24, color, 1.0)
		# Номер точки высотой около 20 м.
		draw_set_transform(center + Vector2(radius * 0.4, -radius * 0.4), 0.0, Vector2(0.6, 0.6))
		draw_string(font, Vector2.ZERO, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
