extends RefCounted
## Блок «Воздух»: сопротивление 0,6 · v².

const CarParams = preload("res://src/sim/car_params.gd")

var params: CarParams


func _init(p_params: CarParams) -> void:
	params = p_params


## Сила сопротивления воздуха, Н. Скорость в м/с.
func drag(speed: float) -> float:
	return params.drag_coefficient * speed * speed
