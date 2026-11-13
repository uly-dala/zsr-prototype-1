extends Node2D
## Изображение машины: вид сверху, нос вверх при курсе 0 (север).
## Положение и поворот задаёт сцена заезда. Размеры в метрах.

const LENGTH: float = 4.6
const WIDTH: float = 2.0

var body_color: Color = Color(0.95, 0.55, 0.15)
var nose_color: Color = Color(1.0, 0.95, 0.80)
var velocity_color: Color = Color(0.40, 0.90, 1.0, 0.9)

## Отладка: показывать вектор скорости.
var show_velocity: bool = false
## Вектор скорости в координатах Godot (x — восток, y — юг), м/с.
var velocity: Vector2 = Vector2.ZERO


func _draw() -> void:
	var half_l: float = LENGTH * 0.5
	var half_w: float = WIDTH * 0.5
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(-half_w, half_l),
		Vector2(-half_w, -half_l * 0.45),
		Vector2(0.0, -half_l),
		Vector2(half_w, -half_l * 0.45),
		Vector2(half_w, half_l),
	])
	draw_colored_polygon(body, body_color)
	var nose: PackedVector2Array = PackedVector2Array([
		Vector2(-half_w * 0.6, -half_l * 0.35),
		Vector2(0.0, -half_l * 0.9),
		Vector2(half_w * 0.6, -half_l * 0.35),
	])
	draw_colored_polygon(nose, nose_color)
	if show_velocity and velocity.length() > 0.5:
		# Вектор скорости: 1 м на экране за 1 м/с. Узел повёрнут, поэтому
		# вектор переводится в координаты узла.
		draw_line(Vector2.ZERO, velocity.rotated(-rotation), velocity_color)
