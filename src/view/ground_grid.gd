extends Node2D
## Сетка на пустой плоскости, чтобы было видно движение и масштаб.
## Мелкая клетка 10 м, средняя 100 м, крупная 1 км; оси через начало координат ярче.
## Шаг 5 заменит её настоящей местностью.

const MINOR_STEP: float = 10.0

## Видимая часть мира в координатах Godot; задаёт сцена заезда каждый кадр.
var visible_rect: Rect2 = Rect2()

var minor_color: Color = Color(1.0, 1.0, 1.0, 0.05)
var major_color: Color = Color(1.0, 1.0, 1.0, 0.13)
var km_color: Color = Color(1.0, 1.0, 1.0, 0.30)
var axis_color: Color = Color(1.0, 0.85, 0.45, 0.55)


func _draw() -> void:
	if visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
		return
	var left: float = visible_rect.position.x
	var top: float = visible_rect.position.y
	var right: float = visible_rect.end.x
	var bottom: float = visible_rect.end.y

	var index: int = int(floor(left / MINOR_STEP))
	var last: int = int(ceil(right / MINOR_STEP))
	while index <= last:
		var x: float = index * MINOR_STEP
		draw_line(Vector2(x, top), Vector2(x, bottom), _line_color(index))
		index += 1

	index = int(floor(top / MINOR_STEP))
	last = int(ceil(bottom / MINOR_STEP))
	while index <= last:
		var y: float = index * MINOR_STEP
		draw_line(Vector2(left, y), Vector2(right, y), _line_color(index))
		index += 1


func _line_color(index: int) -> Color:
	if index == 0:
		return axis_color
	if index % 100 == 0:
		return km_color
	if index % 10 == 0:
		return major_color
	return minor_color
