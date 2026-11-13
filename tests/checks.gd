extends RefCounted
## Автопроверки шагов 0 и 1. Запускаются без окна: см. run_checks.bat.
##
## Ожидаемые числа взяты из таблиц дизайн-документа (разделы 3.4, 3.5, 4.2, 6, 7.1)
## и из независимого расчёта той же модели.

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")
const FlatTerrain = preload("res://src/sim/flat_terrain.gd")
const CarSim = preload("res://src/sim/car_sim.gd")
const CarState = preload("res://src/sim/car_state.gd")
const CarInput = preload("res://src/sim/car_input.gd")
const Command = preload("res://src/sim/command.gd")
const RaceSim = preload("res://src/race/race_sim.gd")
const CameraParams = preload("res://src/view/camera_params.gd")
const CameraRig = preload("res://src/view/camera_rig.gd")

const DT: float = 1.0 / 60.0
## Скорость 108 км/ч в м/с.
const V108: float = 30.0
const FUELS: Array = [0.0, 250.0, 500.0]

var passed: int = 0
var failed: int = 0
var lines: PackedStringArray = PackedStringArray()

var _params: CarParams
var _hard: SurfaceParams
var _sand: SurfaceParams
var _slick: SurfaceParams
var _sim: CarSim


func run() -> void:
	_params = load("res://data/car_default.tres") as CarParams
	_hard = load("res://data/surface_hard.tres") as SurfaceParams
	_sand = load("res://data/surface_sand.tres") as SurfaceParams
	_slick = load("res://data/surface_slick.tres") as SurfaceParams
	if _params == null or _hard == null or _sand == null or _slick == null:
		_report(false, "Файлы параметров в папке data не загрузились")
		return
	_sim = CarSim.new(_params)

	_section("Сцепление и масса (4.2)")
	_test_grip_limits()
	_section("Тормозной путь со 108 км/ч (4.2)")
	_test_braking()
	_section("Радиус поворота при 108 км/ч (4.2)")
	_test_turn_radius()
	_section("Мощность и расход (4.2, 6)")
	_test_power_and_consumption()
	_section("Цена WASD (3.5)")
	_test_manual_cost()
	_section("Покрытия и снос (5.1, 5.3)")
	_test_surfaces()
	_section("Остановка, уклон, пустой бак")
	_test_stops()
	_section("Команды и воспроизводимость (9.1, 9.2)")
	_test_commands_and_determinism()
	_section("Камера (7.1)")
	_test_camera()


# --- Проверки ---------------------------------------------------------------

func _test_grip_limits() -> void:
	var expected_brake: Array = [10.0, 9.045, 8.332]
	for i in FUELS.size():
		var mass: float = _sim.total_mass(FUELS[i])
		_near("предел торможения при %d кг, м/с²" % int(mass),
			_sim.tires.longitudinal_limit(mass, _hard), expected_brake[i], 0.01)
	var full: float = _sim.total_mass(500.0)
	var growth: float = _sim.braking_distance(V108, full, _hard) / _sim.braking_distance(V108, 1000.0, _hard)
	_near("полный бак: рост тормозного пути, раз", growth, 1.20, 0.01)


func _test_braking() -> void:
	var from_document: Array = [45.0, 50.0, 54.0]
	var from_model: Array = [42.35, 46.85, 50.85]
	for i in FUELS.size():
		var mass: float = _sim.total_mass(FUELS[i])
		var answer: float = _sim.braking_distance(V108, mass, _hard)
		_near("запрос к модели, %d кг, м" % int(mass), answer, from_document[i], 0.5)
		var state: CarState = _new_state(FUELS[i], V108)
		var steps: int = 0
		while state.speed() > 0.0 and steps < 2000:
			_step(state, 0.0, -1.0, _hard, 0.0)
			steps += 1
		_near("заезд в модели, %d кг, м" % int(mass), state.y, from_model[i], 0.3)
		_true("заезд не длиннее ответа на запрос, %d кг" % int(mass), state.y <= answer)


func _test_turn_radius() -> void:
	var manual_radius: Array = [100.0, 111.0, 120.0]
	var auto_radius: Array = [250.0, 276.0, 300.0]
	var share: float = _params.autopilot_lateral_share
	for i in FUELS.size():
		var mass: float = _sim.total_mass(FUELS[i])
		_near("WASD, %d кг, м" % int(mass), _sim.min_turn_radius(V108, mass, _hard), manual_radius[i], 1.0)
		_near("автоматика, %d кг, м" % int(mass), _sim.min_turn_radius(V108, mass, _hard, share), auto_radius[i], 1.5)
		# В заезде: после выхода руля на упор боковое ускорение равно пределу шин.
		var state: CarState = _new_state(FUELS[i], V108)
		_run(state, 1.0, 0.0, _hard, 60)
		var lateral: float = state.yaw_rate * state.forward_speed()
		_near("заезд: боковое ускорение на упоре, %d кг, м/с²" % int(mass),
			lateral, _sim.tires.lateral_limit_dry(mass), 0.06)
	# На малой скорости радиус ограничен геометрией.
	var slow: CarState = _new_state(250.0, 3.0)
	_run(slow, 1.0, 0.0, _hard, 30)
	_near("радиус на малой скорости, м", slow.forward_speed() / slow.yaw_rate, _params.min_geometric_radius, 0.05)
	# Раздел 3.4: смещение на 10 м вбок автоматикой требует около 105 м пути.
	var radius: float = _sim.min_turn_radius(V108, 1250.0, _hard, share)
	var angle: float = acos(1.0 - 10.0 / (2.0 * radius))
	_near("путь для смещения на 10 м, м", 2.0 * radius * sin(angle), 105.0, 2.0)


func _test_power_and_consumption() -> void:
	var flat_kw: Array = [25.0, 27.2, 29.4]
	var climb_kw: Array = [29.4, 36.8, 44.1]
	for i in FUELS.size():
		var mass: float = _sim.total_mass(FUELS[i])
		var flat: float = _sim.power_for_speed(V108, mass, _hard) / 1000.0
		var climb: float = _sim.power_for_speed(V108, mass, _hard, 0.10) / 1000.0
		_near("108 км/ч по ровному, %d кг, кВт" % int(mass), flat, flat_kw[i], 0.3)
		_near("добавка на подъёме 10 %%, %d кг, кВт" % int(mass), climb - flat, climb_kw[i], 0.3)
	var speeds_kmh: Array = [72.0, 90.0, 108.0, 126.0]
	var rates: Array = [37.0, 56.0, 82.0, 116.0]
	for i in speeds_kmh.size():
		_near("расход при %d км/ч и 1250 кг, кг/мин" % int(speeds_kmh[i]),
			_sim.consumption_for_speed(speeds_kmh[i] / 3.6, 1250.0, _hard), rates[i], 0.7)
	# Минута на 108 км/ч с постоянным газом: расход около 82 кг.
	var state: CarState = _new_state(250.0, V108)
	var throttle: float = _sim.thrust_for_speed(V108, 1250.0, _hard) / _sim.engine.max_thrust_at(V108)
	_run(state, 0.0, throttle, _hard, 3600)
	_near("заезд: израсходовано за минуту, кг", 250.0 - state.fuel, 81.7, 0.5)
	_near("заезд: скорость через минуту, м/с", state.speed(), 30.25, 0.1)
	# Полный газ с места.
	var sprint: CarState = _new_state(250.0, 0.0)
	var steps: int = 0
	while sprint.speed() < 100.0 / 3.6 and steps < 6000:
		_step(sprint, 0.0, 1.0, _hard, 0.0)
		steps += 1
	_near("разгон 0–100 км/ч при 1250 кг, с", steps * DT, 5.03, 0.1)
	_near("топливо на разгон 0–100 км/ч, кг", 250.0 - sprint.fuel, 26.1, 0.5)


func _test_manual_cost() -> void:
	# Резкий объезд: руль на упор, газ отпущен.
	var durations: Array = [1.5, 2.0]
	var losses: Array = [22.0, 30.2]
	for i in durations.size():
		var state: CarState = _new_state(250.0, V108)
		_run(state, 1.0, 0.0, _hard, int(round(durations[i] * 60.0)))
		_near("объезд %.1f с: потеря, км/ч" % durations[i], (V108 - state.speed()) * 3.6, losses[i], 1.0)
	# Лёгкая подруливка в пределах порога автоматики ничего не стоит.
	var light: CarState = _new_state(250.0, V108)
	var coast: CarState = _new_state(250.0, V108)
	_run(light, _params.autopilot_lateral_share, 0.0, _hard, 120)
	_run(coast, 0.0, 0.0, _hard, 120)
	_near("подруливка 40 % против наката: разница, м/с", coast.speed() - light.speed(), 0.0, 0.02)
	# Короткое нажатие: руль не успевает выйти за порог.
	var tap: CarState = _new_state(250.0, V108)
	var coasting: CarState = _new_state(250.0, V108)
	var max_ratio: float = 0.0
	for i in 60:
		var steer: float = 0.0
		if i < 6:
			steer = 1.0
		_step(tap, steer, 0.0, _hard, 0.0)
		_step(coasting, 0.0, 0.0, _hard, 0.0)
		max_ratio = maxf(max_ratio, tap.lateral_ratio)
	_true("нажатие 0,1 с остаётся ниже порога (доля %.2f)" % max_ratio, max_ratio <= _params.autopilot_lateral_share)
	_near("нажатие 0,1 с против наката: разница, м/с", coasting.speed() - tap.speed(), 0.0, 0.005)


func _test_surfaces() -> void:
	# Скользкое: нос поворачивает, а путь почти нет.
	var slick: CarState = _new_state(250.0, V108)
	_run(slick, 1.0, 0.0, _slick, 60)
	var path_angle: float = atan2(slick.vel_east, slick.vel_north)
	_near("скользкое: поворот носа за 1 с, рад", slick.heading, 0.235, 0.01)
	_near("скользкое: поворот пути за 1 с, рад", path_angle, 0.041, 0.005)
	_true("скользкое: нос ушёл от пути больше чем в 4 раза", slick.heading > 4.0 * path_angle)
	# Твёрдый грунт: путь идёт за носом.
	var hard: CarState = _new_state(250.0, V108)
	_run(hard, 1.0, 0.0, _hard, 60)
	_near("твёрдый грунт: путь идёт за носом, рад", atan2(hard.vel_east, hard.vel_north), hard.heading, 0.001)
	# Песок: накат короче из-за качения.
	var on_sand: CarState = _new_state(250.0, V108)
	var on_hard: CarState = _new_state(250.0, V108)
	_run(on_sand, 0.0, 0.0, _sand, 300)
	_run(on_hard, 0.0, 0.0, _hard, 300)
	_true("песок тормозит накат сильнее грунта", on_sand.speed() < on_hard.speed() - 1.0)
	_near("песок: запас сцепления для автоматики, м/с²",
		_sim.max_lateral_accel(1250.0, _sand, _params.autopilot_lateral_share), 9.0 * 0.9045 * 0.7 * 0.4, 0.01)


func _test_stops() -> void:
	var rolling: CarState = _new_state(250.0, 5.0)
	_run(rolling, 0.0, 0.0, _hard, 6000)
	_true("накат заканчивается остановкой", rolling.speed() == 0.0 and rolling.y > 0.0)
	var stop_y: float = rolling.y
	_run(rolling, 0.0, 0.0, _hard, 600)
	_true("стоящая машина не едет назад", rolling.y == stop_y and rolling.speed() == 0.0)
	var gentle: CarState = _new_state(250.0, 0.0)
	_run_on_slope(gentle, 0.02, 600)
	_true("уклон 2 %: машина стоит", gentle.speed() == 0.0)
	var steep: CarState = _new_state(250.0, 0.0)
	_run_on_slope(steep, 0.15, 600)
	_near("уклон 15 %: скатывается, м/с через 10 с", steep.speed(), 11.55, 0.1)
	_true("уклон 15 %: катится вниз по склону", steep.y < 0.0)
	var held: CarState = _new_state(250.0, 0.0)
	for i in 600:
		_step(held, 0.0, -1.0, _hard, 0.15)
	_true("уклон 15 %: тормоз держит", held.speed() == 0.0)
	var empty: CarState = _new_state(0.0, 10.0)
	_step(empty, 0.0, 1.0, _hard, 0.0)
	_true("пустой бак: тяги нет", empty.speed() < 10.0 and empty.thrust == 0.0)
	var no_burn: CarSim = CarSim.new(_params)
	no_burn.burn_fuel = false
	var fixed: CarState = _new_state(250.0, 0.0)
	var input: CarInput = CarInput.new()
	input.throttle = 1.0
	var terrain: TerrainSample = _terrain(_hard, 0.0)
	for i in 300:
		no_burn.step(fixed, input, terrain, DT)
	_true("отладка: расход выключен, топливо не меняется", fixed.fuel == 250.0 and fixed.speed() > 20.0)


func _test_commands_and_determinism() -> void:
	var first: Array = _scripted_race()
	var second: Array = _scripted_race()
	_true("два одинаковых заезда совпадают точно", first == second)
	_true("машина в заезде проехала", first[1] > 50.0)
	var race: RaceSim = RaceSim.new(FlatTerrain.new(_hard))
	race.add_car(_params, 250.0, 0.0, 0.0, 0.0)
	for i in 10:
		race.step()
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 1.0))
	race.step()
	_true("команда записана с номером шага", race.command_log.size() == 1 and race.command_log[0].step_index == 10)
	_true("команда исполнена", race.cars[0].state.speed() > 0.0 and race.cars[0].is_manual_active())
	race.submit(Command.new(Command.Type.MANUAL, 5, 1.0, 1.0))
	_true("команда несуществующей машине отброшена", race.command_log.size() == 1)
	_near("время заезда после 11 шагов, с", race.time_seconds(), 11.0 / 60.0, 0.0001)


func _test_camera() -> void:
	var camera_params: CameraParams = load("res://data/camera_default.tres") as CameraParams
	if camera_params == null:
		_report(false, "Файл параметров камеры не загрузился")
		return
	var camera: CameraRig = CameraRig.new(camera_params, false)
	var screen: Vector2 = Vector2(1920.0, 1080.0)
	var car: Vector2 = Vector2(1000.0, -5000.0)
	var ahead: Array = [127.5, 247.5, 375.0]
	for i in 3:
		camera.set_zoom_index(i)
		var view: Rect2 = camera.visible_world_rect(car, screen)
		_near("зум %d: обзор вперёд, м" % (i + 1), car.y - view.position.y, ahead[i], 0.1)
		var on_screen: Vector2 = camera.world_transform(car, screen) * car
		_near("зум %d: машина по горизонтали, пикс." % (i + 1), on_screen.x, 960.0, 0.5)
		_near("зум %d: машина по вертикали, пикс." % (i + 1), on_screen.y, 810.0, 0.5)
	camera.shift(Vector2(5.0, -5.0))
	_near("сдвиг: не ближе 8 % к правому краю", camera.car_frac.x, 0.92, 0.0001)
	_near("сдвиг: не ближе 8 % к верхнему краю", camera.car_frac.y, 0.08, 0.0001)
	camera.remember_standard()
	_true("Ctrl+щелчок: положение запомнено", camera.standard_frac.is_equal_approx(Vector2(0.92, 0.08)))
	camera.shift(Vector2(-0.3, 0.3))
	camera.quick_return()
	camera.update(0.15)
	_true("возврат: на полпути камера ещё в движении", not camera.car_frac.is_equal_approx(camera.standard_frac))
	camera.update(0.2)
	_true("возврат: через 0,3 с камера на месте", camera.car_frac.is_equal_approx(Vector2(0.92, 0.08)))
	camera.reset_standard()
	camera.update(0.4)
	_true("Shift+щелчок: стандартное положение сброшено", camera.car_frac.is_equal_approx(Vector2(0.5, 0.75)))
	_true("метка стандартного положения показана", camera.marker_time_left > 0.0)


# --- Вспомогательное --------------------------------------------------------

func _new_state(fuel: float, speed: float) -> CarState:
	var state: CarState = CarState.new()
	state.fuel = fuel
	state.set_motion(0.0, speed)
	return state


func _terrain(surface: SurfaceParams, grade_north: float) -> TerrainSample:
	var terrain: TerrainSample = TerrainSample.new()
	terrain.surface = surface
	terrain.grade_north = grade_north
	return terrain


func _step(state: CarState, steer: float, throttle: float, surface: SurfaceParams, grade_north: float) -> void:
	var input: CarInput = CarInput.new()
	input.steer = steer
	input.throttle = throttle
	_sim.step(state, input, _terrain(surface, grade_north), DT)


func _run(state: CarState, steer: float, throttle: float, surface: SurfaceParams, steps: int) -> void:
	var input: CarInput = CarInput.new()
	input.steer = steer
	input.throttle = throttle
	var terrain: TerrainSample = _terrain(surface, 0.0)
	for i in steps:
		_sim.step(state, input, terrain, DT)


func _run_on_slope(state: CarState, grade_north: float, steps: int) -> void:
	var input: CarInput = CarInput.new()
	var terrain: TerrainSample = _terrain(_hard, grade_north)
	for i in steps:
		_sim.step(state, input, terrain, DT)


## Заезд по сценарию через команды: разгон, поворот, торможение.
func _scripted_race() -> Array:
	var race: RaceSim = RaceSim.new(FlatTerrain.new(_hard))
	race.add_car(_params, 250.0, 0.0, 0.0, 0.0)
	for i in 900:
		if i == 0:
			race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 1.0))
		elif i == 240:
			race.submit(Command.new(Command.Type.MANUAL, 0, 1.0, 0.3))
		elif i == 420:
			race.submit(Command.new(Command.Type.MANUAL, 0, -1.0, 0.0))
		elif i == 600:
			race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, -1.0))
		elif i == 780:
			race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
		race.step()
	var state = race.cars[0].state
	return [state.x, state.y, state.heading, state.vel_east, state.vel_north, state.fuel, state.distance]


func _section(title: String) -> void:
	lines.append("")
	lines.append("== %s" % title)


func _near(title: String, actual: float, expected: float, tolerance: float) -> void:
	var ok: bool = absf(actual - expected) <= tolerance
	_report(ok, "%s: %.3f (ожидалось %.3f ± %.3f)" % [title, actual, expected, tolerance])


func _true(title: String, condition: bool) -> void:
	_report(condition, title)


func _report(ok: bool, text: String) -> void:
	if ok:
		passed += 1
		lines.append("  ок      %s" % text)
	else:
		failed += 1
		lines.append("  ОШИБКА  %s" % text)
