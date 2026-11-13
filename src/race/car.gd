extends RefCounted
## Машина в заезде: модель, состояние, автоматика и последние принятые команды.
## Не знает, кто отдаёт команды.
##
## Приоритеты (раздел 3.2), отдельно для газа и для руля:
##   газ  — W или S: игрок; иначе автоматика держит скорость или расход;
##   руль — A или D: игрок; иначе точка; иначе основное направление;
##          иначе руль стоит прямо.
## После отпускания клавиш автоматика возвращает управление через
## manual_release_delay. Точка и курс при перехвате не сбрасываются.

const CarParams = preload("res://src/sim/car_params.gd")
const CarSim = preload("res://src/sim/car_sim.gd")
const CarState = preload("res://src/sim/car_state.gd")
const CarInput = preload("res://src/sim/car_input.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")
const Command = preload("res://src/sim/command.gd")
const Autopilot = preload("res://src/race/autopilot.gd")

var id: int = 0
var sim: CarSim
var state: CarState = CarState.new()
var autopilot: Autopilot = Autopilot.new()
## Последняя команда ручного управления.
var manual: CarInput = CarInput.new()
## Режим удержания: Command.TargetMode.
var target_mode: int = Command.TargetMode.SPEED
## Заданное значение: км/ч в режиме скорости, кг/мин в режиме расхода.
var target_value: float = 0.0
## Газом на последнем шаге управляла автоматика.
var auto_throttle: bool = true
## Основное направление задано.
var course_active: bool = false
## Основное направление, градусы от 0 до 360: 0 — север, по часовой стрелке.
var course_deg: float = 0.0
## Рулём на последнем шаге управляла автоматика.
var auto_steer: bool = false
## Точка поставлена.
var point_active: bool = false
## Координаты точки: восток и север, м.
var point_x: float = 0.0
var point_y: float = 0.0
## Счётчики событий точки: экран и запись сравнивают их с прошлым значением.
## Пройдено точек.
var points_passed: int = 0
## Снято точек, ставших недостижимыми.
var points_dropped: int = 0
## Отклонено команд: точка вне допустимой зоны.
var points_rejected: int = 0
## Номер следующей контрольной точки, с нуля. Равен числу точек после финиша.
var next_checkpoint: int = 0
## Шаги симуляции, на которых пройдены контрольные точки.
var checkpoint_steps: PackedInt32Array = PackedInt32Array()
## Шаг финиша или -1.
var finish_step: int = -1
## Ударов о препятствия.
var hits: int = 0
## Сколько ещё секунд управление заблокировано после удара.
var blocked_left: float = 0.0

var _input: CarInput = CarInput.new()
var _throttle_wait: float = 0.0
var _steer_wait: float = 0.0
var _last_terrain: TerrainSample = TerrainSample.new()
var _has_terrain: bool = false


func _init(p_id: int, p_params: CarParams) -> void:
	id = p_id
	sim = CarSim.new(p_params)
	state.mass = sim.total_mass(state.fuel)


func apply_command(command: Command) -> void:
	if command.type == Command.Type.MANUAL:
		manual.steer = clampf(command.a, -1.0, 1.0)
		manual.throttle = clampf(command.b, -1.0, 1.0)
	elif command.type == Command.Type.SET_TARGET:
		if int(command.a) == Command.TargetMode.CONSUMPTION:
			target_mode = Command.TargetMode.CONSUMPTION
		else:
			target_mode = Command.TargetMode.SPEED
		target_value = clampf(command.b, 0.0, max_target(target_mode))
	elif command.type == Command.Type.SET_COURSE:
		course_active = command.active
		if course_active:
			course_deg = fposmod(command.a, 360.0)
	elif command.type == Command.Type.SET_POINT:
		_apply_point(command)


## Новая точка заменяет прежнюю. Точка вне допустимой зоны не ставится,
## прежняя при этом остаётся.
func _apply_point(command: Command) -> void:
	if not command.active:
		point_active = false
		return
	if _has_terrain and not autopilot.point_allowed(
			sim, state, _last_terrain, course_active, deg_to_rad(course_deg), command.a, command.b):
		points_rejected += 1
		return
	point_active = true
	point_x = command.a
	point_y = command.b


## Наибольшее заданное значение для режима.
func max_target(mode: int) -> float:
	if mode == Command.TargetMode.CONSUMPTION:
		return sim.params.target_consumption_max
	return sim.params.target_speed_max


## Шаг изменения заданного значения для режима.
func target_step(mode: int) -> float:
	if mode == Command.TargetMode.CONSUMPTION:
		return sim.params.target_consumption_step
	return sim.params.target_speed_step


## Нажата хотя бы одна клавиша ручного управления.
func is_manual_active() -> bool:
	return not manual.is_zero()


## Расстояние до точки, м.
func point_distance() -> float:
	var east: float = point_x - state.x
	var north: float = point_y - state.y
	return sqrt(east * east + north * north)


func step(terrain: TerrainSample, dt: float) -> void:
	_last_terrain.copy_from(terrain)
	_has_terrain = true
	if point_active:
		_check_point(terrain)

	if blocked_left > 0.0:
		# После удара управление заблокировано: ни игрок, ни автоматика
		# не рулят и не газуют (раздел 5.4).
		blocked_left -= dt
		auto_throttle = false
		auto_steer = false
		_input.steer = 0.0
		_input.throttle = 0.0
		_input.brake = 0.0
		sim.step(state, _input, terrain, dt)
		return

	var throttle: float = 0.0
	auto_throttle = false
	if manual.throttle != 0.0:
		throttle = manual.throttle
		_throttle_wait = sim.params.manual_release_delay
	elif _throttle_wait > 0.0:
		_throttle_wait -= dt
	else:
		throttle = autopilot.throttle(sim, state, terrain, target_mode, target_value)
		auto_throttle = true

	var steer: float = 0.0
	auto_steer = false
	if manual.steer != 0.0:
		steer = manual.steer
		_steer_wait = sim.params.manual_release_delay
	elif _steer_wait > 0.0:
		_steer_wait -= dt
	elif point_active:
		var bearing: float = atan2(point_x - state.x, point_y - state.y)
		steer = autopilot.steer(sim, state, terrain, bearing)
		auto_steer = true
	elif course_active:
		steer = autopilot.steer(sim, state, terrain, deg_to_rad(course_deg))
		auto_steer = true

	_input.steer = steer
	_set_drive(throttle, auto_throttle)
	sim.step(state, _input, terrain, dt)


## Перевести газ и тормоз от -1 до 1 во вход модели.
## Автоматика: плюс — газ, минус — тормоз; назад она не ездит.
## Игрок: W и S — газ и тормоз по ходу движения, а с места S включает задний
## ход. При движении назад наоборот: W тормозит, S газует.
func _set_drive(value: float, from_autopilot: bool) -> void:
	_input.throttle = 0.0
	_input.brake = 0.0
	if value == 0.0:
		return
	var forward: float = state.forward_speed()
	if from_autopilot:
		if value > 0.0:
			if forward < -0.5:
				_input.brake = 1.0
			else:
				_input.throttle = value
		else:
			_input.brake = -value
	elif value > 0.0:
		if forward < -0.5:
			_input.brake = value
		else:
			_input.throttle = value
	elif forward > 0.5:
		_input.brake = -value
	else:
		_input.throttle = value


## Едет ли машина задним ходом.
func is_reversing() -> bool:
	return state.forward_speed() < -0.5


## Препятствие сплошное: машина не может оказаться ближе radius к его центру
## (east, north). Скорость внутрь препятствия гасится, машина выталкивается
## на границу. Если она входила быстрее collision_hit_speed — это удар:
## остаётся collision_speed_keep скорости, управление блокируется (раздел 5.4).
## Упёршись носом, машина стоит, пока игрок не отъедет задним ходом.
func collide(east: float, north: float, radius: float) -> void:
	var d_east: float = state.x - east
	var d_north: float = state.y - north
	var distance: float = sqrt(d_east * d_east + d_north * d_north)
	if distance >= radius:
		return
	var out_east: float = -sin(state.heading)
	var out_north: float = -cos(state.heading)
	if distance > 0.001:
		out_east = d_east / distance
		out_north = d_north / distance
	var closing: float = -(state.vel_east * out_east + state.vel_north * out_north)
	if closing > 0.0:
		state.vel_east += out_east * closing
		state.vel_north += out_north * closing
	var drift_closing: float = -(state.drift_east * out_east + state.drift_north * out_north)
	if drift_closing > 0.0:
		state.drift_east += out_east * drift_closing
		state.drift_north += out_north * drift_closing
	if closing + maxf(drift_closing, 0.0) > sim.params.collision_hit_speed:
		hits += 1
		blocked_left = sim.params.collision_block_time
		state.vel_east *= sim.params.collision_speed_keep
		state.vel_north *= sim.params.collision_speed_keep
	state.x = east + out_east * radius
	state.y = north + out_north * radius


## Точка пройдена в радиусе point_pass_radius. Вплотную к точке проверяется
## только, не осталась ли она позади; дальше — достижима ли она ещё.
func _check_point(terrain: TerrainSample) -> void:
	var params: CarParams = sim.params
	var east: float = point_x - state.x
	var north: float = point_y - state.y
	var distance: float = sqrt(east * east + north * north)
	if distance <= params.point_pass_radius:
		point_active = false
		points_passed += 1
		return
	if distance < params.point_near_distance:
		var ahead: float = east * sin(state.heading) + north * cos(state.heading)
		if ahead <= 0.0:
			point_active = false
			points_dropped += 1
		return
	if not autopilot.point_reachable(sim, state, terrain, point_x, point_y, params.point_drop_slack):
		point_active = false
		points_dropped += 1
