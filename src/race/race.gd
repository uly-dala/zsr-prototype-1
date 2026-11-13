extends Node2D
## Сцена заезда.
##
## Шаг 1 дизайн-документа: одна машина на пустой плоскости, WASD,
## силы и масса, сдвиг и зум камеры.
##
## Узел только связывает части между собой:
##   ввод игрока -> команды -> RaceSim (фиксированный шаг 60 раз в секунду)
##   состояние машины -> камера, изображение, экран, запись.

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const FlatTerrain = preload("res://src/sim/flat_terrain.gd")
const RaceSim = preload("res://src/race/race_sim.gd")
const Car = preload("res://src/race/car.gd")
const Recorder = preload("res://src/race/recorder.gd")
const PlayerInput = preload("res://src/input/player_input.gd")
const CameraParams = preload("res://src/view/camera_params.gd")
const CameraRig = preload("res://src/view/camera_rig.gd")
const GroundGrid = preload("res://src/view/ground_grid.gd")
const CarView = preload("res://src/view/car_view.gd")
const TrailView = preload("res://src/view/trail_view.gd")
const Hud = preload("res://src/ui/hud.gd")

const CAR_PARAMS_PATH: String = "res://data/car_default.tres"
const CAMERA_PARAMS_PATH: String = "res://data/camera_default.tres"
const SURFACE_PATHS: Array = [
	"res://data/surface_hard.tres",
	"res://data/surface_sand.tres",
	"res://data/surface_slick.tres",
]
## Точка следа ставится раз в столько шагов.
const TRAIL_EVERY: int = 6
## Отладка: шаг изменения топлива клавишами [ и ], кг.
const DEBUG_FUEL_STEP: float = 50.0

## Топливо на старте, кг. 250 кг — полбака, «средняя масса» из документа.
@export_range(0.0, 500.0, 50.0) var start_fuel: float = 250.0
## Шагов симуляции за один тик: 1 — обычное время, 4 и 16 — ускорение.
@export_range(1, 16) var steps_per_tick: int = 1

var _car_params: CarParams
var _surfaces: Array = []
var _surface_index: int = 0
var _burn_fuel: bool = true

var _terrain: FlatTerrain
var _sim: RaceSim
var _player: Car
var _player_input: PlayerInput
var _recorder: Recorder = Recorder.new()
var _camera: CameraRig

var _world: Node2D
var _grid: GroundGrid
var _trail: TrailView
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


func _ready() -> void:
	_car_params = load(CAR_PARAMS_PATH) as CarParams
	var camera_params: CameraParams = load(CAMERA_PARAMS_PATH) as CameraParams
	for path in SURFACE_PATHS:
		_surfaces.append(load(path))
	assert(_car_params != null, "Не загружен файл параметров машины")
	assert(camera_params != null, "Не загружен файл параметров камеры")
	_camera = CameraRig.new(camera_params)

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_grid = GroundGrid.new()
	_grid.name = "GroundGrid"
	_world.add_child(_grid)
	_trail = TrailView.new()
	_trail.name = "Trail"
	_world.add_child(_trail)
	_car_view = CarView.new()
	_car_view.name = "PlayerCar"
	_world.add_child(_car_view)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_hud = Hud.new()
	_hud.name = "Hud"
	layer.add_child(_hud)

	_start_race()


func _exit_tree() -> void:
	_recorder.stop()


## Начать заезд заново: машина в начале координат, носом на север.
func _start_race() -> void:
	_terrain = FlatTerrain.new(_surfaces[_surface_index])
	_sim = RaceSim.new(_terrain)
	_player = _sim.add_car(_car_params, start_fuel, 0.0, 0.0, 0.0)
	_player.sim.burn_fuel = _burn_fuel
	_player_input = PlayerInput.new(_player.id)
	_store_previous()
	_trail.clear()
	_trail.add_point(Vector2.ZERO)
	_recorder.start()
	_apply_surface_look()


func _physics_process(_delta: float) -> void:
	for _i in steps_per_tick:
		_player_input.poll(_sim)
		_store_previous()
		_sim.step()
		_recorder.sample(_sim.step_index, _sim.time_seconds(), _player, _terrain.get_surface().id, false)
		if _sim.step_index % TRAIL_EVERY == 0:
			_trail.add_point(Vector2(_player.state.x, -_player.state.y))


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
	if shift != Vector2.ZERO:
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
	_world.transform = _camera.world_transform(car_pos, viewport_size)
	_grid.visible_rect = _camera.visible_world_rect(car_pos, viewport_size)
	_grid.queue_redraw()

	_hud.set_marker(_camera.marker_time_left > 0.0, _camera.standard_frac)
	_hud.set_lines(_build_hud_text())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			_on_key(key.physical_keycode)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_on_middle_button(button)
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
		KEY_R:
			_start_race()
		KEY_T:
			_surface_index = (_surface_index + 1) % _surfaces.size()
			_terrain.set_surface(_surfaces[_surface_index])
			_apply_surface_look()
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


func _store_previous() -> void:
	_prev_x = _player.state.x
	_prev_y = _player.state.y
	_prev_heading = _player.state.heading


## Отладка: изменить топливо на ходу, чтобы почувствовать массу.
func _change_fuel(delta_kg: float) -> void:
	_player.state.fuel = clampf(_player.state.fuel + delta_kg, 0.0, _car_params.fuel_capacity)
	_player.state.mass = _player.sim.total_mass(_player.state.fuel)


func _apply_surface_look() -> void:
	var surface: SurfaceParams = _terrain.get_surface()
	RenderingServer.set_default_clear_color(surface.color)


func _build_hud_text() -> String:
	var s = _player.state
	var surface: SurfaceParams = _terrain.get_surface()
	var seconds: int = int(_sim.time_seconds())
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d км/ч     курс %.1f°     топливо %d кг     масса %d кг" % [
		roundi(s.speed() * 3.6), s.heading_deg(), roundi(s.fuel), roundi(s.mass),
	])
	lines.append("расход %d кг/мин     время %d:%02d     путь %.2f км" % [
		roundi(s.consumption), int(seconds / 60.0), seconds % 60, s.distance / 1000.0,
	])
	lines.append("покрытие: %s     зум %d (%d м по высоте экрана)" % [
		surface.title, _camera.zoom_index + 1, roundi(_camera.ground_height()),
	])
	if not _show_details:
		return "\n".join(lines)

	var burn_text: String = "включён"
	if not _burn_fuel:
		burn_text = "ВЫКЛЮЧЕН"
	lines.append("")
	lines.append("мощность %d кВт     тяга %d Н     расход топлива %s" % [
		roundi(s.engine_power / 1000.0), roundi(s.thrust), burn_text,
	])
	lines.append("боковое ускорение %.1f м/с²: %d %% предела шин" % [
		absf(s.lateral_accel), roundi(s.lateral_ratio * 100.0),
	])
	lines.append("потеря скорости на манёвре %.1f м/с за секунду" % s.scrub_decel)
	lines.append("x %d м     y %d м     шаг %d" % [roundi(s.x), roundi(s.y), _sim.step_index])
	lines.append("")
	lines.append("WASD — машина     1 2 3 — зум     стрелки или средняя кнопка — сдвиг камеры")
	lines.append("щелчок средней — вернуть камеру     Ctrl+щелчок — запомнить     Shift+щелчок — сбросить")
	lines.append("[ ] — топливо ±50 кг     T — покрытие     F — расход топлива     R — заново     F2 — скрыть")
	return "\n".join(lines)
