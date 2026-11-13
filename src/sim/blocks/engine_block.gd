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


## Топливо на работу двигателя, кг.
func fuel_for_work(work_joules: float) -> float:
	return work_joules * params.fuel_per_joule
