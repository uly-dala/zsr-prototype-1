extends RefCounted
## Источник команд «соперник» (раздел 8). ИИ управляет машиной теми же
## командами, что и игрок: курс, скорость, точка, ручной перехват.
## Он не получает ничего, чего нет у игрока, кроме знания своего положения
## с ошибкой: ведёт счисление, ошибка копится с пройденным путём и
## исправляется у контрольных точек и ориентиров. Цель ближе дальности
## обзора он видит и едет прямо на неё.
##
## Все случайные решения берутся из своего генератора с зерном от зерна
## мира и номера машины, поэтому заезд воспроизводим.

const AiParams = preload("res://src/input/ai_params.gd")
const Command = preload("res://src/sim/command.gd")

enum Kind { SPRINTER, MIDDLE, ECONOMY }
const KIND_NAMES: Array = ["Спринтер", "Середняк", "Экономный"]
## ИИ принимает решения раз в столько шагов: 10 раз в секунду.
const DECIDE_EVERY: int = 6
## Объезд не ближе стольких метров к стене трассы.
const WALL_CLEARANCE: float = 8.0
## Полоса перед машиной, в которой ищутся препятствия: половина ширины, м.
const CORRIDOR: float = 3.0

var car_id: int = 0
var kind: int = Kind.MIDDLE
var title: String = ""
## Крейсерская скорость этой машины, км/ч.
var cruise_speed: float = 100.0
var params: AiParams
## Сколько заправок планирует эта машина; -1 — без ограничения.
## По умолчанию берётся из параметров по типу.
var max_refuels: int = -1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Ошибка счисления: оценка положения = истинное положение + ошибка.
var _error: Vector2 = Vector2.ZERO
var _error_direction: float = 0.0
var _last_distance: float = 0.0
var _leg: int = -1
var _depot: int = -1
## Скорость с учётом экономии топлива, км/ч.
var _travel_speed: float = 100.0
var _start_fuel: float = -1.0
## Твёрдый грунт: расход на нём — основа расчёта топлива.
var _hard_surface = null
var _sent_course: float = -1000.0
var _sent_speed: float = -1.0
var _sent_steer: float = 0.0
var _sent_throttle: float = 0.0
var _avoiding: bool = false
var _point_tried: Vector3 = Vector3.ZERO
## Заход на вход трассы: машина уже в клине перед входом и едет вдоль оси.
var _entry_follow: bool = false
var _stuck_ticks: int = 0
var _reverse_ticks: int = 0
var _reverse_side: float = 1.0


func _init(p_car_id: int, p_kind: int, number: int, p_params: AiParams, world_seed: int) -> void:
	car_id = p_car_id
	kind = p_kind
	params = p_params
	title = "%s %d" % [KIND_NAMES[p_kind], number]
	_rng.seed = hash(Vector3i(world_seed, 9001, p_car_id))
	cruise_speed = _rng.randf_range(params.speed_min[p_kind], params.speed_max[p_kind])
	max_refuels = params.max_refuels[p_kind]
	_error_direction = _rng.randf() * TAU
	if _rng.randf() < 0.5:
		_reverse_side = -1.0


## Заправка на старте для этого типа, кг.
func start_fuel() -> float:
	return params.start_fuel[kind]


## Вызывается перед каждым шагом симуляции. sim — RaceSim, terrain — слой
## данных местности, landmarks — ориентиры StageLayout.
func decide(sim, terrain, landmarks: Array) -> void:
	if sim.step_index % DECIDE_EVERY != 0:
		return
	var car = sim.cars[car_id]
	var state = car.state
	var checkpoints: PackedVector2Array = sim.checkpoints
	if car.finish_step >= 0 or checkpoints.is_empty():
		_set_manual(sim, 0.0, 0.0)
		_set_speed(sim, 0.0)
		return
	if state.fuel <= 0.0:
		# Пустой бак: заезд для машины закончен.
		return
	var position: Vector2 = Vector2(state.x, state.y)
	var speed: float = state.speed()
	if _start_fuel < 0.0:
		_start_fuel = state.fuel
		_travel_speed = cruise_speed

	_update_error(state, position, landmarks)
	if car.next_checkpoint != _leg:
		# Контрольная точка взята: положение известно точно, план на отрезок.
		_leg = car.next_checkpoint
		_error = Vector2.ZERO
		_plan_leg(sim, car, position)

	# Цель: склад, если на этом отрезке нужна заправка, иначе контрольная точка.
	var world_state = sim.world_state
	if _depot >= 0:
		var seen_empty: bool = position.distance_to(world_state.depots[_depot]) < params.sight_radius \
				and world_state.stock[_depot] <= 0.0
		if car.depots_used.has(_depot) or seen_empty:
			_depot = -1
			_plan_speed(sim, car, position)
	if sim.step_index % 300 == 0:
		# Раз в 5 секунд ИИ пересчитывает, хватит ли топлива на этой скорости.
		_plan_speed(sim, car, position)
	var target: Vector2 = checkpoints[_leg]
	if _depot >= 0:
		target = world_state.depots[_depot]
	var true_distance: float = position.distance_to(target)
	var in_sight: bool = true_distance < params.sight_radius
	var aim: Vector2 = target - position
	if not in_sight:
		aim = target - (position + _error)
	# Вход на трассу: если машина сбоку от него, сначала выйти на ось.
	var lining_up: bool = false
	var entering: bool = false
	if _depot < 0 and _is_track_entry(sim):
		var believed: Vector2 = position
		if not in_sight:
			believed = position + _error
		var approach: Vector2 = _entry_approach(sim, believed)
		lining_up = not _entry_follow
		entering = true
		aim = approach - believed

	# Скорость: крейсерская или экономная; на подходе к цели — такая, чтобы
	# автоматика успела довернуть; малая для проезда склада.
	var wanted_speed: float = _travel_speed
	if in_sight:
		var off_course: float = absf(wrapf(atan2(aim.x, aim.y) - state.heading, -PI, PI))
		if off_course > 0.03:
			# Радиус дуги, которая приводит в цель с текущего курса.
			var radius: float = true_distance / (2.0 * maxf(sin(minf(off_course, PI * 0.5)), 0.05))
			var surface = terrain.sample(state.x, state.y).surface
			var grip: float = car.sim.max_lateral_accel(state.mass, surface, car.sim.params.autopilot_lateral_share)
			var turn_limit: float = sqrt(grip * radius * 0.6) * 3.6
			wanted_speed = minf(wanted_speed, maxf(turn_limit, params.approach_speed_min))
	if _depot < 0 and _on_track(sim, true_distance):
		wanted_speed = minf(wanted_speed, params.track_speed)
	if entering:
		wanted_speed = minf(wanted_speed, params.track_speed)
	if lining_up:
		wanted_speed = minf(wanted_speed, params.track_entry_speed)
	if _depot >= 0 and in_sight:
		var slow: float = params.depot_speed / 3.6
		var braking: float = maxf(0.0, speed * speed - slow * slow) / (2.0 * car.sim.params.autopilot_max_brake)
		if true_distance < braking + 40.0:
			wanted_speed = minf(wanted_speed, params.depot_speed)
	_set_speed(sim, wanted_speed)

	# Упёрся в препятствие: отъехать задним ходом с рулём в сторону.
	if _reverse_ticks > 0:
		_reverse_ticks -= 1
		if _reverse_ticks == 0:
			_set_manual(sim, 0.0, 0.0)
		return
	if car.blocked_left <= 0.0 and speed < 0.5 and sim.step_index > 180:
		_stuck_ticks += 1
	else:
		_stuck_ticks = 0
	if _stuck_ticks >= 10:
		_stuck_ticks = 0
		_reverse_ticks = 20
		_reverse_side = -_reverse_side
		_set_manual(sim, _reverse_side, -1.0)
		return

	if _avoid_obstacle(sim, terrain, car, state, speed):
		return
	_set_course(sim, rad_to_deg(atan2(aim.x, aim.y)))


## Едет ли машина по участку трассы с границами: цель — ворота, и это либо
## не первые ворота, либо до входа осталось меньше 150 м.
func _on_track(sim, distance_to_target: float) -> bool:
	if _leg >= sim.checkpoint_radii.size():
		return false
	if sim.checkpoint_radii[_leg] >= sim.checkpoint_radius:
		return false
	if _leg > 0 and sim.checkpoint_radii[_leg - 1] < sim.checkpoint_radius:
		return true
	return distance_to_target < 150.0


## Цель — первые ворота трассы: сами ворота узкие, место перед ними в списке
## широкое, место после них узкое.
func _is_track_entry(sim) -> bool:
	if _leg + 1 >= sim.checkpoint_radii.size():
		return false
	if sim.checkpoint_radii[_leg] >= sim.checkpoint_radius:
		return false
	if _leg > 0 and sim.checkpoint_radii[_leg - 1] < sim.checkpoint_radius:
		return false
	return sim.checkpoint_radii[_leg + 1] < sim.checkpoint_radius


## Куда ехать, чтобы попасть во вход трассы ровно, а не боком.
## - Машина перед входом и внутри сужающегося к нему клина: едет вдоль оси
##   трассы, целясь в место на оси на 80 м впереди себя.
## - Машина перед входом, но далеко от оси: едет на ось в 600 м до входа,
##   пока не окажется в клине.
## - Машина сбоку от стен или за входом: уезжает назад и в сторону от стен.
func _entry_approach(sim, believed: Vector2) -> Vector2:
	var gate: Vector2 = sim.checkpoints[_leg]
	var direction: Vector2 = (sim.checkpoints[_leg + 1] - gate).normalized()
	var side: Vector2 = direction.orthogonal()
	var offset: Vector2 = believed - gate
	var along: float = offset.dot(direction)
	var across: float = offset.dot(side)
	var half_width: float = sim.checkpoint_radii[_leg]
	var back: float = params.track_entry_distance
	if along > -60.0 and absf(across) > half_width:
		_entry_follow = false
	if not _entry_follow:
		if along > -150.0:
			if absf(across) < half_width and along <= 0.0:
				_entry_follow = true
		elif absf(across) < 0.5 * (-along - 150.0):
			_entry_follow = true
	if _entry_follow:
		if along > -80.0:
			return gate
		return gate + direction * (along + 80.0)
	if along > -150.0:
		return gate - direction * back + side * signf(across) * 200.0
	return gate - direction * back


# --- Счисление ----------------------------------------------------------------

## Ошибка растёт с пройденным путём и медленно меняет направление;
## рядом с ориентиром исправляется.
func _update_error(state, position: Vector2, landmarks: Array) -> void:
	var moved: float = state.distance - _last_distance
	_last_distance = state.distance
	_error_direction += _rng.randf_range(-0.4, 0.4) * moved / 100.0
	_error += Vector2(cos(_error_direction), sin(_error_direction)) * moved * params.drift_rate
	if _error.length() > params.error_cap:
		_error = _error.normalized() * params.error_cap
	for landmark in landmarks:
		if absf(landmark["x"] - position.x) < params.landmark_fix_radius \
				and absf(landmark["y"] - position.y) < params.landmark_fix_radius:
			_error = Vector2.ZERO
			return


# --- Топливо ------------------------------------------------------------------

## Во сколько раз настоящий расход больше расчётного для ровного грунта.
## Сначала это оценка из параметров, после первого километра — свой замер.
func _cost_factor(car) -> float:
	var state = car.state
	if state.distance < 1000.0:
		return params.terrain_factor
	var used: float = _start_fuel + car.fuel_taken - state.fuel
	var flat: float = _flat_cost(car, _travel_speed) * state.distance
	if flat <= 0.0:
		return params.terrain_factor
	return clampf(used / flat, 1.0, 3.0)


## Расход на метр пути по ровному твёрдому грунту на скорости speed_kmh, кг/м.
## Ответ даёт модель машины.
func _flat_cost(car, speed_kmh: float) -> float:
	if _hard_surface == null:
		return 0.0
	var speed: float = speed_kmh / 3.6
	return car.sim.consumption_for_speed(speed, car.state.mass, _hard_surface) / 60.0 / speed


## Сколько топлива нужно на distance метров на скорости speed_kmh, с запасом.
func _fuel_needed(car, distance: float, speed_kmh: float) -> float:
	return distance * _flat_cost(car, speed_kmh) * _cost_factor(car) * params.fuel_margin


## Путь от position через оставшиеся контрольные точки до финиша, м.
func _route_left(sim, position: Vector2) -> float:
	var total: float = 0.0
	var from: Vector2 = position
	for i in range(_leg, sim.checkpoints.size()):
		total += from.distance_to(sim.checkpoints[i])
		from = sim.checkpoints[i]
	return total


## Может ли машина ещё заправляться по своему плану.
func _may_refuel(car) -> bool:
	return max_refuels < 0 or car.refuels < max_refuels


## Путь до следующего места, где можно взять топливо, если пропустить склад
## этого отрезка: до склада следующего отрезка, а если его нет — до финиша.
func _reach_after_skip(sim, car, position: Vector2) -> float:
	if not _may_refuel(car):
		return _route_left(sim, position)
	var depots: PackedVector2Array = sim.world_state.depots
	var checkpoints: PackedVector2Array = sim.checkpoints
	var total: float = position.distance_to(checkpoints[_leg])
	var from: Vector2 = checkpoints[_leg]
	for next_leg in range(_leg + 1, checkpoints.size()):
		var depot: int = sim.depot_of_leg(next_leg)
		if depot >= 0:
			return total + from.distance_to(depots[depot])
		total += from.distance_to(checkpoints[next_leg])
		from = checkpoints[next_leg]
	return _route_left(sim, position)


## План на отрезок: заезжать ли на склад этого отрезка. ИИ заправляется как
## можно позже: едет на склад, только если без него не дотянуть до следующего.
## Так машины расходятся по складам, а не опустошают первые два.
func _plan_leg(sim, car, position: Vector2) -> void:
	_depot = -1
	_entry_follow = false
	_point_tried = Vector3.ZERO
	_hard_surface = sim.terrain.hard if "hard" in sim.terrain else sim.terrain.sample(position.x, position.y).surface
	var world_state = sim.world_state
	var fuel: float = car.state.fuel
	var space: float = car.sim.params.fuel_capacity - fuel
	var depot: int = sim.depot_of_leg(_leg)
	if _may_refuel(car) and depot >= 0 and not car.depots_used.has(depot):
		var to_finish: float = _fuel_needed(car, _route_left(sim, position), cruise_speed)
		var to_next_supply: float = _fuel_needed(car, _reach_after_skip(sim, car, position), cruise_speed)
		if fuel < to_finish and fuel < to_next_supply and space >= params.min_refuel_space:
			_depot = depot
	_plan_speed(sim, car, position)


## Скорость в пути: самая большая, на которой топлива хватает до следующей
## заправки, а если заправок больше не будет — до финиша.
func _plan_speed(sim, car, position: Vector2) -> void:
	_travel_speed = cruise_speed
	if _depot >= 0 or _hard_surface == null:
		return
	var left: float = _reach_after_skip(sim, car, position)
	var factor: float = _cost_factor(car) * params.fuel_margin
	var speed: float = cruise_speed
	while speed > params.saving_speed_min and car.state.fuel < left * _flat_cost(car, speed) * factor:
		speed -= 10.0
	_travel_speed = maxf(speed, params.saving_speed_min)


# --- Препятствия --------------------------------------------------------------

## Объезд препятствия впереди. Возвращает true, если ИИ сейчас рулит сам
## и курс менять не нужно.
func _avoid_obstacle(sim, terrain, car, state, speed: float) -> bool:
	var look: float = maxf(40.0, speed * params.early_time)
	var obstacle: Vector3 = terrain.obstacle_ahead(state.x, state.y, state.heading, look, CORRIDOR)
	if obstacle.z <= 0.0:
		if _avoiding:
			_avoiding = false
			_set_manual(sim, 0.0, 0.0)
		return false
	var nose: Vector2 = Vector2(sin(state.heading), cos(state.heading))
	var right: Vector2 = Vector2(nose.y, -nose.x)
	var offset: Vector2 = Vector2(obstacle.x - state.x, obstacle.y - state.y)
	var gap: float = offset.dot(nose) - obstacle.z
	var lateral: float = offset.dot(right)
	# Как ИИ заметил это препятствие, решается один раз: по его координатам.
	var roll: float = float(hash(Vector3(obstacle.x, obstacle.y, car_id)) % 1000) / 1000.0
	var react_time: float = params.late_time
	if roll > 1.0 - params.miss_probability:
		react_time = params.miss_time
	var noticed_early: bool = roll < params.notice_probability

	if gap > maxf(8.0, speed * react_time):
		# Далеко: если заметил заранее, объехать точкой сбоку от препятствия.
		if noticed_early and not car.point_active and not _avoiding and obstacle != _point_tried:
			_point_tried = obstacle
			var side: float = _pass_side(sim, obstacle, right, lateral)
			var beside: Vector2 = Vector2(obstacle.x, obstacle.y) + right * side * (obstacle.z + params.clearance)
			sim.submit(Command.new(Command.Type.SET_POINT, car_id, beside.x, beside.y, true))
		return car.point_active
	# Близко: перехват руля в сторону от препятствия.
	var steer: float = _pass_side(sim, obstacle, right, lateral)
	_avoiding = true
	_set_manual(sim, steer, 0.0)
	return true


## С какой стороны объезжать: 1 — справа, -1 — слева. Обычно с той, что
## ближе; но если там вплотную стена трассы — с другой.
func _pass_side(sim, obstacle: Vector3, right: Vector2, lateral: float) -> float:
	var side: float = 1.0
	if lateral >= 0.0:
		side = -1.0
	var beside: Vector2 = Vector2(obstacle.x, obstacle.y) + right * side * (obstacle.z + params.clearance)
	var index: int = 0
	while index + 1 < sim.walls.size():
		var from: Vector2 = sim.walls[index]
		var axis: Vector2 = sim.walls[index + 1] - from
		var along: float = clampf((beside - from).dot(axis) / axis.length_squared(), 0.0, 1.0)
		if beside.distance_to(from + axis * along) < WALL_CLEARANCE:
			return -side
		index += 2
	return side


# --- Команды: отправляются только при изменении --------------------------------

func _set_speed(sim, speed_kmh: float) -> void:
	var rounded: float = round(speed_kmh / 5.0) * 5.0
	if rounded != _sent_speed:
		_sent_speed = rounded
		sim.submit(Command.new(Command.Type.SET_TARGET, car_id, Command.TargetMode.SPEED, rounded))


func _set_course(sim, degrees: float) -> void:
	var rounded: float = fposmod(round(degrees), 360.0)
	if absf(wrapf(rounded - _sent_course, -180.0, 180.0)) >= 2.0 or _sent_course < -500.0:
		_sent_course = rounded
		sim.submit(Command.new(Command.Type.SET_COURSE, car_id, rounded, 0.0, true))


func _set_manual(sim, steer: float, throttle: float) -> void:
	if steer != _sent_steer or throttle != _sent_throttle:
		_sent_steer = steer
		_sent_throttle = throttle
		sim.submit(Command.new(Command.Type.MANUAL, car_id, steer, throttle))
