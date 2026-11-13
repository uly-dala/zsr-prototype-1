extends RefCounted
## Блок «Шины»: пределы продольного и бокового ускорения
## с учётом покрытия и массы (раздел 4.2).

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")

var params: CarParams


func _init(p_params: CarParams) -> void:
	params = p_params


## Множитель сцепления от массы: (1000 / масса)^0,45.
func mass_factor(mass: float) -> float:
	return pow(params.reference_mass / mass, params.grip_mass_exponent)


## Предел бокового ускорения на твёрдом грунте, м/с².
func lateral_limit_dry(mass: float) -> float:
	return params.lateral_accel * mass_factor(mass)


## Предел бокового ускорения на этом покрытии, м/с².
func lateral_limit(mass: float, surface: SurfaceParams) -> float:
	return lateral_limit_dry(mass) * surface.grip


## Предел разгона и торможения на этом покрытии, м/с².
func longitudinal_limit(mass: float, surface: SurfaceParams) -> float:
	return params.brake_decel * mass_factor(mass) * surface.grip
