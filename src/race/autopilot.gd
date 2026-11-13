extends RefCounted
## Автоматика: превращает заданную скорость или расход в положение газа.
## Дизайн-документ, разделы 3.3 и 9.6.
##
## Собственных формул движения у неё нет: всё, что нужно знать о машине,
## она спрашивает у модели (сопротивление, предел тяги, предел сцепления).
## Рельеф она не предвидит: подъём оплачивается топливом по факту.
##
## Она же отвечает, куда можно поставить точку (раздел 3.4): зона клика на
## экране и проверка команды в симуляции пользуются одними функциями.

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


## Руль от -1 до 1, чтобы повернуть нос на курс course (радианы) и держать его.
## Автоматика поворачивает плавно: использует не больше autopilot_lateral_share
## доступной боковой силы шин на этом покрытии, поэтому манёвр не стоит скорости.
func steer(sim: CarSim, state: CarState, terrain: TerrainSample, course: float) -> float:
	var mass: float = sim.total_mass(state.fuel)
	var forward: float = maxf(state.forward_speed(), 0.0)
	var limit: float = sim.max_lateral_accel(mass, terrain.surface, sim.params.autopilot_lateral_share)
	var error: float = wrapf(course - state.heading, -PI, PI)
	var accel: float = clampf(sim.params.autopilot_course_gain * error * forward, -limit, limit)
	return sim.steer_for_lateral_accel(accel, mass)


## Радиус поворота автоматики на текущей скорости, массе и покрытии, м.
func auto_turn_radius(sim: CarSim, state: CarState, terrain: TerrainSample) -> float:
	return sim.min_turn_radius(state.speed(), sim.total_mass(state.fuel), terrain.surface,
		sim.params.autopilot_lateral_share)


## Ближняя граница зоны вдоль луча под углом angle к носу машины (радианы),
## при радиусе поворота radius: длина хорды окружности поворота, м.
## Точки ближе этого лежат внутри окружности, и машина в них не попадёт.
func zone_inner_distance(radius: float, angle: float) -> float:
	return 2.0 * radius * sin(absf(wrapf(angle, -PI, PI)))


## Достижима ли точка (восток, север): лежит ли она вне двух окружностей
## минимального радиуса слева и справа от машины. scale меняет радиус.
func point_reachable(sim: CarSim, state: CarState, terrain: TerrainSample,
		east: float, north: float, scale: float = 1.0) -> bool:
	var d_east: float = east - state.x
	var d_north: float = north - state.y
	var distance: float = sqrt(d_east * d_east + d_north * d_north)
	var angle: float = atan2(d_east, d_north) - state.heading
	return distance >= zone_inner_distance(auto_turn_radius(sim, state, terrain) * scale, angle)


## Можно ли поставить точку (раздел 3.4). Если курс задан, зона ограничена ещё
## сектором вокруг курса и дальностью.
func point_allowed(sim: CarSim, state: CarState, terrain: TerrainSample,
		course_active: bool, course: float, east: float, north: float) -> bool:
	var params = sim.params
	if not point_reachable(sim, state, terrain, east, north, params.point_zone_margin):
		return false
	var d_east: float = east - state.x
	var d_north: float = north - state.y
	var distance: float = sqrt(d_east * d_east + d_north * d_north)
	if distance <= params.point_pass_radius:
		return false
	if not course_active:
		return true
	if distance > params.point_max_range:
		return false
	var off_course: float = absf(wrapf(atan2(d_east, d_north) - course, -PI, PI))
	return off_course <= deg_to_rad(params.point_sector_deg)


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
