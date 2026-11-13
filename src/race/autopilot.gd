extends RefCounted
## Автоматика: превращает заданную скорость или расход в положение газа.
## Дизайн-документ, разделы 3.3 и 9.6.
##
## Собственных формул движения у неё нет: всё, что нужно знать о машине,
## она спрашивает у модели (сопротивление, предел тяги, предел сцепления).
## Рельеф она не предвидит: подъём оплачивается топливом по факту.
##
## Курс и точка появятся здесь на шагах 3 и 4.

const CarSim = preload("res://src/sim/car_sim.gd")
const CarState = preload("res://src/sim/car_state.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")
const Command = preload("res://src/sim/command.gd")


## Газ и тормоз от -1 до 1 для режима mode (Command.TargetMode) и значения value:
## скорость в км/ч или расход в кг/мин.
func throttle(sim: CarSim, state: CarState, terrain: TerrainSample, mode: int, value: float) -> float:
	var forward: float = state.forward_speed()
	if mode == Command.TargetMode.CONSUMPTION:
		return _hold_consumption(sim, forward, value)
	return _hold_speed(sim, state, terrain, forward, value)


## Держать расход: двигатель отдаёт постоянную мощность, скорость меняется сама.
## Автоматика в этом режиме не тормозит.
func _hold_consumption(sim: CarSim, forward: float, rate_kg_min: float) -> float:
	var power: float = rate_kg_min / 60.0 / sim.params.fuel_per_joule
	if power <= 0.0:
		return 0.0
	var thrust: float = power / maxf(forward, 0.5)
	return clampf(thrust / sim.engine.max_thrust_at(forward), 0.0, 1.0)


## Держать скорость: тяга равна сопротивлению плюс добавка на разгон или торможение.
func _hold_speed(sim: CarSim, state: CarState, terrain: TerrainSample, forward: float, speed_kmh: float) -> float:
	var params = sim.params
	var mass: float = sim.total_mass(state.fuel)
	var long_limit: float = sim.tires.longitudinal_limit(mass, terrain.surface)
	var target: float = speed_kmh / 3.6
	if target <= 0.0:
		# Задан ноль: остановиться и стоять на тормозе.
		if forward <= 0.05 or long_limit <= 0.0:
			return -1.0
		return -clampf(params.autopilot_max_brake / long_limit, 0.0, 1.0)
	var grade: float = terrain.grade_east * sin(state.heading) + terrain.grade_north * cos(state.heading)
	var accel: float = clampf(params.autopilot_speed_gain * (target - forward),
		-params.autopilot_max_brake, params.autopilot_max_accel)
	var force: float = sim.resistance_force(maxf(forward, 0.0), mass, terrain.surface, grade) + mass * accel
	if force >= 0.0:
		return clampf(force / sim.engine.max_thrust_at(forward), 0.0, 1.0)
	if long_limit <= 0.0:
		return -1.0
	return -clampf(-force / (mass * long_limit), 0.0, 1.0)
