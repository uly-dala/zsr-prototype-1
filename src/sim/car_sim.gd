extends RefCounted
## Модель машины: точка с массой, направлением носа и вектором скорости.
## Дизайн-документ, разделы 4 и 9.6.
##
## Граница модели:
##   вход  — CarInput (руль, газ и тормоз) и TerrainSample (местность под машиной);
##   выход — CarState.
## Автоматика и ИИ не считают движение сами, а задают модели вопросы
## (функции в конце файла).
##
## Как устроен шаг:
##   1. Руль догоняет заданное положение с ограниченной скоростью.
##   2. Руль поворачивает нос. Полный руль — это поворот на пределе сцепления
##      твёрдого грунта при текущей массе; от покрытия поворот носа не зависит.
##   3. Двигатель толкает вдоль носа, уклон тянет вниз по склону.
##   4. Шины гасят боковое скольжение, но не сильнее предела покрытия.
##      На твёрдом грунте скорость успевает за носом. На скользком нос
##      повернулся, а машина продолжает ехать прежним путём: это и есть снос.
##   5. Воздух, качение, тормоз и цена манёвра уменьшают скорость.

const CarParams = preload("res://src/sim/car_params.gd")
const CarState = preload("res://src/sim/car_state.gd")
const CarInput = preload("res://src/sim/car_input.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")
const EngineBlock = preload("res://src/sim/blocks/engine_block.gd")
const TireBlock = preload("res://src/sim/blocks/tire_block.gd")
const AeroBlock = preload("res://src/sim/blocks/aero_block.gd")
const RollingBlock = preload("res://src/sim/blocks/rolling_block.gd")

var params: CarParams
var engine: EngineBlock
var tires: TireBlock
var aero: AeroBlock
var rolling: RollingBlock

## Отладка: при false топливо не расходуется и масса не меняется.
var burn_fuel: bool = true


func _init(p_params: CarParams) -> void:
	params = p_params
	engine = EngineBlock.new(p_params)
	tires = TireBlock.new(p_params)
	aero = AeroBlock.new(p_params)
	rolling = RollingBlock.new(p_params)


## Блок «Масса»: машина и топливо, кг.
func total_mass(fuel: float) -> float:
	return params.dry_mass + fuel


## Один шаг симуляции длиной dt секунд.
func step(state: CarState, input: CarInput, terrain: TerrainSample, dt: float) -> void:
	var surface: SurfaceParams = terrain.surface
	var mass: float = total_mass(state.fuel)
	var lat_dry: float = tires.lateral_limit_dry(mass)
	var lat_limit: float = tires.lateral_limit(mass, surface)
	var long_limit: float = tires.longitudinal_limit(mass, surface)
	var throttle: float = clampf(input.throttle, -1.0, 1.0)

	# 1. Привод руля.
	var steer_step: float = params.steer_rate * dt
	var steer_error: float = clampf(input.steer, -1.0, 1.0) - state.steer
	state.steer += clampf(steer_error, -steer_step, steer_step)

	# 2. Поворот носа.
	var nose_e: float = sin(state.heading)
	var nose_n: float = cos(state.heading)
	var forward: float = state.vel_east * nose_e + state.vel_north * nose_n
	var forward_abs: float = absf(forward)
	var yaw_rate: float = 0.0
	if forward_abs > 0.01:
		var yaw_max: float = forward_abs / params.min_geometric_radius
		yaw_rate = clampf(state.steer * lat_dry / forward_abs, -yaw_max, yaw_max)
		if forward < 0.0:
			yaw_rate = -yaw_rate
	state.heading = fposmod(state.heading + yaw_rate * dt, TAU)
	nose_e = sin(state.heading)
	nose_n = cos(state.heading)
	var right_e: float = nose_n
	var right_n: float = -nose_e

	# 3. Двигатель и уклон.
	var thrust: float = engine.thrust(throttle, forward, state.fuel)
	thrust = minf(thrust, mass * long_limit)
	var thrust_accel: float = thrust / mass
	state.vel_east += (nose_e * thrust_accel + rolling.slope_accel(terrain.grade_east)) * dt
	state.vel_north += (nose_n * thrust_accel + rolling.slope_accel(terrain.grade_north)) * dt

	# 4. Шины гасят боковое скольжение.
	var lateral_speed: float = state.vel_east * right_e + state.vel_north * right_n
	var lateral_accel: float = clampf(-lateral_speed / dt, -lat_limit, lat_limit)
	state.vel_east += right_e * lateral_accel * dt
	state.vel_north += right_n * lateral_accel * dt
	var lateral_ratio: float = 0.0
	if lat_limit > 0.0:
		lateral_ratio = absf(lateral_accel) / lat_limit

	# 5. Потери: воздух, качение, тормоз, цена манёвра.
	var speed: float = state.speed()
	var scrub: float = 0.0
	if speed > 0.0:
		var share: float = params.autopilot_lateral_share
		var excess: float = maxf(0.0, (lateral_ratio - share) / maxf(1.0 - share, 0.001))
		scrub = params.manual_scrub_decel * surface.grip * excess
		var decel: float = (aero.drag(speed) + rolling.resistance(mass, surface)) / mass + scrub
		if throttle < 0.0:
			decel += -throttle * long_limit
		var new_speed: float = maxf(0.0, speed - decel * dt)
		var keep: float = new_speed / speed
		state.vel_east *= keep
		state.vel_north *= keep
		speed = new_speed

	# 6. Положение и одометр.
	state.x += state.vel_east * dt
	state.y += state.vel_north * dt
	state.distance += speed * dt

	# 7. Топливо: расход пропорционален работе двигателя.
	var power: float = thrust * maxf(forward, 0.0)
	if burn_fuel:
		state.fuel = maxf(0.0, state.fuel - engine.fuel_for_work(power * dt))

	# Величины шага для экрана и записи.
	state.mass = total_mass(state.fuel)
	state.yaw_rate = yaw_rate
	state.thrust = thrust
	state.engine_power = power
	state.consumption = engine.fuel_for_work(power) * 60.0
	state.lateral_accel = lateral_accel
	state.lateral_ratio = lateral_ratio
	state.scrub_decel = scrub


# ---------------------------------------------------------------------------
# Запросы к модели (раздел 9.6, правило 2). Сейчас модель отвечает формулой.
# ---------------------------------------------------------------------------

## Наибольшее боковое ускорение, м/с². share — доля доступной боковой силы:
## 1 для ручного управления, autopilot_lateral_share для автоматики.
func max_lateral_accel(mass: float, surface: SurfaceParams, share: float = 1.0) -> float:
	return tires.lateral_limit(mass, surface) * share


## Минимальный радиус поворота на этой скорости и покрытии, м.
func min_turn_radius(speed: float, mass: float, surface: SurfaceParams, share: float = 1.0) -> float:
	var accel: float = max_lateral_accel(mass, surface, share)
	if accel <= 0.0:
		return INF
	return maxf(speed * speed / accel, params.min_geometric_radius)


## Тормозной путь с этой скорости, м. Считается только по шинам:
## воздух и качение его немного сокращают, поэтому ответ с запасом.
func braking_distance(speed: float, mass: float, surface: SurfaceParams) -> float:
	var decel: float = tires.longitudinal_limit(mass, surface)
	if decel <= 0.0:
		return INF
	return speed * speed / (2.0 * decel)


## Сила сопротивления на этой скорости, уклоне и покрытии, Н.
## grade — уклон вдоль пути: 0,1 означает подъём 10 %.
func resistance_force(speed: float, mass: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	return aero.drag(speed) + rolling.resistance(mass, surface) + mass * params.gravity * grade


## Тяга, нужная для этой скорости на этом уклоне и покрытии, Н.
func thrust_for_speed(speed: float, mass: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	return maxf(0.0, resistance_force(speed, mass, surface, grade))


## Мощность, нужная для этой скорости, Вт.
func power_for_speed(speed: float, mass: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	return thrust_for_speed(speed, mass, surface, grade) * speed


## Расход на этой скорости, кг/мин.
func consumption_for_speed(speed: float, mass: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	return engine.fuel_for_work(power_for_speed(speed, mass, surface, grade)) * 60.0


## Скорость, достижимая при этом расходе (кг/мин) на этом уклоне и покрытии, м/с.
func speed_for_consumption(rate_kg_min: float, mass: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	var power: float = rate_kg_min / 60.0 / params.fuel_per_joule
	if power <= 0.0:
		return 0.0
	var low: float = 0.0
	var high: float = 150.0
	for i in 40:
		var middle: float = (low + high) * 0.5
		if resistance_force(middle, mass, surface, grade) * middle > power:
			high = middle
		else:
			low = middle
	return low


## Запас хода, м: сколько машина проедет на этом топливе с этой скоростью
## по такому же покрытию и уклону. Учитывает, что машина легчает.
func range_at_speed(speed: float, fuel: float, surface: SurfaceParams, grade: float = 0.0) -> float:
	if fuel <= 0.0 or speed <= 0.0:
		return 0.0
	var per_kg: float = (surface.rolling_coefficient + grade) * params.gravity
	var empty_force: float = aero.drag(speed) + per_kg * params.dry_mass
	if empty_force + per_kg * fuel <= 0.0:
		return INF
	if absf(per_kg) < 0.000001:
		return fuel / (params.fuel_per_joule * empty_force)
	if empty_force <= 0.0:
		return INF
	return log(1.0 + per_kg * fuel / empty_force) / (per_kg * params.fuel_per_joule)


## Положение руля, которое даёт такое боковое ускорение (м/с², плюс — вправо)
## на твёрдом грунте при этой массе.
func steer_for_lateral_accel(accel: float, mass: float) -> float:
	return clampf(accel / tires.lateral_limit_dry(mass), -1.0, 1.0)
