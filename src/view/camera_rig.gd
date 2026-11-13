extends RefCounted
## Камера: вид строго сверху, север вверху, без поворота (раздел 7.1).
##
## Камера хранит не своё положение, а место машины на экране в долях экрана
## (car_frac): (0.5, 0.75) — центр по горизонтали и четверть высоты от низа.
## Отсюда следует всё остальное: сдвиг меняет car_frac, зум его не трогает,
## и результат не зависит от разрешения.
##
## Камера не входит в симуляцию и не записывается в повтор.

const CameraParams = preload("res://src/view/camera_params.gd")

const SETTINGS_PATH: String = "user://zsr_settings.cfg"
const SETTINGS_SECTION: String = "camera"

var params: CameraParams
var zoom_index: int = 1
## Стандартное положение машины на экране, доли экрана.
var standard_frac: Vector2 = Vector2(0.5, 0.75)
## Текущее положение машины на экране, доли экрана.
var car_frac: Vector2 = Vector2(0.5, 0.75)
## Сколько ещё показывать метку стандартного положения, с.
var marker_time_left: float = 0.0

## Основной режим камеры для точки (раздел 7.1.1): 1 следование,
## 2 по горизонтали, 3 по вертикали, 4 полный.
var point_mode: int = 1
## Возврат в стандартное положение после каждой точки.
var auto_return: bool = false

var _persist: bool = true
var _point_tracking: bool = false
var _point_start: Vector2 = Vector2.ZERO
var _point_target: Vector2 = Vector2.ZERO
var _point_start_distance: float = 1.0
var _anim_active: bool = false
var _anim_from: Vector2 = Vector2.ZERO
var _anim_to: Vector2 = Vector2.ZERO
var _anim_duration: float = 0.0
var _anim_elapsed: float = 0.0


## persist = false отключает чтение и запись настроек (для тестов).
func _init(p_params: CameraParams, persist: bool = true) -> void:
	params = p_params
	_persist = persist
	zoom_index = clampi(params.start_zoom_index, 0, params.zoom_heights.size() - 1)
	standard_frac = clamp_frac(params.default_car_frac)
	point_mode = clampi(params.point_mode_start, 1, 4)
	if _persist:
		_load_settings()
	car_frac = standard_frac


## Ограничение: машина не ближе edge_margin к любому краю экрана.
func clamp_frac(frac: Vector2) -> Vector2:
	var margin: float = params.edge_margin
	return Vector2(clampf(frac.x, margin, 1.0 - margin), clampf(frac.y, margin, 1.0 - margin))


## Высота экрана на местности при текущем зуме, м.
func ground_height() -> float:
	return params.zoom_heights[zoom_index]


func pixels_per_meter(viewport_size: Vector2) -> float:
	return viewport_size.y / ground_height()


## Зум переключается мгновенно; положение машины на экране сохраняется.
func set_zoom_index(index: int) -> void:
	zoom_index = clampi(index, 0, params.zoom_heights.size() - 1)


## Сдвинуть машину на экране на delta долей экрана. Ручной сдвиг отменяет возврат.
func shift(delta_frac: Vector2) -> void:
	_anim_active = false
	_point_tracking = false
	car_frac = clamp_frac(car_frac + delta_frac)


## Плавно вернуть машину в стандартное положение за duration секунд.
func return_to_standard(duration: float) -> void:
	if duration <= 0.0:
		_anim_active = false
		car_frac = standard_frac
		return
	_anim_active = true
	_anim_from = car_frac
	_anim_to = standard_frac
	_anim_duration = duration
	_anim_elapsed = 0.0


func quick_return() -> void:
	_point_tracking = false
	return_to_standard(params.quick_return_time)


# --- Камера при движении к точке (раздел 7.1.1) ------------------------------

## Режим для одного клика: Ctrl означает «горизонталь наоборот»,
## Alt — «вертикаль наоборот» относительно основного режима.
func resolve_point_mode(ctrl: bool, alt: bool) -> int:
	var horizontal: bool = point_mode == 2 or point_mode == 4
	var vertical: bool = point_mode == 3 or point_mode == 4
	if ctrl:
		horizontal = not horizontal
	if alt:
		vertical = not vertical
	var mode: int = 1
	if horizontal:
		mode += 1
	if vertical:
		mode += 2
	return mode


## V: следующий основной режим по кругу.
func cycle_point_mode() -> void:
	point_mode = point_mode % 4 + 1
	_save_settings()


## H: включить или выключить возврат камеры после точки.
func toggle_auto_return() -> void:
	auto_return = not auto_return
	_save_settings()


## Точка поставлена. cursor_frac — место курсора на экране в долях экрана,
## mode — режим этого клика, distance — расстояние от машины до точки, м.
func begin_point(cursor_frac: Vector2, mode: int, distance: float) -> void:
	_anim_active = false
	_point_start = car_frac
	var target: Vector2 = car_frac
	if mode == 2 or mode == 4:
		target.x = cursor_frac.x
	if mode == 3 or mode == 4:
		target.y = cursor_frac.y
	_point_target = clamp_frac(target)
	_point_start_distance = maxf(distance, 0.001)
	_point_tracking = mode != 1


## Вызывается каждый кадр, пока точка стоит: distance — расстояние до неё, м.
## Машина на экране = старт + (цель - старт) · p, где p растёт от 0 до 1
## по мере приближения к точке.
func track_point(distance: float, delta: float) -> void:
	if not _point_tracking:
		return
	var progress: float = clampf(1.0 - distance / _point_start_distance, 0.0, 1.0)
	var wanted: Vector2 = _point_start.lerp(_point_target, progress)
	var blend: float = 1.0
	if params.point_smooth_time > 0.0:
		blend = 1.0 - exp(-delta / params.point_smooth_time)
	car_frac = car_frac.lerp(wanted, blend)


## Точка пройдена (passed = true), снята или стала недостижимой.
func end_point(passed: bool) -> void:
	var was_tracking: bool = _point_tracking
	_point_tracking = false
	if auto_return:
		return_to_standard(params.auto_return_time)
	elif passed and was_tracking:
		_animate(car_frac, _point_target, params.quick_return_time)


func is_tracking_point() -> bool:
	return _point_tracking


func _animate(from: Vector2, to: Vector2, duration: float) -> void:
	_anim_active = true
	_anim_from = from
	_anim_to = to
	_anim_duration = maxf(duration, 0.001)
	_anim_elapsed = 0.0


## Запомнить текущее положение машины на экране как стандартное.
func remember_standard() -> void:
	_anim_active = false
	standard_frac = clamp_frac(car_frac)
	marker_time_left = params.marker_time
	_save_settings()


## Сбросить стандартное положение к изначальному и перейти туда.
func reset_standard() -> void:
	standard_frac = clamp_frac(params.default_car_frac)
	marker_time_left = params.marker_time
	_save_settings()
	quick_return()


## Вызывается каждый кадр.
func update(delta: float) -> void:
	if marker_time_left > 0.0:
		marker_time_left = maxf(0.0, marker_time_left - delta)
	if _anim_active:
		_anim_elapsed += delta
		var t: float = clampf(_anim_elapsed / _anim_duration, 0.0, 1.0)
		car_frac = _anim_from.lerp(_anim_to, smoothstep(0.0, 1.0, t))
		if t >= 1.0:
			_anim_active = false


## Преобразование «мир → экран» для узла мира. car_pos — положение машины
## в координатах Godot (x — восток, y — юг), viewport_size — размер экрана.
func world_transform(car_pos: Vector2, viewport_size: Vector2) -> Transform2D:
	var ppm: float = pixels_per_meter(viewport_size)
	var origin: Vector2 = viewport_size * car_frac - car_pos * ppm
	return Transform2D(Vector2(ppm, 0.0), Vector2(0.0, ppm), origin)


## Видимая часть мира в координатах Godot.
func visible_world_rect(car_pos: Vector2, viewport_size: Vector2) -> Rect2:
	var ppm: float = pixels_per_meter(viewport_size)
	return Rect2(car_pos - viewport_size * car_frac / ppm, viewport_size / ppm)


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved: Variant = config.get_value(SETTINGS_SECTION, "standard_frac", null)
	if saved is Vector2:
		standard_frac = clamp_frac(saved)
	var saved_mode: Variant = config.get_value(SETTINGS_SECTION, "point_mode", null)
	if saved_mode is int:
		point_mode = clampi(saved_mode, 1, 4)
	var saved_return: Variant = config.get_value(SETTINGS_SECTION, "auto_return", null)
	if saved_return is bool:
		auto_return = saved_return


func _save_settings() -> void:
	if not _persist:
		return
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, "standard_frac", standard_frac)
	config.set_value(SETTINGS_SECTION, "point_mode", point_mode)
	config.set_value(SETTINGS_SECTION, "auto_return", auto_return)
	config.save(SETTINGS_PATH)
