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


## Участок трассы: две стены и ворота поперёк.
func _draw_track() -> void:
	if not _layout.has_track:
		return
	var wall_color: Color = Color(0.95, 0.95, 0.9)
	var index: int = 0
	while index + 1 < _layout.walls.size():
		var from: Vector2 = Vector2(_layout.walls[index].x, -_layout.walls[index].y)
		var to: Vector2 = Vector2(_layout.walls[index + 1].x, -_layout.walls[index + 1].y)
		draw_line(from, to, wall_color, 2.0)
		# Красно-белые метки через 50 м: по ним видна скорость.
		var count: int = int(from.distance_to(to) / 50.0)
		for mark in count + 1:
			draw_circle(from.lerp(to, float(mark) / maxi(count, 1)), 1.6, Color(0.9, 0.25, 0.2))
		index += 2
	var across: Vector2 = (_layout.track_end - _layout.track_start).normalized().orthogonal() * _layout.track_half_width
	var gate: int = 0
	for place in _layout.waypoints.size():
		if _layout.waypoint_checkpoint[place] >= 0:
			continue
		var color: Color = checkpoint_color
		if place < _next_checkpoint:
			color = passed_color
		var spot: Vector2 = _layout.gates[gate]
		var left: Vector2 = Vector2(spot.x + across.x, -(spot.y + across.y))
		var right: Vector2 = Vector2(spot.x - across.x, -(spot.y - across.y))
		draw_line(left, right, color, 1.5)
		draw_circle(left, 2.5, color)
		draw_circle(right, 2.5, color)
		gate += 1


## Номер следующего места в списке игрока (контрольные точки и ворота трассы
## вместе): пройденные рисуются бледнее.
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
	# Склады топлива: круг, в котором идёт заправка, и бочки.
	var depot_color: Color = Color(0.35, 0.75, 1.0)
	for depot in _layout.depots:
		var spot: Vector2 = Vector2(depot.x, -depot.y)
		draw_arc(spot, _layout.depot_radius, 0.0, TAU, 48, depot_color, 1.0)
		draw_circle(spot + Vector2(-3.0, -2.0), 2.5, depot_color)
		draw_circle(spot + Vector2(3.0, -2.0), 2.5, depot_color)
		draw_circle(spot + Vector2(0.0, 3.0), 2.5, depot_color)
	var font: Font = ThemeDB.fallback_font
	var radius: float = _layout.checkpoint_radius
	_draw_track()
	for place in _layout.waypoints.size():
		var i: int = _layout.waypoint_checkpoint[place]
		if i < 0:
			continue
		var center: Vector2 = Vector2(_layout.checkpoints[i].x, -_layout.checkpoints[i].y)
		var color: Color = checkpoint_color
		if place < _next_checkpoint:
			color = passed_color
		draw_arc(center, radius, 0.0, TAU, 64, color, 1.5)
		draw_arc(center, radius * 0.25, 0.0, TAU, 24, color, 1.0)
		# Номер точки высотой около 20 м.
		draw_set_transform(center + Vector2(radius * 0.4, -radius * 0.4), 0.0, Vector2(0.6, 0.6))
		draw_string(font, Vector2.ZERO, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
