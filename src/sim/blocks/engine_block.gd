extends RefCounted
## Блок «Двигатель»: тяга по газу, предел по мощности и силе,
## расход пропорционален работе.

const CarParams = preload("res://src/sim/car_params.gd")

var params: CarParams


func _init(p_params: CarParams) -> void:
	params = p_params


## Наибольшая тяга на этой скорости вдоль носа, Н.
func max_thrust_at(forward_speed: float) -> float:
	return minf(params.max_thrust, params.max_power / maxf(forward_speed, 0.5))


## Тяга при данном положении газа, Н. Без топлива тяги нет.
func thrust(throttle: float, forward_speed: float, fuel: float) -> float:
	if throttle <= 0.0 or fuel <= 0.0:
		return 0.0
	return throttle * max_thrust_at(forward_speed)


## Тяга заднего хода, Н (отрицательная). throttle от -1 до 0.
## Задний ход ограничен по скорости и по доле тяги.
func reverse_thrust(throttle: float, forward_speed: float, fuel: float) -> float:
	if throttle >= 0.0 or fuel <= 0.0 or forward_speed <= -params.reverse_max_speed:
		return 0.0
	return throttle * params.max_thrust * params.reverse_thrust_share


## Топливо на работу двигателя, кг.
func fuel_for_work(work_joules: float) -> float:
	return work_joules * params.fuel_per_joule
