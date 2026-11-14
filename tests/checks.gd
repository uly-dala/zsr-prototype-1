extends RefCounted
## Автопроверки шагов 0–9. Запускаются без окна: см. run_checks.bat.
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
const WorldGenParams = preload("res://src/world/world_gen_params.gd")
const GeneratedTerrain = preload("res://src/world/generated_terrain.gd")
const StageLayout = preload("res://src/world/stage_layout.gd")
const MapBuilder = preload("res://src/world/map_builder.gd")
const MapView = preload("res://src/ui/map_view.gd")
const RaceLog = preload("res://src/race/race_log.gd")
const ReplayInput = preload("res://src/input/replay_input.gd")
const AiParams = preload("res://src/input/ai_params.gd")
const AiInput = preload("res://src/input/ai_input.gd")

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
	_section("Запас хода (6)")
	_test_range()
	_section("Удержание скорости и расхода (3.3)")
	_test_hold()
	_section("Приоритет WASD над автоматикой (3.2)")
	_test_manual_priority()
	_section("Основное направление (3.2, 3.4)")
	_test_course()
	_section("Точка и зона клика (3.2, 3.4)")
	_test_point()
	_section("Камера при движении к точке (7.1.1)")
	_test_point_camera()
	_section("Местность из генератора (5, 9.4)")
	_test_terrain()
	_section("Ветер и удары (5.3, 5.4)")
	_test_wind_and_hits()
	_section("Маршрут, ориентиры, контрольные точки (2.1, 7.3)")
	_test_stage()
	_section("Карта и линейка (7.2, 9.4)")
	_test_map()
	_section("Склады топлива (5.5)")
	_test_depots()
	_section("Запись заезда и повтор (7.5, 9.2)")
	_test_log_and_replay()
	_section("Соперники: объезд и задний ход (8)")
	_test_rival_basics()
	_section("Соперники: заезд девяти машин по местности (8)")
	_test_rival_race()


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


func _test_range() -> void:
	var speeds_kmh: Array = [72.0, 90.0, 108.0, 126.0]
	var fuels: Array = [300.0, 400.0, 500.0]
	var table: Array = [[10.4, 13.5, 16.6], [8.4, 11.0, 13.5], [6.8, 9.0, 11.1], [5.6, 7.4, 9.1]]
	for i in speeds_kmh.size():
		for j in fuels.size():
			_near("%d км/ч, %d кг, км" % [int(speeds_kmh[i]), int(fuels[j])],
				_sim.range_at_speed(speeds_kmh[i] / 3.6, fuels[j], _hard) / 1000.0, table[i][j], 0.1)
	_near("песок, 108 км/ч, полный бак, км", _sim.range_at_speed(V108, 500.0, _sand) / 1000.0, 7.2, 0.1)
	_near("пустой бак, км", _sim.range_at_speed(V108, 0.0, _hard), 0.0, 0.0)
	_near("скорость при 80 кг/мин и 1250 кг, км/ч", _sim.speed_for_consumption(80.0, 1250.0, _hard) * 3.6, 107.0, 0.5)


func _test_hold() -> void:
	# Держать скорость 110 км/ч с места.
	var race: RaceSim = _new_race(250.0, 0.0)
	var car = race.cars[0]
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 110.0))
	_steps(race, 1800)
	_near("скорость: держит 110 км/ч", car.state.speed() * 3.6, 110.0, 0.3)
	_near("скорость: расход как по запросу к модели, кг/мин", car.state.consumption,
		_sim.consumption_for_speed(110.0 / 3.6, car.state.mass, _hard), 1.0)
	_true("скорость: газом управляет автоматика", car.auto_throttle)
	# Снизить до 60 км/ч: автоматика тормозит.
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 60.0))
	_steps(race, 600)
	_near("скорость: снизила до 60 км/ч", car.state.speed() * 3.6, 60.0, 0.3)
	# Ноль: остановка.
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 0.0))
	_steps(race, 600)
	_true("скорость: при нуле машина стоит", car.state.speed() == 0.0)
	# Пределы заданного значения.
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 500.0))
	_near("скорость: предел 140 км/ч", car.target_value, 140.0, 0.0)
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.CONSUMPTION, 500.0))
	_near("расход: предел 150 кг/мин", car.target_value, 150.0, 0.0)

	# Держать скорость на песке: расход растёт.
	var on_sand: RaceSim = RaceSim.new(FlatTerrain.new(_sand))
	on_sand.add_car(_params, 250.0, 0.0, 0.0, 0.0)
	on_sand.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 110.0))
	_steps(on_sand, 1800)
	_near("песок: держит 110 км/ч", on_sand.cars[0].state.speed() * 3.6, 110.0, 0.3)
	_true("песок: расход выше, чем на грунте", on_sand.cars[0].state.consumption > 100.0)

	# Держать расход 80 кг/мин.
	var eco: RaceSim = _new_race(250.0, 0.0)
	var eco_car = eco.cars[0]
	eco.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.CONSUMPTION, 80.0))
	_steps(eco, 3600)
	_near("расход: держит 80 кг/мин", eco_car.state.consumption, 80.0, 0.5)
	_near("расход: скорость как по запросу к модели, км/ч", eco_car.state.speed() * 3.6,
		_sim.speed_for_consumption(80.0, eco_car.state.mass, _hard) * 3.6, 4.0)
	var speed_before: float = eco_car.state.speed()
	_steps(eco, 3600)
	_true("расход: скорость растёт по мере выгорания топлива", eco_car.state.speed() > speed_before)
	eco.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.CONSUMPTION, 0.0))
	_steps(eco, 60)
	_true("расход: при нуле двигатель не тянет", eco_car.state.thrust == 0.0 and eco_car.state.consumption == 0.0)


func _test_manual_priority() -> void:
	var race: RaceSim = _new_race(250.0, 0.0)
	var car = race.cars[0]
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 110.0))
	_steps(race, 1800)
	# Только руль: автоматика продолжает держать скорость.
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.3, 0.0))
	_steps(race, 120)
	_true("только руль: газ остаётся у автоматики", car.auto_throttle and car.is_manual_active())
	_near("только руль: скорость держится, км/ч", car.state.speed() * 3.6, 110.0, 0.5)
	_true("только руль: машина повернула", car.state.heading > 0.05)
	# Тормоз вручную, затем отпустить.
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, -1.0))
	_steps(race, 60)
	_true("S: тормозит игрок", not car.auto_throttle and car.state.speed() * 3.6 < 90.0)
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
	_steps(race, 12)
	_true("после отпускания: 0,2 с газ ещё не у автоматики", not car.auto_throttle and car.state.thrust == 0.0)
	_steps(race, 12)
	_true("после отпускания: через 0,4 с автоматика вернула газ", car.auto_throttle and car.state.thrust > 0.0)
	_steps(race, 900)
	_near("после отпускания: скорость восстановлена, км/ч", car.state.speed() * 3.6, 110.0, 0.3)
	# Полный газ вручную сильнее автоматики.
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 1.0))
	_steps(race, 300)
	_true("W: разгон выше заданной скорости", car.state.speed() * 3.6 > 125.0)


func _test_course() -> void:
	var race: RaceSim = _new_race(250.0, 0.0)
	var car = race.cars[0]
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 110.0))
	_steps(race, 1800)
	_near("без курса машина едет прямо, градусы", car.state.heading_deg(), 0.0, 0.0001)
	# Поворот на курс 90°.
	race.submit(Command.new(Command.Type.SET_COURSE, 0, 90.0, 0.0, true))
	var max_ratio: float = 0.0
	var max_scrub: float = 0.0
	var max_heading: float = 0.0
	var reached_step: int = -1
	for i in 1500:
		race.step()
		max_ratio = maxf(max_ratio, car.state.lateral_ratio)
		max_scrub = maxf(max_scrub, car.state.scrub_decel)
		max_heading = maxf(max_heading, car.state.heading_deg())
		if reached_step < 0 and absf(car.state.heading_deg() - 90.0) < 0.2:
			reached_step = i
	_near("поворот на 90°: курс достигнут, градусы", car.state.heading_deg(), 90.0, 0.01)
	_near("поворот на 90°: время, с", reached_step / 60.0, 15.7, 1.0)
	_true("поворот на 90°: без перелёта (наибольший курс %.3f)" % max_heading, max_heading <= 90.001)
	_near("автоматика берёт 40 % боковой силы", max_ratio, 0.4, 0.001)
	_true("поворот автоматики не стоит скорости", max_scrub < 0.001)
	_near("скорость после поворота, км/ч", car.state.speed() * 3.6, 110.0, 0.3)
	_true("рулём управляет автоматика", car.auto_steer)
	# Кратчайшая сторона через север: с 90° на 350° — влево на 100°.
	race.submit(Command.new(Command.Type.SET_COURSE, 0, 350.0, 0.0, true))
	_steps(race, 60)
	_true("с 90° на 350°: поворот влево", car.state.heading_deg() < 90.0 and car.state.yaw_rate < 0.0)
	_steps(race, 1500)
	_near("с 90° на 350°: курс достигнут, градусы", car.state.heading_deg(), 350.0, 0.01)
	# Перехват рулём: курс не сбрасывается, после отпускания машина возвращается.
	race.submit(Command.new(Command.Type.MANUAL, 0, 1.0, 0.0))
	_steps(race, 60)
	_true("D: рулит игрок, курс не сброшен", not car.auto_steer and car.course_active)
	var turned: float = wrapf(car.state.heading_deg() - 350.0, -180.0, 180.0)
	_true("D: машина ушла вправо на %.1f°" % turned, turned > 5.0)
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
	_steps(race, 12)
	_true("после отпускания: 0,2 с руль ещё не у автоматики", not car.auto_steer)
	_steps(race, 600)
	_near("после отпускания: курс возвращён, градусы", car.state.heading_deg(), 350.0, 0.01)
	# Сброс курса.
	race.submit(Command.new(Command.Type.SET_COURSE, 0, 0.0, 0.0, false))
	race.submit(Command.new(Command.Type.MANUAL, 0, 1.0, 0.0))
	_steps(race, 30)
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
	_steps(race, 300)
	_true("C: курс сброшен, машина не возвращается", not car.course_active and not car.auto_steer
		and absf(wrapf(car.state.heading_deg() - 350.0, -180.0, 180.0)) > 1.0)
	_near("C: машина едет прямо, рад/с", car.state.yaw_rate, 0.0, 0.0001)
	# Курс задаётся и на месте, а поворот начинается с движением.
	var parked: RaceSim = _new_race(250.0, 0.0)
	parked.submit(Command.new(Command.Type.SET_COURSE, 0, 180.0, 0.0, true))
	_steps(parked, 120)
	_near("на месте машина не разворачивается, градусы", parked.cars[0].state.heading_deg(), 0.0, 0.0001)
	parked.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 20.0))
	_steps(parked, 1800)
	_near("20 км/ч: разворот на 180°, градусы", parked.cars[0].state.heading_deg(), 180.0, 0.01)
	# На скользком нос поворачивает намного медленнее.
	var ice: RaceSim = RaceSim.new(FlatTerrain.new(_slick))
	ice.add_car(_params, 250.0, 0.0, 0.0, 0.0)
	ice.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 110.0))
	_steps(ice, 3600)
	ice.submit(Command.new(Command.Type.SET_COURSE, 0, 90.0, 0.0, true))
	_steps(ice, 900)
	_true("скользкое: за 15 с курс 90° не достигнут", ice.cars[0].state.heading_deg() < 30.0)


## Машина на 108 км/ч с курсом 0, готовая к постановке точки.
func _cruising_race() -> RaceSim:
	var race: RaceSim = _new_race(250.0, 0.0)
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 108.0))
	race.submit(Command.new(Command.Type.SET_COURSE, 0, 0.0, 0.0, true))
	_steps(race, 1800)
	return race


## Поставить точку со смещением от машины и ехать, пока она стоит.
## Возвращает число шагов.
func _drive_to_point(race: RaceSim, east: float, north: float, limit: int) -> int:
	var car = race.cars[0]
	race.submit(Command.new(Command.Type.SET_POINT, 0, car.state.x + east, car.state.y + north, true))
	var count: int = 0
	while car.point_active and count < limit:
		race.step()
		count += 1
	return count


func _test_point() -> void:
	# Раздел 3.4: смещение на 10 м вбок за 105 м пути, около 3,5 с.
	var race: RaceSim = _cruising_race()
	var car = race.cars[0]
	var start_x: float = car.state.x
	var steps: int = _drive_to_point(race, 10.0, 105.0, 3000)
	_true("10 м вбок на 105 м: точка пройдена", car.points_passed == 1 and car.points_dropped == 0)
	_near("10 м вбок на 105 м: время, с", steps / 60.0, 3.4, 0.3)
	_true("машина сместилась вправо", car.state.x - start_x > 5.0)
	_true("после точки машина на автоматике", car.auto_steer and not car.point_active)
	_steps(race, 900)
	_near("после точки машина вернулась на курс, градусы", wrapf(car.state.heading_deg(), -180.0, 180.0), 0.0, 0.01)
	_true("смещение осталось: машина держит курс, а не линию", car.state.x - start_x > 10.0)
	_near("манёвр к точке не стоил скорости, км/ч", car.state.speed() * 3.6, 108.0, 0.3)

	# Зона клика при заданном курсе.
	var terrain: TerrainSample = _terrain(_hard, 0.0)
	var pilot = car.autopilot
	var x: float = car.state.x
	var y: float = car.state.y
	var radius: float = pilot.auto_turn_radius(car.sim, car.state, terrain)
	_near("радиус поворота автоматики, м", radius, 270.0, 5.0)
	_true("зона: прямо вперёд 200 м — можно", pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x, y + 200.0))
	_true("зона: 18 м вбок на 105 м — можно", pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x + 18.0, y + 105.0))
	_true("зона: 30 м вбок на 105 м — нельзя", not pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x + 30.0, y + 105.0))
	_true("зона: дальше 400 м — нельзя", not pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x, y + 420.0))
	_true("зона: 100 м строго сбоку — нельзя", not pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x + 100.0, y))
	_true("зона: позади — нельзя при заданном курсе", not pilot.point_allowed(car.sim, car.state, terrain, true, 0.0, x, y - 300.0))
	_true("зона: позади — можно, если курс не задан", pilot.point_allowed(car.sim, car.state, terrain, false, 0.0, x, y - 300.0))
	_true("зона под 50°: при курсе на 400 м нельзя, без курса на 600 м можно", pilot.point_allowed(car.sim, car.state, terrain, true, 0.0,
		x + 400.0 * sin(deg_to_rad(50.0)), y + 400.0 * cos(deg_to_rad(50.0))) == false
		and pilot.point_allowed(car.sim, car.state, terrain, false, 0.0,
		x + 600.0 * sin(deg_to_rad(50.0)), y + 600.0 * cos(deg_to_rad(50.0))))
	_near("ближняя граница зоны под 30°, м", pilot.zone_inner_distance(radius, deg_to_rad(30.0)), radius, 0.01)

	# Команда вне зоны отклоняется, прежняя точка остаётся.
	race.submit(Command.new(Command.Type.SET_POINT, 0, x, y + 200.0, true))
	race.submit(Command.new(Command.Type.SET_POINT, 0, x + 100.0, y, true))
	_true("точка вне зоны не ставится, прежняя остаётся",
		car.points_rejected == 1 and car.point_active and car.point_y == y + 200.0)
	# Новая точка заменяет прежнюю.
	race.submit(Command.new(Command.Type.SET_POINT, 0, x + 10.0, y + 250.0, true))
	_true("новая точка заменяет прежнюю", car.point_active and car.point_x == x + 10.0)
	# X снимает точку.
	race.submit(Command.new(Command.Type.SET_POINT, 0, 0.0, 0.0, false))
	_true("точка снята командой", not car.point_active and car.points_dropped == 0)

	# Перехват: точка остаётся; уведённая в сторону машина теряет её как недостижимую.
	var lost: RaceSim = _cruising_race()
	var lost_car = lost.cars[0]
	lost.submit(Command.new(Command.Type.SET_POINT, 0, lost_car.state.x + 15.0, lost_car.state.y + 250.0, true))
	lost.submit(Command.new(Command.Type.MANUAL, 0, -1.0, 0.0))
	_steps(lost, 30)
	_true("перехват рулём: точка не сброшена", lost_car.point_active and not lost_car.auto_steer)
	_steps(lost, 240)
	_true("уход от точки на WASD: точка снята как недостижимая", not lost_car.point_active and lost_car.points_dropped == 1)

	# Курс не задан: машина идёт к точке позади по дуге и дальше едет прямо.
	var roam: RaceSim = _new_race(250.0, 0.0)
	var free_car = roam.cars[0]
	roam.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 108.0))
	_steps(roam, 1800)
	var turn_steps: int = _drive_to_point(roam, 0.0, -300.0, 6000)
	_true("без курса: точка позади пройдена", free_car.points_passed == 1)
	_near("без курса: время разворота к точке, с", turn_steps / 60.0, 51.0, 3.0)
	var heading_after: float = free_car.state.heading_deg()
	_steps(roam, 300)
	_near("без курса: после точки машина едет прямо, градусы", free_car.state.heading_deg(), heading_after, 1.0)

	# На малой скорости зона ближе.
	var slow: RaceSim = _new_race(250.0, 0.0)
	slow.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 20.0))
	_steps(slow, 600)
	_drive_to_point(slow, 10.0, 20.0, 1200)
	_true("20 км/ч: точка в 22 м под углом пройдена", slow.cars[0].points_passed == 1)


func _test_point_camera() -> void:
	var camera_params: CameraParams = load("res://data/camera_default.tres") as CameraParams
	if camera_params == null:
		_report(false, "Файл параметров камеры не загрузился")
		return
	var camera: CameraRig = CameraRig.new(camera_params, false)
	# Таблица режимов: Ctrl — горизонталь наоборот, Alt — вертикаль наоборот.
	var table: Array = [[1, 2, 3, 4], [2, 1, 4, 3], [3, 4, 1, 2], [4, 3, 2, 1]]
	var table_ok: bool = true
	for base in 4:
		camera.point_mode = base + 1
		var row: Array = [camera.resolve_point_mode(false, false), camera.resolve_point_mode(true, false),
			camera.resolve_point_mode(false, true), camera.resolve_point_mode(true, true)]
		if row != table[base]:
			table_ok = false
	_true("таблица режимов с Ctrl и Alt", table_ok)
	camera.point_mode = 4
	camera.cycle_point_mode()
	_true("V: после режима 4 идёт режим 1", camera.point_mode == 1)

	# Пример из документа: экран 1920×1080 не важен, всё в долях экрана.
	var start: Vector2 = Vector2(0.5, 0.75)
	var cursor: Vector2 = Vector2(0.4, 0.3)
	var expected: Array = [Vector2(0.5, 0.75), Vector2(0.4, 0.75), Vector2(0.5, 0.3), Vector2(0.4, 0.3)]
	for mode in 4:
		var rig: CameraRig = CameraRig.new(camera_params, false)
		rig.begin_point(cursor, mode + 1, 200.0)
		for i in 200:
			rig.track_point(200.0 - i, 1.0 / 60.0)
			rig.update(1.0 / 60.0)
		rig.track_point(0.0, 1.0)
		_true("режим %d: машина пришла в нужное место экрана" % (mode + 1), rig.car_frac.is_equal_approx(expected[mode]))
	# Половина пути — половина переноса.
	var half: CameraRig = CameraRig.new(camera_params, false)
	half.begin_point(cursor, 4, 200.0)
	half.track_point(100.0, 10.0)
	_true("полпути: машина на полпути по экрану", half.car_frac.is_equal_approx(start.lerp(cursor, 0.5)))
	# Машина удаляется от точки: возвращается на экране к старту.
	half.track_point(260.0, 10.0)
	_true("удаление от точки: машина вернулась к старту", half.car_frac.is_equal_approx(start))
	# Клик у края: цель сдвигается внутрь до 8 %.
	var edge: CameraRig = CameraRig.new(camera_params, false)
	edge.begin_point(Vector2(0.99, 0.01), 4, 100.0)
	edge.track_point(0.0, 10.0)
	_true("клик у края: машина не ближе 8 % к краю", edge.car_frac.is_equal_approx(Vector2(0.92, 0.08)))
	# После точки: остаётся на новом месте; с возвратом — уходит в стандартное.
	edge.end_point(true)
	edge.update(1.0)
	_true("после точки машина остаётся на новом месте", edge.car_frac.is_equal_approx(Vector2(0.92, 0.08)))
	edge.auto_return = true
	edge.begin_point(Vector2(0.3, 0.3), 2, 100.0)
	edge.track_point(0.0, 10.0)
	edge.end_point(true)
	edge.update(0.75)
	_true("возврат: через 0,75 с камера ещё в пути", not edge.car_frac.is_equal_approx(start))
	edge.update(0.8)
	_true("возврат: через 1,5 с машина в стандартном положении", edge.car_frac.is_equal_approx(start))
	# Ручной сдвиг отменяет автоматическое движение до следующей точки.
	var manual: CameraRig = CameraRig.new(camera_params, false)
	manual.begin_point(cursor, 4, 200.0)
	manual.track_point(100.0, 10.0)
	manual.shift(Vector2(0.1, 0.0))
	var after_shift: Vector2 = manual.car_frac
	manual.track_point(50.0, 10.0)
	_true("ручной сдвиг отменяет движение камеры к точке", manual.car_frac == after_shift and not manual.is_tracking_point())
	# Режим 1 ничего не меняет.
	var follow: CameraRig = CameraRig.new(camera_params, false)
	follow.begin_point(cursor, 1, 200.0)
	follow.track_point(0.0, 10.0)
	_true("режим 1: положение машины на экране не меняется", follow.car_frac == start and not follow.is_tracking_point())


func _test_stage() -> void:
	var world_params: WorldGenParams = load("res://data/world_default.tres") as WorldGenParams
	var layout: StageLayout = StageLayout.new(world_params)
	var twin: StageLayout = StageLayout.new(world_params)
	_true("маршрут воспроизводим", layout.checkpoints == twin.checkpoints and layout.landmarks.size() == twin.landmarks.size())
	_true("контрольных точек четыре", layout.checkpoints.size() == world_params.checkpoint_count)
	var route_ok: bool = true
	var previous: Vector2 = layout.start
	var worst_deviation: float = 0.0
	for checkpoint in layout.checkpoints:
		var leg: Vector2 = checkpoint - previous
		var deviation: float = absf(rad_to_deg(atan2(leg.x, leg.y)))
		worst_deviation = maxf(worst_deviation, deviation)
		if leg.length() < 2000.0 or leg.length() > 4000.0:
			route_ok = false
		if checkpoint.x < world_params.area_min.x or checkpoint.x > world_params.area_max.x:
			route_ok = false
		if checkpoint.y < world_params.area_min.y or checkpoint.y > world_params.area_max.y:
			route_ok = false
		previous = checkpoint
	_true("отрезки от 2 до 4 км, точки внутри местности", route_ok)
	_true("отклонение от севера не больше 45° (наибольшее %.0f°)" % worst_deviation, worst_deviation <= 45.0)
	_near("длина маршрута, км", layout.route_length / 1000.0, 14.0, 2.0)

	# Ориентиры: 20–25, с уникальными именами, не вплотную друг к другу.
	var names: Dictionary = {}
	var spacing_ok: bool = true
	for i in layout.landmarks.size():
		var one: Dictionary = layout.landmarks[i]
		names[one["name"]] = true
		for j in i:
			var two: Dictionary = layout.landmarks[j]
			if Vector2(one["x"], one["y"]).distance_to(Vector2(two["x"], two["y"])) < world_params.landmark_spacing:
				spacing_ok = false
	_true("ориентиров от 20 до 25 (%d)" % layout.landmarks.size(), layout.landmarks.size() >= 20 and layout.landmarks.size() <= 25)
	_true("у каждого ориентира своё имя", names.size() == layout.landmarks.size())
	_true("ориентиры не ближе 700 м друг к другу", spacing_ok)

	# У контрольных точек и ориентиров нет препятствий и скользких полей.
	var world: GeneratedTerrain = GeneratedTerrain.new(world_params, _hard, _sand, _slick, layout.clear_zones())
	var clear_ok: bool = true
	for checkpoint in layout.checkpoints:
		if world.field_at(checkpoint.x, checkpoint.y) >= 0:
			clear_ok = false
		for angle in 8:
			var probe: Vector2 = checkpoint + Vector2(cos(angle * TAU / 8.0), sin(angle * TAU / 8.0)) * 30.0
			if world.obstacle_near(probe.x, probe.y, 1.0).z > 0.0:
				clear_ok = false
	for landmark in layout.landmarks:
		if world.field_at(landmark["x"], landmark["y"]) >= 0 or world.obstacle_near(landmark["x"], landmark["y"], 1.0).z > 0.0:
			clear_ok = false
	_true("у контрольных точек и ориентиров нет препятствий и скользких полей", clear_ok)

	# Точки проходятся по порядку.
	var race: RaceSim = _new_race(250.0, 0.0)
	var car = race.cars[0]
	race.checkpoints = PackedVector2Array([Vector2(0.0, 300.0), Vector2(0.0, 600.0), Vector2(0.0, 900.0)])
	race.checkpoint_radius = 40.0
	car.state.y = 590.0
	race.step()
	_true("вторая точка раньше первой не засчитывается", car.next_checkpoint == 0)
	car.state.y = 265.0
	race.step()
	_true("первая точка засчитана в радиусе 40 м", car.next_checkpoint == 1 and car.checkpoint_steps.size() == 1)
	car.state.x = 45.0
	car.state.y = 600.0
	race.step()
	_true("мимо точки дальше 40 м — не засчитано", car.next_checkpoint == 1)
	car.state.x = 0.0
	race.step()
	car.state.y = 900.0
	race.step()
	_true("последняя точка — финиш", car.next_checkpoint == 3 and car.finish_step == race.step_index - 1)
	race.step()
	_true("после финиша счёт точек не меняется", car.next_checkpoint == 3 and car.checkpoint_steps.size() == 3)


func _test_depots() -> void:
	var world_params: WorldGenParams = load("res://data/world_default.tres") as WorldGenParams
	var layout: StageLayout = StageLayout.new(world_params)
	_true("складов четыре, по одному на отрезок", layout.depots.size() == 4)
	var detours_ok: bool = true
	var from: Vector2 = layout.start
	var report: String = ""
	for i in layout.depots.size():
		var detour: float = StageLayout.detour_length(from, layout.depots[i], layout.checkpoints[i])
		report += " %d" % int(detour)
		if detour < world_params.depot_detour_min - 5.0 or detour > world_params.depot_detour_max + 5.0:
			detours_ok = false
		if layout.depots[i].x < world_params.area_min.x or layout.depots[i].x > world_params.area_max.x:
			detours_ok = false
		from = layout.checkpoints[i]
	_true("крюк до каждого склада от 300 до 900 м:%s" % report, detours_ok)
	var world: GeneratedTerrain = GeneratedTerrain.new(world_params, _hard, _sand, _slick, layout.clear_zones())
	var clear_ok: bool = true
	for depot in layout.depots:
		if world.field_at(depot.x, depot.y) >= 0 or world.obstacle_near(depot.x, depot.y, 10.0).z > 0.0:
			clear_ok = false
	_true("на складах нет препятствий и скользких полей", clear_ok)

	# Один склад на плоскости, четыре машины.
	var race: RaceSim = RaceSim.new(FlatTerrain.new(_hard))
	for i in 4:
		race.add_car(_params, 250.0, 0.0, 0.0, 0.0)
	race.world_state.setup(PackedVector2Array([Vector2(0.0, 500.0)]), 600.0, 200.0, 15.0, 30.0)
	var fast = race.cars[0]
	fast.state.y = 495.0
	fast.state.set_motion(0.0, 20.0)
	_near("быстрее 30 км/ч топливо не взять, кг", race.world_state.try_refuel(fast), 0.0, 0.0)
	fast.state.set_motion(0.0, 8.0)
	_near("медленнее 30 км/ч: порция 200 кг", race.world_state.try_refuel(fast), 200.0, 0.001)
	_true("топливо в баке, склад уменьшился", fast.state.fuel == 450.0 and race.world_state.stock[0] == 400.0 and fast.refuels == 1)
	_near("с одного склада — один раз, кг", race.world_state.try_refuel(fast), 0.0, 0.0)
	var nearly_full = race.cars[1]
	nearly_full.state.fuel = 450.0
	nearly_full.state.y = 510.0
	_near("не больше свободного места в баке, кг", race.world_state.try_refuel(nearly_full), 50.0, 0.001)
	var outside = race.cars[2]
	outside.state.y = 520.0
	_near("вне круга склада топливо не взять, кг", race.world_state.try_refuel(outside), 0.0, 0.0)
	outside.state.y = 500.0
	_near("третья машина: 200 кг", race.world_state.try_refuel(outside), 200.0, 0.001)
	var late = race.cars[3]
	late.state.y = 500.0
	_near("четвёртой достаётся остаток, кг", race.world_state.try_refuel(late), 150.0, 0.001)
	_near("склад пуст, кг", race.world_state.stock[0], 0.0, 0.001)
	_true("номер склада под машиной", race.world_state.depot_at(0.0, 505.0) == 0 and race.world_state.depot_at(0.0, 530.0) == -1)

	# Заправка в заезде: машина проезжает склад на 25 км/ч.
	var drive: RaceSim = _new_race(100.0, 0.0)
	drive.world_state.setup(PackedVector2Array([Vector2(0.0, 150.0)]), 600.0, 200.0, 15.0, 30.0)
	drive.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 25.0))
	_steps(drive, 2400)
	var driver = drive.cars[0]
	_true("в заезде: проезд склада на 25 км/ч заправил машину", driver.refuels == 1 and driver.fuel_taken == 200.0 and driver.state.fuel > 250.0)
	var rush: RaceSim = _new_race(100.0, 0.0)
	rush.world_state.setup(PackedVector2Array([Vector2(0.0, 300.0)]), 600.0, 200.0, 15.0, 30.0)
	rush.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 60.0))
	_steps(rush, 2400)
	_true("в заезде: проезд склада на 60 км/ч ничего не дал", rush.cars[0].refuels == 0)


## Заезд по местности из генератора с объездами: команды по сценарию.
## Возвращает симуляцию после заезда. При replay != null команды берутся из повтора.
func _recorded_race(replay: ReplayInput, race_log: RaceLog) -> RaceSim:
	var race: RaceSim = RaceSim.new(_new_world())
	race.add_car(_params, 400.0, 0.0, 0.0, 0.0)
	race.checkpoints = PackedVector2Array([Vector2(60.0, 600.0)])
	race.world_state.setup(PackedVector2Array([Vector2(60.0, 300.0)]), 600.0, 200.0, 15.0, 30.0)
	var car = race.cars[0]
	for i in 3600:
		if replay != null:
			replay.feed(race)
		elif i == 0:
			race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 25.0))
			race.submit(Command.new(Command.Type.SET_COURSE, 0, 11.0, 0.0, true))
		elif i == 300:
			race.submit(Command.new(Command.Type.MANUAL, 0, 1.0, 0.0))
		elif i == 330:
			race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
		elif i == 600:
			race.submit(Command.new(Command.Type.SET_POINT, 0, car.state.x + 3.0, car.state.y + 60.0, true))
		elif i == 1500:
			race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.CONSUMPTION, 40.0))
		elif i == 2400:
			race.submit(Command.new(Command.Type.MANUAL, 0, -0.5, -1.0))
		elif i == 2460:
			race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
		race.step()
		if race_log != null:
			race_log.record(race.step_index, race.time_seconds(), car, i >= 900 and i < 1200)
	return race


func _test_log_and_replay() -> void:
	var race_log: RaceLog = RaceLog.new()
	var original: RaceSim = _recorded_race(null, race_log)
	var car = original.cars[0]
	race_log.close(original.time_seconds(), car)
	_true("в журнале команд 8 команд", original.command_log.size() == 8)

	# Повтор из журнала команд воспроизводит заезд точно.
	var replayed: RaceSim = _recorded_race(ReplayInput.new(original.command_log), null)
	var twin = replayed.cars[0]
	_true("повтор воспроизводит заезд точно: положение, курс, топливо",
		twin.state.x == car.state.x and twin.state.y == car.state.y
		and twin.state.heading == car.state.heading and twin.state.fuel == car.state.fuel)
	_true("повтор: те же удары, заправки и точки",
		twin.hits == car.hits and twin.refuels == car.refuels and twin.points_passed == car.points_passed
		and twin.next_checkpoint == car.next_checkpoint)

	# Повтор переживает запись в файл и чтение обратно.
	var text: String = JSON.stringify({"commands": ReplayInput.commands_to_data(original.command_log)}, "", false, true)
	var parsed: Variant = JSON.parse_string(text)
	var restored: Array = ReplayInput.commands_from_data(parsed["commands"])
	var from_file: RaceSim = _recorded_race(ReplayInput.new(restored), null)
	_true("повтор из файла воспроизводит заезд точно",
		from_file.cars[0].state.x == car.state.x and from_file.cars[0].state.y == car.state.y
		and from_file.cars[0].state.fuel == car.state.fuel)

	# Журнал для разбора.
	_true("путь и графики записаны дважды в секунду (%d точек)" % race_log.path.size(),
		race_log.path.size() == 121 and race_log.times.size() == 121 and race_log.fuel.size() == 121)
	_near("последняя точка пути — где машина остановилась, м", race_log.path[race_log.path.size() - 1].y, car.state.y, 0.01)
	_true("объезды на A и D отмечены (%d)" % race_log.count("maneuver"), race_log.count("maneuver") == 2)
	_true("заправок в журнале столько же, сколько у машины", race_log.count("refuel") == car.refuels)
	_true("ударов в журнале столько же, сколько у машины", race_log.count("hit") == car.hits)
	_near("карта была открыта 5 с из 60: доля", race_log.share(race_log.map_steps), 300.0 / 3600.0, 0.0001)
	_true("карту открывали один раз", race_log.map_opens == 1)
	_near("режим «держать расход»: доля времени", race_log.share(race_log.consumption_steps), 2100.0 / 3600.0, 0.001)
	_near("на WASD: доля времени", race_log.share(race_log.manual_steps), 90.0 / 3600.0, 0.001)
	if car.next_checkpoint == 1:
		_true("отрезок до контрольной точки записан", race_log.legs.size() == 1 and race_log.legs[0]["distance"] > 590.0)
	else:
		_true("контрольная точка не взята, отрезков в журнале нет", race_log.legs.is_empty())


## Строка в журнал без проверки: числа для настройки.
func _info(text: String) -> void:
	lines.append("  ...     %s" % text)


## Один соперник на плоскости: точка в 1,5 км на севере и камень на пути.
func _rival_on_plane(start_y: float, limit: int) -> RaceSim:
	var ai_params: AiParams = load("res://data/ai_default.tres") as AiParams
	var terrain: FlatTerrain = FlatTerrain.new(_hard)
	terrain.test_obstacle = Vector3(0.0, 400.0, 6.0)
	var race: RaceSim = RaceSim.new(terrain)
	race.checkpoints = PackedVector2Array([Vector2(0.0, 1500.0)])
	var rival: AiInput = AiInput.new(0, AiInput.Kind.MIDDLE, 1, ai_params, 1)
	race.add_car(_params, rival.start_fuel(), 0.0, start_y, 0.0)
	var count: int = 0
	while count < limit and race.cars[0].finish_step < 0:
		rival.decide(race, terrain, [])
		race.step()
		count += 1
	return race


func _test_rival_basics() -> void:
	var ai_params: AiParams = load("res://data/ai_default.tres") as AiParams
	if ai_params == null:
		_report(false, "Файл параметров соперников не загрузился")
		return
	# С разгона: камень на пути в 400 м.
	var race: RaceSim = _rival_on_plane(0.0, 9000)
	var car = race.cars[0]
	_true("соперник объехал камень и взял точку (за %.0f с, ударов %d)" % [race.time_seconds(), car.hits],
		car.finish_step >= 0)
	_true("соперник едет с крейсерской скоростью своего типа", car.target_value >= 0.0 and race.time_seconds() < 90.0)
	_true("соперник управляет командами: в журнале есть курс и скорость", race.command_log.size() >= 2)
	# С места вплотную к камню: упирается, отъезжает задним ходом, объезжает.
	var stuck: RaceSim = _rival_on_plane(392.8, 9000)
	_true("упёршись в камень, соперник выезжает задним ходом и доезжает (за %.0f с)" % stuck.time_seconds(),
		stuck.cars[0].finish_step >= 0)
	# Соперники одного зерна ведут себя одинаково.
	var again: RaceSim = _rival_on_plane(0.0, 9000)
	_true("поведение соперника воспроизводимо", again.cars[0].finish_step == car.finish_step
		and again.cars[0].state.x == car.state.x)
	# Места в гонке.
	var places: RaceSim = _new_race(250.0, 0.0)
	places.add_car(_params, 250.0, 0.0, 100.0, 0.0)
	places.add_car(_params, 250.0, 0.0, 50.0, 0.0)
	places.checkpoints = PackedVector2Array([Vector2(0.0, 1000.0), Vector2(0.0, 2000.0)])
	_true("место по расстоянию до точки", places.place_of(1) == 1 and places.place_of(2) == 2 and places.place_of(0) == 3)
	places.cars[0].next_checkpoint = 1
	_true("взятая точка важнее расстояния", places.place_of(0) == 1 and places.place_of(1) == 2)
	places.cars[2].next_checkpoint = 2
	places.cars[2].finish_step = 500
	_true("финишировавший впереди всех", places.place_of(2) == 1 and places.place_of(0) == 2)


## Девять соперников на местности из генератора, без игрока, до 15 минут.
func _test_rival_race() -> void:
	var world_params: WorldGenParams = load("res://data/world_default.tres") as WorldGenParams
	var ai_params: AiParams = load("res://data/ai_default.tres") as AiParams
	var layout: StageLayout = StageLayout.new(world_params)
	var world: GeneratedTerrain = GeneratedTerrain.new(world_params, _hard, _sand, _slick, layout.clear_zones())
	var race: RaceSim = RaceSim.new(world)
	race.checkpoints = layout.checkpoints
	race.checkpoint_radius = layout.checkpoint_radius
	race.world_state.setup(layout.depots, world_params.depot_stock, world_params.depot_portion,
		world_params.depot_radius, world_params.depot_max_speed)
	var rivals: Array = []
	for kind in 3:
		for number in 3:
			var rival: AiInput = AiInput.new(race.cars.size(), kind, number + 1, ai_params, world_params.world_seed)
			race.add_car(_params, rival.start_fuel(), (rivals.size() - 4) * 7.0, 0.0, 0.0)
			rivals.append(rival)
	var started: int = Time.get_ticks_msec()
	var running: bool = true
	while running and race.step_index < 54000:
		for rival in rivals:
			rival.decide(race, world, layout.landmarks)
		race.step()
		if race.step_index % 600 == 0:
			# Заезд идёт, пока хоть одна машина ещё может доехать.
			running = false
			for car in race.cars:
				if car.finish_step < 0 and (car.state.fuel > 0.0 or car.state.speed() > 0.5):
					running = true
	var finished: int = 0
	var finished_by_kind: Array = [0, 0, 0]
	var best: Array = [0.0, 0.0, 0.0]
	for rival in rivals:
		var car = race.cars[rival.car_id]
		var status: String = "не доехал, взято точек %d, топливо %d кг" % [car.next_checkpoint, int(car.state.fuel)]
		if car.finish_step >= 0:
			var seconds: float = car.finish_step * DT
			status = "финиш %d:%02d, топливо %d кг" % [int(seconds / 60.0), int(seconds) % 60, int(car.state.fuel)]
			finished += 1
			finished_by_kind[rival.kind] += 1
			if best[rival.kind] == 0.0 or seconds < best[rival.kind]:
				best[rival.kind] = seconds
		_info("%s, %d км/ч: %s, путь %.1f км, заправок %d (%d кг), ударов %d, место %d" % [
			rival.title, int(rival.cruise_speed), status, car.state.distance / 1000.0, car.refuels,
			int(car.fuel_taken), car.hits, race.place_of(rival.car_id),
		])
	var stock_text: String = ""
	for value in race.world_state.stock:
		stock_text += " %d" % int(value)
	_info("остатки на складах, кг:%s" % stock_text)
	_info("лучшее время по типам, с: спринтер %d, середняк %d, экономный %d" % [int(best[0]), int(best[1]), int(best[2])])
	_info("расчёт занял %.1f с, шагов %d" % [(Time.get_ticks_msec() - started) / 1000.0, race.step_index])
	_true("до финиша доехали не меньше 5 соперников из 9 (доехало %d)" % finished, finished >= 5)
	_true("доехал хотя бы один соперник каждого типа",
		finished_by_kind[0] > 0 and finished_by_kind[1] > 0 and finished_by_kind[2] > 0)


func _test_map() -> void:
	var world: GeneratedTerrain = _new_world()
	var world_params: WorldGenParams = world.params
	# Малый участок, чтобы проверка шла быстро: 2 × 3 км.
	var image: Image = MapBuilder.build_image(world, Vector2(-1000.0, 0.0), Vector2(1000.0, 3000.0))
	_true("картинка карты: 1 пиксель на 25 м (80 × 120)", image.get_width() == 80 and image.get_height() == 120)
	var full_width: float = (world_params.area_max.x - world_params.area_min.x) / world_params.map_meters_per_pixel
	var full_height: float = (world_params.area_max.y - world_params.area_min.y) / world_params.map_meters_per_pixel
	_true("карта короткого формата: %d × %d пикселей" % [int(full_width), int(full_height)], int(full_width) == 240 and int(full_height) == 520)
	# Скользкое поле на карте окрашено цветом скользкого покрытия.
	var circle: Vector3 = world.field_circle(0)
	var small: Image = MapBuilder.build_image(world, Vector2(circle.x - 100.0, circle.y - 100.0), Vector2(circle.x + 100.0, circle.y + 100.0))
	var pixel: Color = small.get_pixel(4, 4)
	_true("скользкое поле на карте — цветом скользкого", absf(pixel.r - _slick.color.r) < 0.02 and absf(pixel.b - _slick.color.b) < 0.02)

	# Линейка: курс и расстояние.
	_near("линейка: на север, градусы", MapView.ruler_course(Vector2(0.0, 0.0), Vector2(0.0, 1000.0)), 0.0, 0.001)
	_near("линейка: на восток, градусы", MapView.ruler_course(Vector2(0.0, 0.0), Vector2(1000.0, 0.0)), 90.0, 0.001)
	_near("линейка: на юго-запад, градусы", MapView.ruler_course(Vector2(500.0, 500.0), Vector2(0.0, 0.0)), 225.0, 0.001)
	_near("линейка: расстояние, км", MapView.ruler_distance_km(Vector2(0.0, 0.0), Vector2(3000.0, 4000.0)), 5.0, 0.001)
	# Раздел 7.3: ошибка 5° на отрезке 3 км даёт около 260 м промаха.
	_near("промах при ошибке 5° на 3 км, м", 3000.0 * sin(deg_to_rad(5.0)), 260.0, 2.0)


func _new_world() -> GeneratedTerrain:
	var world_params: WorldGenParams = load("res://data/world_default.tres") as WorldGenParams
	return GeneratedTerrain.new(world_params, _hard, _sand, _slick)


func _test_terrain() -> void:
	var world: GeneratedTerrain = _new_world()
	var twin: GeneratedTerrain = _new_world()
	var world_params: WorldGenParams = world.params
	# Одно зерно — одна местность.
	var same: bool = true
	var max_grade: float = 0.0
	var max_height: float = 0.0
	var counts: Dictionary = {"hard": 0, "sand": 0, "slick": 0}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 4000:
		var x: float = rng.randf_range(world_params.area_min.x, world_params.area_max.x)
		var y: float = rng.randf_range(world_params.area_min.y, world_params.area_max.y)
		var first: TerrainSample = world.sample(x, y)
		var height: float = first.height
		var grade: float = sqrt(first.grade_east * first.grade_east + first.grade_north * first.grade_north)
		var surface_id: String = first.surface.id
		var second: TerrainSample = twin.sample(x, y)
		if second.height != height or second.surface.id != surface_id:
			same = false
		max_grade = maxf(max_grade, grade)
		max_height = maxf(max_height, absf(height))
		counts[surface_id] += 1
	_true("одно зерно даёт одну и ту же местность", same)
	_true("уклон не больше 15 %% (наибольший %.1f %%)" % (max_grade * 100.0), max_grade <= world_params.max_grade + 0.0001)
	_true("рельеф есть: уклоны до %.1f %%, высоты до %d м" % [max_grade * 100.0, int(max_height)], max_grade > 0.05 and max_height > 10.0)
	_true("есть все три покрытия: грунт %d, песок %d, скользкое %d из 4000" % [counts["hard"], counts["sand"], counts["slick"]],
		counts["hard"] > 1500 and counts["sand"] > 100 and counts["slick"] > 20)
	# Другое зерно — другая местность.
	var other_params: WorldGenParams = world_params.duplicate() as WorldGenParams
	other_params.world_seed = world_params.world_seed + 1
	var other: GeneratedTerrain = GeneratedTerrain.new(other_params, _hard, _sand, _slick)
	_true("другое зерно даёт другую местность", other.height_at(500.0, 2000.0) != world.height_at(500.0, 2000.0))

	# Скользкие поля: ровные, с ветром, без препятствий.
	_true("скользких полей столько, сколько задано", world.field_count() == world_params.slick_count)
	var fields_ok: bool = true
	for field in world.field_count():
		var circle: Vector3 = world.field_circle(field)
		var inside: TerrainSample = world.sample(circle.x, circle.y)
		var wind: float = sqrt(inside.wind_east * inside.wind_east + inside.wind_north * inside.wind_north)
		if inside.surface.id != "slick" or inside.grade_east != 0.0 or inside.grade_north != 0.0:
			fields_ok = false
		if wind < world_params.wind_min - 0.001 or wind > world_params.wind_max + 0.001:
			fields_ok = false
		if circle.z < world_params.slick_radius_min or circle.z > world_params.slick_radius_max:
			fields_ok = false
	_true("поля скользкие, ровные, с ветром от 0,2 до 0,5 м/с²", fields_ok)
	_true("на старте не скользко", world.sample(0.0, 0.0).surface.id != "slick")

	# Препятствия: из зерна и координат части, в заданных размерах, не на скользком.
	var total: int = 0
	var obstacles_ok: bool = true
	for cx in range(-3, 3):
		for cy in range(0, 8):
			var list: PackedFloat32Array = world.build_obstacles(cx, cy)
			if list != twin.build_obstacles(cx, cy):
				obstacles_ok = false
			var index: int = 0
			while index < list.size():
				total += 1
				var radius: float = list[index + 2]
				if radius < world_params.obstacle_radius_min or radius > world_params.obstacle_radius_max:
					obstacles_ok = false
				if world.field_at(list[index], list[index + 1]) >= 0:
					obstacles_ok = false
				if floor(list[index] / world_params.chunk_size) != cx or floor(list[index + 1] / world_params.chunk_size) != cy:
					obstacles_ok = false
				index += 4
	_true("препятствия воспроизводимы, нужного размера, не на скользком", obstacles_ok)
	var area_km2: float = 48.0 * world_params.chunk_size * world_params.chunk_size / 1000000.0
	_near("плотность препятствий, на км²", total / area_km2, world_params.obstacle_density, 40.0)
	_true("у старта препятствий нет", world.obstacle_near(0.0, 0.0, 1.0).z == 0.0 and world.obstacle_near(30.0, 30.0, 1.0).z == 0.0)
	var some: PackedFloat32Array = world.build_obstacles(1, 3)
	if some.size() >= 4:
		var hit: Vector3 = world.obstacle_near(some[0], some[1], 1.0)
		_true("препятствие находится по своим координатам", hit.z > 0.0 and absf(hit.z - some[2]) < 0.001)
		_true("рядом с препятствием касания с ним нет", world.obstacle_near(some[0] + some[2] + 1.5, some[1], 1.0) != hit)
	else:
		_report(false, "в части (1, 3) нет препятствий")

	# Данные картинки части.
	var cells: int = world_params.chunk_cells
	var data: PackedFloat32Array = world.build_chunk_data(2, -5)
	_true("данные части: по четыре числа на узел сетки", data.size() == (cells + 1) * (cells + 1) * 4)
	var step_size: float = world_params.chunk_size / cells
	var node: int = (7 * (cells + 1) + 20) * 4
	_near("данные части совпадают со слоем данных: высота, м", data[node],
		world.height_at(2.0 * world_params.chunk_size + 20.0 * step_size, -(-5.0 * world_params.chunk_size + 7.0 * step_size)), 0.0001)
	# Соседние части сходятся на стыке.
	var neighbour: PackedFloat32Array = world.build_chunk_data(3, -5)
	_near("стык частей: высота на общей границе", data[(7 * (cells + 1) + cells) * 4], neighbour[(7 * (cells + 1)) * 4], 0.0001)


func _test_wind_and_hits() -> void:
	# Ветер 0,2 и 0,5 м/с² поперёк пути, поле 500 м на 108 км/ч: снос 30–70 м.
	var strengths: Array = [0.2, 0.5]
	var shifts: Array = [27.8, 69.4]
	for i in strengths.size():
		var state: CarState = _new_state(250.0, V108)
		var input: CarInput = CarInput.new()
		var on_field: TerrainSample = _terrain(_slick, 0.0)
		on_field.wind_east = strengths[i]
		var steps: int = 0
		while state.y < 500.0 and steps < 3000:
			# Газ держит скорость; руль прямо: нос остаётся на курсе.
			input.throttle = _sim.thrust_for_speed(V108, _sim.total_mass(state.fuel), _slick) / _sim.engine.max_thrust_at(V108)
			_sim.step(state, input, on_field, DT)
			steps += 1
		_near("ветер %.1f м/с²: снос за 500 м, м" % strengths[i], state.x, shifts[i], 3.0)
		_near("ветер %.1f м/с²: нос остался на курсе, градусы" % strengths[i], wrapf(state.heading_deg(), -180.0, 180.0), 0.0, 0.001)
		# После поля снос прекращается, смещение остаётся.
		var off_field: TerrainSample = _terrain(_hard, 0.0)
		input.throttle = 0.0
		for j in 120:
			_sim.step(state, input, off_field, DT)
		var x_after: float = state.x
		for j in 120:
			_sim.step(state, input, off_field, DT)
		_near("ветер %.1f м/с²: после поля машину больше не сносит, м" % strengths[i], state.x - x_after, 0.0, 0.01)
		_true("ветер %.1f м/с²: смещение осталось" % strengths[i], state.x > shifts[i] - 3.0)
	# На твёрдом грунте ветер не действует: слой данных его не даёт.
	var world: GeneratedTerrain = _new_world()
	var found_wind: bool = false
	for i in 200:
		var probe: TerrainSample = world.sample(-2500.0 + i * 25.0, 300.0)
		if probe.surface.id != "slick" and (probe.wind_east != 0.0 or probe.wind_north != 0.0):
			found_wind = true
	_true("на обычном грунте ветра нет", not found_wind)

	# Удар в лоб: препятствие сплошное, машина останавливается перед ним.
	var race: RaceSim = _cruising_race()
	var car = race.cars[0]
	var rock: Vector3 = Vector3(car.state.x, car.state.y + 200.0, 5.0)
	race.terrain.test_obstacle = rock
	var touch: float = rock.z + _params.collision_margin
	_steps(race, 420)
	_true("удар в лоб засчитан один раз", car.hits == 1)
	_near("машина стоит на границе препятствия, м", rock.y - car.state.y, touch, 0.05)
	_true("управление на секунду заблокировано", car.blocked_left > 0.0 and not car.auto_throttle)
	_steps(race, 600)
	_true("автоматика упирается и стоит: насквозь не проехать", car.state.speed() < 0.1 and rock.y - car.state.y >= touch - 0.05)
	_true("стоя у препятствия, машина не получает новых ударов", car.hits == 1)
	var fuel_stuck: float = car.state.fuel
	_steps(race, 300)
	_near("упёршись, машина топливо не тратит, кг", fuel_stuck - car.state.fuel, 0.0, 0.01)
	# Задний ход: S с места.
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, -1.0))
	_steps(race, 180)
	_true("S с места: задний ход", car.is_reversing() and rock.y - car.state.y > touch + 5.0)
	_near("задний ход: скорость не выше предела, м/с", -car.state.forward_speed(), _params.reverse_max_speed, 0.5)
	_true("задний ход тратит топливо", fuel_stuck - car.state.fuel > 0.05)
	_near("задний ход: нос по-прежнему на север, градусы", wrapf(car.state.heading_deg(), -180.0, 180.0), 0.0, 0.01)
	# W при движении назад сначала тормозит, потом едет вперёд.
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 1.0))
	_steps(race, 12)
	_true("W при движении назад: сначала тормоз", car.state.thrust == 0.0 and car.state.forward_speed() < 0.0)
	_steps(race, 120)
	_true("W: затем вперёд", car.state.forward_speed() > 1.0)
	race.submit(Command.new(Command.Type.MANUAL, 0, 0.0, 0.0))
	# Руль на заднем ходу поворачивает нос в обратную сторону.
	var back: RaceSim = _new_race(250.0, 0.0)
	back.submit(Command.new(Command.Type.MANUAL, 0, 1.0, -1.0))
	_steps(back, 120)
	_true("задний ход с рулём вправо: нос уходит влево", back.cars[0].state.heading_deg() > 180.0)
	# Автоматика назад не ездит: при заданном нуле машина стоит.
	var parked: RaceSim = _new_race(250.0, 0.0)
	_steps(parked, 300)
	_true("заданная скорость 0: машина стоит, а не пятится", parked.cars[0].state.speed() == 0.0 and parked.cars[0].state.y == 0.0)

	# Удар вскользь: остаётся 20 % скорости вдоль препятствия.
	var glance: RaceSim = _new_race(250.0, V108)
	var glance_car = glance.cars[0]
	var side: float = 6.0 / sqrt(2.0)
	glance_car.collide(glance_car.state.x - side + 0.1, glance_car.state.y + side, 6.0)
	_near("удар под 45°: осталось скорости, м/с", glance_car.state.speed(), V108 * sin(deg_to_rad(45.0)) * 0.2, 0.3)
	_true("удар под 45° засчитан", glance_car.hits == 1 and glance_car.blocked_left > 0.0)
	# Медленное касание — не удар.
	var slow: RaceSim = _new_race(250.0, 1.0)
	var slow_car = slow.cars[0]
	slow_car.collide(slow_car.state.x, slow_car.state.y + 5.5, 6.0)
	_true("касание медленнее 2 м/с — не удар", slow_car.hits == 0 and slow_car.blocked_left == 0.0 and slow_car.state.speed() < 0.001)

	# Заезд по настоящей местности: воспроизводимость вместе с ударами.
	var first: Array = _world_race(true)
	var second: Array = _world_race(true)
	_true("заезд по местности из генератора воспроизводим", first == second)
	# Автоматика препятствий не видит: без объезда она упирается в первый же камень.
	_true("без объезда машина упирается в камень (проехала %.0f м, ударов %d)" % [first[1], first[3]],
		first[3] >= 1 and first[1] < 5000.0)
	# Без препятствий: три минуты по рельефу, песку и скользким полям.
	var open_ground: Array = _world_race(false)
	_true("без препятствий машина проехала больше 4 км (%.0f м)" % open_ground[1],
		open_ground[1] > 4000.0 and open_ground[3] == 0)


## Три минуты по местности из генератора на автоматике: курс на север, 108 км/ч.
func _world_race(with_obstacles: bool) -> Array:
	var world: GeneratedTerrain = _new_world()
	if not with_obstacles:
		var bare: WorldGenParams = world.params.duplicate() as WorldGenParams
		bare.obstacle_density = 0.0
		world = GeneratedTerrain.new(bare, _hard, _sand, _slick)
	var race: RaceSim = RaceSim.new(world)
	race.add_car(_params, 500.0, 0.0, 0.0, 0.0)
	race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, 108.0))
	race.submit(Command.new(Command.Type.SET_COURSE, 0, 0.0, 0.0, true))
	_steps(race, 10800)
	var car = race.cars[0]
	return [car.state.x, car.state.y, car.state.fuel, car.hits]


func _new_race(fuel: float, speed: float) -> RaceSim:
	var race: RaceSim = RaceSim.new(FlatTerrain.new(_hard))
	var car = race.add_car(_params, fuel, 0.0, 0.0, 0.0)
	car.state.set_motion(0.0, speed)
	return race


func _steps(race: RaceSim, count: int) -> void:
	for i in count:
		race.step()


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


## throttle: плюс — газ, минус — тормоз.
func _step(state: CarState, steer: float, throttle: float, surface: SurfaceParams, grade_north: float) -> void:
	var input: CarInput = CarInput.new()
	input.steer = steer
	input.throttle = maxf(throttle, 0.0)
	input.brake = maxf(-throttle, 0.0)
	_sim.step(state, input, _terrain(surface, grade_north), DT)


func _run(state: CarState, steer: float, throttle: float, surface: SurfaceParams, steps: int) -> void:
	var input: CarInput = CarInput.new()
	input.steer = steer
	input.throttle = maxf(throttle, 0.0)
	input.brake = maxf(-throttle, 0.0)
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
