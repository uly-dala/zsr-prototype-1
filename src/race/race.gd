extends Node2D
## Сцена заезда.
##
## Шаги 1–3 дизайн-документа: одна машина на пустой плоскости, WASD,
## силы и масса, камера, удержание скорости и расхода, экран заезда,
## основное направление и указатель курса, точка, зона клика и камера
## при движении к точке, местность из генератора с подгрузкой частями,
## покрытия, ветер, препятствия, карта, ориентиры, контрольные точки, линейка,
## склады топлива и выбор заправки перед стартом.
##
## Узел только связывает части между собой:
##   ввод игрока -> команды -> RaceSim (фиксированный шаг 60 раз в секунду)
##   состояние машины -> камера, изображение, экран, запись.

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const FlatTerrain = preload("res://src/sim/flat_terrain.gd")
const WorldGenParams = preload("res://src/world/world_gen_params.gd")
const GeneratedTerrain = preload("res://src/world/generated_terrain.gd")
const ChunkStreamer = preload("res://src/view/chunk_streamer.gd")
const StageLayout = preload("res://src/world/stage_layout.gd")
const MapBuilder = preload("res://src/world/map_builder.gd")
const StageView = preload("res://src/view/stage_view.gd")
const MapView = preload("res://src/ui/map_view.gd")
const RaceSim = preload("res://src/race/race_sim.gd")
const Car = preload("res://src/race/car.gd")
const Recorder = preload("res://src/race/recorder.gd")
const PlayerInput = preload("res://src/input/player_input.gd")
const CameraParams = preload("res://src/view/camera_params.gd")
const CameraRig = preload("res://src/view/camera_rig.gd")
const GroundGrid = preload("res://src/view/ground_grid.gd")
const CarView = preload("res://src/view/car_view.gd")
const TrailView = preload("res://src/view/trail_view.gd")
const CourseView = preload("res://src/view/course_view.gd")
const PointView = preload("res://src/view/point_view.gd")
const Beeper = preload("res://src/ui/beeper.gd")
const Hud = preload("res://src/ui/hud.gd")
const Command = preload("res://src/sim/command.gd")

const CAR_PARAMS_PATH: String = "res://data/car_default.tres"
const CAMERA_PARAMS_PATH: String = "res://data/camera_default.tres"
const WORLD_PARAMS_PATH: String = "res://data/world_default.tres"
const SURFACE_PATHS: Array = [
	"res://data/surface_hard.tres",
	"res://data/surface_sand.tres",
	"res://data/surface_slick.tres",
]
## Точка следа ставится раз в столько шагов.
const TRAIL_EVERY: int = 6
## Отладка: шаг изменения топлива клавишами [ и ], кг.
const DEBUG_FUEL_STEP: float = 50.0
## Вращение колеса не учитывается, пока колесо нажато и столько секунд после
## отпускания: иначе возврат камеры случайно менял бы заданную скорость (7.1).
const WHEEL_GUARD_TIME: float = 0.15
const POINT_MODE_NAMES: Array = ["следование", "по горизонтали", "по вертикали", "полный"]

## Топливо на старте, кг. 250 кг — полбака, «средняя масса» из документа.
@export_range(0.0, 500.0, 50.0) var start_fuel: float = 250.0
## Шагов симуляции за один тик: 1 — обычное время, 4 и 16 — ускорение.
@export_range(1, 16) var steps_per_tick: int = 1

var _car_params: CarParams
var _surfaces: Array = []
## Местность: 0 — из генератора; 1, 2, 3 — отладочная плоскость
## с одним покрытием (грунт, песок, скользкое).
var _terrain_mode: int = 0
var _generated: GeneratedTerrain
var _flat: FlatTerrain
var _streamer: ChunkStreamer
var _show_chunks: bool = false
var _seen_hits: int = 0
var _layout: StageLayout
var _stage_view: StageView
var _map: MapView
var _world_params: WorldGenParams
var _map_task: int = -1
var _map_image: Image = null
var _map_mutex: Mutex = Mutex.new()
var _map_opened_msec: int = -1
var _seen_checkpoint: int = 0
var _seen_refuels: int = 0
## Экран перед стартом (раздел 2.2): открыта карта, игрок выбирает заправку,
## симуляция стоит.
var _prestart: bool = false
var _chosen_fuel: float = 350.0
## Сколько секунд ещё показывать строку о заправке и её текст.
var _notice_left: float = 0.0
var _notice_text: String = ""
## Истинный путь для отладочного показа на карте (F1): восток и север, м.
var _true_trail: PackedVector2Array = PackedVector2Array()
var _burn_fuel: bool = true

var _terrain
var _sim: RaceSim
var _player: Car
var _player_input: PlayerInput
var _recorder: Recorder = Recorder.new()
var _camera: CameraRig

var _world: Node2D
var _grid: GroundGrid
var _trail: TrailView
var _course_view: CourseView
var _point_view: PointView
var _beeper: Beeper
var _car_view: CarView
var _hud: Hud

# Состояние машины на прошлом шаге: кадры рисуются между шагами симуляции.
var _prev_x: float = 0.0
var _prev_y: float = 0.0
var _prev_heading: float = 0.0

var _show_details: bool = true
var _middle_down: bool = false
var _middle_dragging: bool = false
var _middle_press_pos: Vector2 = Vector2.ZERO
var _middle_release_msec: int = -100000
## Показание пройденного пути, от которого считает одометр, м.
var _odometer_zero: float = 0.0
var _right_down: bool = false
var _seen_passed: int = 0
var _seen_dropped: int = 0
var _last_point_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_car_params = load(CAR_PARAMS_PATH) as CarParams
	var camera_params: CameraParams = load(CAMERA_PARAMS_PATH) as CameraParams
	for path in SURFACE_PATHS:
		_surfaces.append(load(path))
	assert(_car_params != null, "Не загружен файл параметров машины")
	assert(camera_params != null, "Не загружен файл параметров камеры")
	_camera = CameraRig.new(camera_params)

	var world_params: WorldGenParams = load(WORLD_PARAMS_PATH) as WorldGenParams
	assert(world_params != null, "Не загружен файл параметров местности")
	_world_params = world_params
	_layout = StageLayout.new(world_params)
	_generated = GeneratedTerrain.new(world_params, _surfaces[0], _surfaces[1], _surfaces[2], _layout.clear_zones())
	_flat = FlatTerrain.new(_surfaces[0])

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_streamer = ChunkStreamer.new()
	_streamer.name = "Terrain"
	_world.add_child(_streamer)
	_stage_view = StageView.new()
	_stage_view.name = "Stage"
	_world.add_child(_stage_view)
	_grid = GroundGrid.new()
	_grid.name = "GroundGrid"
	_world.add_child(_grid)
	_trail = TrailView.new()
	_trail.name = "Trail"
	_world.add_child(_trail)
	_point_view = PointView.new()
	_point_view.name = "Point"
	_world.add_child(_point_view)
	_course_view = CourseView.new()
	_course_view.name = "CourseLine"
	_world.add_child(_course_view)
	_car_view = CarView.new()
	_car_view.name = "PlayerCar"
	_world.add_child(_car_view)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_beeper = Beeper.new()
	_beeper.name = "Beeper"
	add_child(_beeper)
	_hud = Hud.new()
	_hud.name = "Hud"
	layer.add_child(_hud)
	_map = MapView.new()
	_map.name = "Map"
	layer.add_child(_map)
	_map.setup(_generated, _layout, world_params.area_min, world_params.area_max, world_params.map_grid_step)
	# Картинка карты строится один раз в фоне (раздел 9.4).
	_map_task = WorkerThreadPool.add_task(_build_map_image)

	_chosen_fuel = world_params.start_fuel_default
	_apply_terrain_mode()
	_start_race()


func _exit_tree() -> void:
	_recorder.stop()
	if _map_task != -1:
		WorkerThreadPool.wait_for_task_completion(_map_task)
		_map_task = -1


## Работает в фоновом потоке.
func _build_map_image() -> void:
	var image: Image = MapBuilder.build_image(_generated, _world_params.area_min, _world_params.area_max)
	_map_mutex.lock()
	_map_image = image
	_map_mutex.unlock()


## Принять готовую картинку карты из фонового потока.
func _accept_map_image() -> void:
	if _map_task == -1 or not WorkerThreadPool.is_task_completed(_map_task):
		return
	WorkerThreadPool.wait_for_task_completion(_map_task)
	_map_task = -1
	_map_mutex.lock()
	var image: Image = _map_image
	_map_image = null
	_map_mutex.unlock()
	if image != null:
		_map.set_texture(ImageTexture.create_from_image(image))


## Начать заезд заново: машина в начале координат, носом на север.
func _start_race() -> void:
	_sim = RaceSim.new(_terrain)
	_apply_stage()
	_seen_checkpoint = 0
	_seen_refuels = 0
	_notice_left = 0.0
	_true_trail = PackedVector2Array()
	var fuel: float = start_fuel
	if _terrain_mode == 0:
		fuel = _chosen_fuel
	_player = _sim.add_car(_car_params, fuel, 0.0, 0.0, 0.0)
	# На местности из генератора заезд начинается с экрана выбора заправки.
	_prestart = _terrain_mode == 0
	_map.set_open(_prestart)
	_player.sim.burn_fuel = _burn_fuel
	_player_input = PlayerInput.new(_player.id)
	_odometer_zero = 0.0
	_seen_passed = 0
	_seen_dropped = 0
	_seen_hits = 0
	_camera.end_point(false)
	_store_previous()
	_trail.clear()
	_trail.add_point(Vector2.ZERO)
	_recorder.start()


func _physics_process(_delta: float) -> void:
	if _prestart:
		return
	for _i in steps_per_tick:
		_player_input.poll(_sim)
		_store_previous()
		_sim.step()
		_recorder.sample(_sim.step_index, _sim.time_seconds(), _player, _surface_under_player().id, _map.is_open)
		if _sim.step_index % TRAIL_EVERY == 0:
			_trail.add_point(Vector2(_player.state.x, -_player.state.y))
		if _sim.step_index % 60 == 0:
			_true_trail.append(Vector2(_player.state.x, _player.state.y))


func _process(delta: float) -> void:
	# Сдвиг камеры стрелками: стрелка вверх открывает обзор вперёд,
	# машина при этом уходит по экрану вниз.
	var shift: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_UP):
		shift.y += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		shift.y -= 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		shift.x += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		shift.x -= 1.0
	# Перед стартом стрелки выбирают заправку, а не двигают камеру.
	if shift != Vector2.ZERO and not _prestart:
		_camera.shift(shift * _camera.params.arrow_shift_rate * delta)
	_camera.update(delta)

	# Положение машины между двумя шагами симуляции. Мир: y — север;
	# экран Godot: y — вниз, поэтому знак y меняется.
	var s = _player.state
	var alpha: float = Engine.get_physics_interpolation_fraction()
	var car_pos: Vector2 = Vector2(lerpf(_prev_x, s.x, alpha), -lerpf(_prev_y, s.y, alpha))
	_car_view.position = car_pos
	_car_view.rotation = lerp_angle(_prev_heading, s.heading, alpha)
	_car_view.velocity = Vector2(s.vel_east, -s.vel_north)
	if _car_view.show_velocity != _show_details:
		_car_view.show_velocity = _show_details
		_car_view.queue_redraw()
	elif _show_details:
		_car_view.queue_redraw()

	var viewport_size: Vector2 = get_viewport_rect().size
	_update_point(car_pos, viewport_size, delta)
	_world.transform = _camera.world_transform(car_pos, viewport_size)
	_streamer.update_center(car_pos)
	_accept_map_image()
	if _player.next_checkpoint != _seen_checkpoint:
		# Контрольная точка пройдена: на карте вспыхивает «вы здесь».
		if _player.next_checkpoint > _seen_checkpoint and _seen_checkpoint < _sim.checkpoints.size():
			_map.flash_here(_sim.checkpoints[_player.next_checkpoint - 1])
		_seen_checkpoint = _player.next_checkpoint
		_stage_view.set_next_checkpoint(_seen_checkpoint)
	if _player.refuels != _seen_refuels:
		_seen_refuels = _player.refuels
		_notice_text = "ЗАПРАВКА: в баке %d кг" % roundi(s.fuel)
		_notice_left = 4.0
		_beeper.beep()
	if _notice_left > 0.0:
		_notice_left = maxf(0.0, _notice_left - delta)
	_map.banner = ""
	if _prestart:
		_map.banner = _prestart_text()
	_map.true_position = Vector2(s.x, s.y)
	_map.true_trail = _true_trail
	_map.update_view(viewport_size, delta)
	if _grid.visible:
		_grid.visible_rect = _camera.visible_world_rect(car_pos, viewport_size)
		_grid.queue_redraw()
	if _player.hits != _seen_hits:
		_seen_hits = _player.hits
		_beeper.beep()

	_course_view.set_course(_player.course_active, car_pos, deg_to_rad(_player.course_deg))
	var course_text: String = "%.1f°" % s.heading_deg()
	if _player.course_active:
		course_text += "\nзадан %d°" % roundi(_player.course_deg)
	_hud.set_course_text(course_text, _camera.car_frac)
	_hud.set_marker(_camera.marker_time_left > 0.0, _camera.standard_frac)
	_hud.set_lines(_build_hud_text())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if _prestart:
			if key.pressed:
				_on_prestart_key(key.physical_keycode)
		elif key.physical_keycode == KEY_M:
			if not key.echo:
				_on_map_key(key.pressed)
		elif key.pressed and key.physical_keycode == KEY_Q:
			# Q и E повторяются при удержании: так удобнее набирать курс числом.
			_player_input.adjust_course(_sim, -1.0)
		elif key.pressed and key.physical_keycode == KEY_E:
			_player_input.adjust_course(_sim, 1.0)
		elif key.pressed and not key.echo:
			_on_key(key.physical_keycode)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_on_middle_button(button)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_button(button)
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(button.position)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_on_wheel(1)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_on_wheel(-1)
	elif event is InputEventMouseMotion:
		if _middle_down:
			_on_middle_motion(event as InputEventMouseMotion)


func _on_key(keycode: int) -> void:
	match keycode:
		KEY_1:
			_camera.set_zoom_index(0)
		KEY_2:
			_camera.set_zoom_index(1)
		KEY_3:
			_camera.set_zoom_index(2)
		KEY_F2:
			_show_details = not _show_details
		KEY_TAB:
			_player_input.toggle_mode(_sim)
		KEY_X:
			if _player.point_active:
				_player_input.clear_point(_sim)
				_camera.end_point(false)
		KEY_V:
			_camera.cycle_point_mode()
		KEY_H:
			_camera.toggle_auto_return()
		KEY_C:
			_player_input.clear_course(_sim)
		KEY_O:
			_odometer_zero = _player.state.distance
		KEY_R:
			_start_race()
		KEY_T:
			_terrain_mode = (_terrain_mode + 1) % 4
			_apply_terrain_mode()
			_start_race()
		KEY_F1:
			_map.show_truth = not _map.show_truth
		KEY_F3:
			_show_chunks = not _show_chunks
			_streamer.show_borders = _show_chunks
			_streamer.queue_redraw()
		KEY_F:
			_burn_fuel = not _burn_fuel
			_player.sim.burn_fuel = _burn_fuel
		KEY_BRACKETLEFT:
			_change_fuel(-DEBUG_FUEL_STEP)
		KEY_BRACKETRIGHT:
			_change_fuel(DEBUG_FUEL_STEP)


## Средняя кнопка мыши: щелчок без движения — возврат камеры,
## с Ctrl — запомнить стандартное положение, с Shift — сбросить его.
func _on_middle_button(button: InputEventMouseButton) -> void:
	if button.pressed:
		_middle_down = true
		_middle_dragging = false
		_middle_press_pos = button.position
		return
	if not _middle_down:
		return
	_middle_down = false
	_middle_release_msec = Time.get_ticks_msec()
	if _middle_dragging:
		return
	if button.ctrl_pressed:
		_camera.remember_standard()
	elif button.shift_pressed:
		_camera.reset_standard()
	else:
		_camera.quick_return()


## Движение с зажатой средней кнопкой сдвигает камеру относительно машины.
func _on_middle_motion(motion: InputEventMouseMotion) -> void:
	if not _middle_dragging:
		if motion.position.distance_to(_middle_press_pos) <= _camera.params.click_move_threshold:
			return
		_middle_dragging = true
	_camera.shift(motion.relative / get_viewport_rect().size)


## Левый клик по земле: основное направление — курс от машины к месту клика.
func _on_left_click(screen_pos: Vector2) -> void:
	var ground: Vector2 = _world.transform.affine_inverse() * screen_pos
	var east: float = ground.x - _player.state.x
	var north: float = -ground.y - _player.state.y
	if east * east + north * north < 4.0:
		return
	_player_input.set_course(_sim, rad_to_deg(atan2(east, north)))


## Правая кнопка мыши: пока зажата, видна зона клика; точка ставится
## при отпускании (или при нажатии, если так задано в параметрах камеры).
func _on_right_button(button: InputEventMouseButton) -> void:
	_right_down = button.pressed
	if button.pressed != _camera.params.point_on_release:
		_place_point(button)


func _place_point(button: InputEventMouseButton) -> void:
	var ground: Vector2 = _world.transform.affine_inverse() * button.position
	var rejected_before: int = _player.points_rejected
	_player_input.set_point(_sim, ground.x, -ground.y)
	if _player.points_rejected != rejected_before:
		# Курсор вне зоны: точка не ставится, звучит сигнал.
		_beeper.beep()
		return
	var mode: int = _camera.resolve_point_mode(button.ctrl_pressed, button.alt_pressed)
	_camera.begin_point(button.position / get_viewport_rect().size, mode, _player.point_distance())


## Точка, зона клика и камера при движении к точке. Вызывается каждый кадр.
func _update_point(car_pos: Vector2, viewport_size: Vector2, delta: float) -> void:
	var params: CarParams = _car_params
	if _player.points_passed != _seen_passed:
		_seen_passed = _player.points_passed
		_camera.end_point(true)
	if _player.points_dropped != _seen_dropped:
		# Точка стала недостижимой: сигнал и вспышка маркера.
		_seen_dropped = _player.points_dropped
		_camera.end_point(false)
		_point_view.flash(_last_point_pos)
		_beeper.beep()
	if _player.point_active:
		_last_point_pos = Vector2(_player.point_x, -_player.point_y)
		_camera.track_point(car_pos.distance_to(_last_point_pos), delta)
	_point_view.set_point(_player.point_active, _last_point_pos, params.point_pass_radius)

	if not _right_down:
		_point_view.hide_zone()
		return
	var state = _player.state
	var terrain = _terrain.sample(state.x, state.y)
	var autopilot = _player.autopilot
	var radius: float = autopilot.auto_turn_radius(_player.sim, state, terrain) * params.point_zone_margin
	var center: float = state.heading
	var half_angle: float = PI
	var max_range: float = _camera.params.zone_draw_range
	if _player.course_active:
		center = deg_to_rad(_player.course_deg)
		half_angle = deg_to_rad(params.point_sector_deg)
		max_range = params.point_max_range
	var cursor: Vector2 = _camera.world_transform(car_pos, viewport_size).affine_inverse() * get_viewport().get_mouse_position()
	var cursor_ok: bool = autopilot.point_allowed(_player.sim, state, terrain,
		_player.course_active, deg_to_rad(_player.course_deg), cursor.x, -cursor.y)
	_point_view.show_zone(car_pos, state.heading, radius, center, half_angle, max_range, cursor_ok)


## Колесо мыши: один щелчок — один шаг заданной скорости или расхода.
func _on_wheel(steps: int) -> void:
	# Пока открыта карта, заданную скорость менять нельзя: это цена взгляда
	# на карту (раздел 7.2).
	if _map.is_open:
		return
	if _middle_down:
		return
	if Time.get_ticks_msec() - _middle_release_msec < int(WHEEL_GUARD_TIME * 1000.0):
		return
	_player_input.adjust_target(_sim, steps)


func _store_previous() -> void:
	_prev_x = _player.state.x
	_prev_y = _player.state.y
	_prev_heading = _player.state.heading


## Отладка: изменить топливо на ходу, чтобы почувствовать массу.
func _change_fuel(delta_kg: float) -> void:
	_player.state.fuel = clampf(_player.state.fuel + delta_kg, 0.0, _car_params.fuel_capacity)
	_player.state.mass = _player.sim.total_mass(_player.state.fuel)


## Клавиша M: короткое нажатие открывает и закрывает карту; если держать
## клавишу, карта открыта, пока она нажата.
func _on_map_key(pressed: bool) -> void:
	if pressed:
		if _map.is_open:
			_map.set_open(false)
			_map_opened_msec = -1
		else:
			_map.set_open(true)
			_map_opened_msec = Time.get_ticks_msec()
	elif _map.is_open and _map_opened_msec >= 0:
		if Time.get_ticks_msec() - _map_opened_msec > 350:
			_map.set_open(false)
		_map_opened_msec = -1


## Экран перед стартом: стрелки вверх и вниз меняют заправку, Enter или
## пробел начинают заезд.
func _on_prestart_key(keycode: int) -> void:
	var params: WorldGenParams = _world_params
	match keycode:
		KEY_UP, KEY_RIGHT:
			_set_start_fuel(_chosen_fuel + params.start_fuel_step)
		KEY_DOWN, KEY_LEFT:
			_set_start_fuel(_chosen_fuel - params.start_fuel_step)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_prestart = false
			_map.set_open(false)
		KEY_T:
			_terrain_mode = (_terrain_mode + 1) % 4
			_apply_terrain_mode()
			_start_race()


func _set_start_fuel(fuel: float) -> void:
	_chosen_fuel = clampf(fuel, _world_params.start_fuel_min, _world_params.start_fuel_max)
	_player.state.fuel = _chosen_fuel
	_player.state.mass = _player.sim.total_mass(_chosen_fuel)


## Строка экрана перед стартом: заправка и что она значит в километрах.
func _prestart_text() -> String:
	var sim = _player.sim
	var reach_slow: float = sim.range_at_speed(90.0 / 3.6, _chosen_fuel, _surfaces[0]) / 1000.0
	var reach_fast: float = sim.range_at_speed(108.0 / 3.6, _chosen_fuel, _surfaces[0]) / 1000.0
	return "Заправка %d кг (стрелки вверх и вниз)     хватит на %.1f км при 90 км/ч, %.1f км при 108     маршрут %.0f км     Enter — старт" % [
		roundi(_chosen_fuel), reach_slow, reach_fast, _layout.route_length / 1000.0,
	]


## Контрольные точки, склады и ориентиры есть только на местности из генератора.
func _apply_stage() -> void:
	var params: WorldGenParams = _world_params
	if _terrain_mode == 0:
		_sim.checkpoints = _layout.checkpoints
		_sim.checkpoint_radius = _layout.checkpoint_radius
		_sim.world_state.setup(_layout.depots, params.depot_stock, params.depot_portion,
			params.depot_radius, params.depot_max_speed)
		_stage_view.set_layout(_layout)
	else:
		_sim.checkpoints = PackedVector2Array()
		_sim.world_state.setup(PackedVector2Array(), 0.0, 0.0, params.depot_radius, params.depot_max_speed)
		_stage_view.set_layout(null)
	_stage_view.set_next_checkpoint(0)


## Выбрать местность по _terrain_mode: генератор или отладочная плоскость.
func _apply_terrain_mode() -> void:
	if _terrain_mode == 0:
		_terrain = _generated
		_streamer.set_terrain(_generated)
		_streamer.visible = true
		_grid.visible = false
		RenderingServer.set_default_clear_color(_surfaces[0].color)
	else:
		_flat.set_surface(_surfaces[_terrain_mode - 1])
		_terrain = _flat
		_streamer.set_terrain(null)
		_streamer.visible = false
		_grid.visible = true
		RenderingServer.set_default_clear_color(_surfaces[_terrain_mode - 1].color)


func _surface_under_player() -> SurfaceParams:
	return _terrain.sample(_player.state.x, _player.state.y).surface


func _build_hud_text() -> String:
	var s = _player.state
	var sample = _terrain.sample(s.x, s.y)
	var surface: SurfaceParams = sample.surface
	var seconds: int = int(_sim.time_seconds())
	var hold_speed: bool = _player.target_mode == Command.TargetMode.SPEED

	# Экран заезда (раздел 7.4). В скобках — заданное значение того, что держит
	# автоматика; вторая величина меняется сама.
	var speed_note: String = "меняется сама"
	var rate_note: String = "меняется сам"
	var mode_text: String = "держать расход"
	if hold_speed:
		speed_note = "задано %d" % roundi(_player.target_value)
		mode_text = "держать скорость"
	else:
		rate_note = "задано %d" % roundi(_player.target_value)
	var control_text: String = ""
	if _player.is_manual_active():
		control_text = "     РУЧНОЕ"
	if _player.is_reversing():
		control_text += "     ЗАДНИЙ ХОД"
	if _player.blocked_left > 0.0:
		control_text = "     УДАР: управление заблокировано"
	elif _player.is_manual_active():
		if _player.auto_throttle:
			control_text = "     РУЛЬ ВРУЧНУЮ"
		elif _player.auto_steer:
			control_text = "     ГАЗ ВРУЧНУЮ"

	# Запас хода: если ехать дальше с этой скоростью по такому же покрытию.
	var range_text: String = "—"
	if s.speed() > 1.0 and s.fuel > 0.0:
		var range_m: float = _player.sim.range_at_speed(s.speed(), s.fuel, surface)
		if range_m < 1000000.0:
			range_text = "%.1f" % (range_m / 1000.0)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("режим: %s%s" % [mode_text, control_text])
	lines.append("скорость %d км/ч  (%s)" % [roundi(s.speed() * 3.6), speed_note])
	lines.append("расход %d кг/мин  (%s)" % [roundi(s.consumption), rate_note])
	lines.append("топливо %d кг     запас хода %s км     масса %d кг" % [
		roundi(s.fuel), range_text, roundi(s.mass),
	])
	var total: int = _sim.checkpoints.size()
	if total > 0:
		if _player.finish_step >= 0:
			var finish_seconds: int = int(_player.finish_step * RaceSim.DT)
			lines.append("ФИНИШ     время %d:%02d     осталось топлива %d кг" % [
				int(finish_seconds / 60.0), finish_seconds % 60, roundi(s.fuel),
			])
		else:
			lines.append("следующая контрольная точка: %d из %d" % [_player.next_checkpoint + 1, total])
	# Склад: остаток виден, только когда машина на нём стоит.
	var depot: int = _sim.world_state.depot_at(s.x, s.y)
	if depot >= 0:
		var depot_note: String = "сбросьте скорость ниже %d км/ч" % roundi(_world_params.depot_max_speed)
		if _player.depots_used.has(depot):
			depot_note = "порция уже взята"
		elif _sim.world_state.stock[depot] <= 0.0:
			depot_note = "склад пуст"
		lines.append("СКЛАД %d: осталось %d кг — %s" % [depot + 1, roundi(_sim.world_state.stock[depot]), depot_note])
	if _notice_left > 0.0:
		lines.append(_notice_text)
	var course_note: String = "не задан"
	if _player.course_active:
		course_note = "задан %d°" % roundi(_player.course_deg)
	lines.append("курс %.1f°  (%s)     одометр %.2f км     время %d:%02d" % [
		s.heading_deg(), course_note, (s.distance - _odometer_zero) / 1000.0, int(seconds / 60.0), seconds % 60,
	])
	var point_text: String = "нет"
	if _player.point_active:
		point_text = "поставлена"
	var return_text: String = "выключен"
	if _camera.auto_return:
		return_text = "включён"
	lines.append("точка: %s     камера для точки: режим %d (%s)     возврат камеры: %s" % [
		point_text, _camera.point_mode, POINT_MODE_NAMES[_camera.point_mode - 1], return_text,
	])
	if not _show_details:
		return "\n".join(lines)

	var burn_text: String = "включён"
	if not _burn_fuel:
		burn_text = "ВЫКЛЮЧЕН"
	lines.append("")
	var terrain_text: String = "из генератора"
	if _terrain_mode != 0:
		terrain_text = "отладочная плоскость"
	var grade: float = sample.grade_east * sin(s.heading) + sample.grade_north * cos(s.heading)
	var wind: float = sqrt(sample.wind_east * sample.wind_east + sample.wind_north * sample.wind_north)
	lines.append("местность: %s     покрытие: %s     уклон по ходу %.1f %%     ветер %.2f м/с²     ударов %d" % [
		terrain_text, surface.title, grade * 100.0, wind, _player.hits,
	])
	lines.append("зум %d (%d м по высоте экрана)     высота %d м     снос ветром %.1f м/с" % [
		_camera.zoom_index + 1, roundi(_camera.ground_height()), roundi(sample.height),
		sqrt(s.drift_east * s.drift_east + s.drift_north * s.drift_north),
	])
	if _show_chunks:
		lines.append("части: загружено %d, создаётся %d, последняя за %d мс" % [
			_streamer.loaded_count(), _streamer.pending_count(), _streamer.last_build_msec,
		])
	lines.append("мощность %d кВт     тяга %d Н     расход топлива %s" % [
		roundi(s.engine_power / 1000.0), roundi(s.thrust), burn_text,
	])
	lines.append("боковое ускорение %.1f м/с²: %d %% предела шин" % [
		absf(s.lateral_accel), roundi(s.lateral_ratio * 100.0),
	])
	lines.append("потеря скорости на манёвре %.1f м/с за секунду" % s.scrub_decel)
	lines.append("x %d м     y %d м     шаг %d" % [roundi(s.x), roundi(s.y), _sim.step_index])
	lines.append("")
	lines.append("колесо — заданное значение     Tab — скорость или расход     WASD — вручную     O — обнулить одометр")
	lines.append("левый клик — курс     Q E — курс ±1°     C — сбросить курс     M — карта     F1 — истинное положение на карте")
	lines.append("правая кнопка — точка (с Ctrl, Alt — перенос на экране)     X — убрать точку     V — режим камеры     H — возврат камеры")
	lines.append("1 2 3 — зум     стрелки или средняя кнопка — сдвиг камеры     щелчок средней — вернуть камеру")
	lines.append("[ ] — топливо ±50 кг     T — местность или плоскость     F — расход топлива     R — заново     F2 — скрыть     F3 — части")
	return "\n".join(lines)
