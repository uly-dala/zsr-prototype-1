extends RefCounted
## Машина в заезде: модель, состояние, автоматика и последние принятые команды.
## Не знает, кто отдаёт команды.
##
## Газ и руль разделены:
##   газ  — W или S нажаты: игрок; иначе автоматика держит скорость или расход;
##   руль — A или D: игрок; иначе автоматика держит основное направление,
##          а если оно не задано, руль стоит прямо.
## После отпускания клавиш автоматика возвращает управление через
## manual_release_delay. Курс при перехвате не сбрасывается (раздел 3.2).

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

var _input: CarInput = CarInput.new()
var _throttle_wait: float = 0.0
var _steer_wait: float = 0.0


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


func step(terrain: TerrainSample, dt: float) -> void:
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
	elif course_active:
		steer = autopilot.steer(sim, state, terrain, deg_to_rad(course_deg))
		auto_steer = true
	_input.steer = steer
	_input.throttle = throttle
	sim.step(state, _input, terrain, dt)
