extends RefCounted
## Блок «Качение и уклон»: коэффициент покрытия и уклон, умноженные на вес.

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")

var params: CarParams


func _init(p_params: CarParams) -> void:
	params = p_params


## Сила сопротивления качению, Н.
func resistance(mass: float, surface: SurfaceParams) -> float:
	return surface.rolling_coefficient * mass * params.gravity


## Ускорение от уклона вдоль одной оси, м/с². На подъёме отрицательное.
func slope_accel(grade: float) -> float:
	return -params.gravity * grade
