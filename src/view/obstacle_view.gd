extends Node2D
## Препятствия одной части: камни и заросли (раздел 5.4).

const STRIDE: int = 4

var rock_color: Color = Color(0.16, 0.14, 0.13)
var rock_edge: Color = Color(0.45, 0.42, 0.40)
var bush_color: Color = Color(0.20, 0.33, 0.17)
var bush_edge: Color = Color(0.36, 0.50, 0.28)

## По четыре числа на препятствие: восток, север, радиус, вид.
var obstacles: PackedFloat32Array = PackedFloat32Array()


func _draw() -> void:
	var index: int = 0
	while index < obstacles.size():
		# Мир: y — север; экран Godot: y — вниз.
		var center: Vector2 = Vector2(obstacles[index], -obstacles[index + 1])
		var radius: float = obstacles[index + 2]
		if obstacles[index + 3] > 0.5:
			draw_circle(center, radius, bush_color)
			draw_arc(center, radius, 0.0, TAU, 24, bush_edge)
		else:
			draw_circle(center, radius, rock_color)
			draw_arc(center, radius, 0.0, TAU, 24, rock_edge)
		index += STRIDE
