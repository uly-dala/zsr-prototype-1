extends Control
## Карта заезда (раздел 7.2). Открывается поверх игры, гонка не останавливается.
##
## Показывает: рельеф, покрытия, контрольные точки, ориентиры, стрелки ветра
## и сетку. Не показывает: положение игрока, соперников и препятствия.
##
## Пока карта открыта: левая кнопка мыши тянет карту, колесо меняет масштаб,
## правая кнопка тянет линейку — курс в градусах и расстояние в километрах.
##
## Координаты мира: x — восток, y — север, метры.

const LandmarkArt = preload("res://src/view/landmark_art.gd")

## Доля экрана, которую занимает карта: по ширине и по высоте.
const SCREEN_SHARE: Vector2 = Vector2(0.6, 0.9)
const MAX_ZOOM: float = 8.0
const ZOOM_STEP: float = 1.25
## Сколько секунд на карте видна отметка «вы здесь» после контрольной точки.
const HERE_TIME: float = 5.0

var is_open: bool = false
## Отладка (F1): показывать истинное положение и путь.
var show_truth: bool = false
var true_position: Vector2 = Vector2.ZERO
var true_trail: PackedVector2Array = PackedVector2Array()

var _canvas: Control
var _layout = null
var _terrain = null
var _texture: Texture2D = null
var _area_min: Vector2 = Vector2.ZERO
var _area_max: Vector2 = Vector2(1000.0, 1000.0)
var _grid_step: float = 500.0
## Центр вида в мире и масштаб: пикселей на метр.
var _center: Vector2 = Vector2.ZERO
var _scale: float = 0.05
var _fit_scale: float = 0.05
var _fitted: bool = false
var _dragging: bool = false
var _ruler_shown: bool = false
var _ruler_dragging: bool = false
var _ruler_from: Vector2 = Vector2.ZERO
var _ruler_to: Vector2 = Vector2.ZERO
var _here_left: float = 0.0
var _here_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)


## Задать этап: слой данных, объекты и границы местности.
func setup(terrain, layout, area_min: Vector2, area_max: Vector2, grid_step: float) -> void:
	_terrain = terrain
	_layout = layout
	_area_min = area_min
	_area_max = area_max
	_grid_step = grid_step
	_texture = null
	_fitted = false
	_ruler_shown = false
	_here_left = 0.0


## Картинка карты готова.
func set_texture(texture: Texture2D) -> void:
	_texture = texture
	_canvas.queue_redraw()


func set_open(open_now: bool) -> void:
	is_open = open_now
	visible = open_now
	_dragging = false
	_ruler_dragging = false
	if not open_now:
		_ruler_shown = false


## Контрольная точка пройдена: на карте на 5 секунд вспыхивает «вы здесь».
func flash_here(position_world: Vector2) -> void:
	_here_position = position_world
	_here_left = HERE_TIME


## Вызывается каждый кадр: место на экране и анимация.
func update_view(viewport_size: Vector2, delta: float) -> void:
	if _here_left > 0.0:
		_here_left = maxf(0.0, _here_left - delta)
	if not is_open:
		return
	size = viewport_size * SCREEN_SHARE
	position = (viewport_size - size) * 0.5
	if not _fitted and size.x > 0.0:
		_fit()
	_canvas.queue_redraw()


## Курс от одного места к другому, градусы от 0 до 360.
static func ruler_course(from: Vector2, to: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(to.x - from.x, to.y - from.y)), 360.0)


## Расстояние между местами, км.
static func ruler_distance_km(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to) / 1000.0


## Мир -> карта на экране.
func to_screen(world: Vector2) -> Vector2:
	return size * 0.5 + Vector2(world.x - _center.x, -(world.y - _center.y)) * _scale


## Карта на экране -> мир.
func to_world(screen: Vector2) -> Vector2:
	var offset: Vector2 = (screen - size * 0.5) / _scale
	return Vector2(_center.x + offset.x, _center.y - offset.y)


## Вся местность целиком помещается в окно карты.
func _fit() -> void:
	var area: Vector2 = _area_max - _area_min
	_fit_scale = minf(size.x / area.x, size.y / area.y)
	_scale = _fit_scale
	_center = (_area_min + _area_max) * 0.5
	_fitted = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_ruler_dragging = button.pressed
			if button.pressed:
				_ruler_from = to_world(button.position)
				_ruler_to = _ruler_from
				_ruler_shown = true
			else:
				_ruler_to = to_world(button.position)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(ZOOM_STEP, button.position)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / ZOOM_STEP, button.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _dragging:
			_center += Vector2(-motion.relative.x, motion.relative.y) / _scale
			_keep_in_area()
		if _ruler_dragging:
			_ruler_to = to_world(motion.position)
		accept_event()


## Масштаб меняется вокруг курсора: место под ним остаётся на месте.
func _zoom(factor: float, cursor: Vector2) -> void:
	var anchor: Vector2 = to_world(cursor)
	_scale = clampf(_scale * factor, _fit_scale, _fit_scale * MAX_ZOOM)
	var moved: Vector2 = to_world(cursor)
	_center += anchor - moved
	_keep_in_area()


func _keep_in_area() -> void:
	_center.x = clampf(_center.x, _area_min.x, _area_max.x)
	_center.y = clampf(_center.y, _area_min.y, _area_max.y)


# --- Рисование ----------------------------------------------------------------

func _draw_map() -> void:
	var font: Font = get_theme_default_font()
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.06, 0.96))
	if _texture == null:
		_canvas.draw_string(font, Vector2(24.0, 40.0), "Карта строится…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22)
		return
	var top_left: Vector2 = to_screen(Vector2(_area_min.x, _area_max.y))
	_canvas.draw_texture_rect(_texture, Rect2(top_left, (_area_max - _area_min) * _scale), false)
	_draw_grid()
	_draw_wind(font)
	_draw_landmarks(font)
	_draw_checkpoints(font)
	_draw_ruler(font)
	_draw_here(font)
	if show_truth:
		_draw_truth()
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.85, 0.7, 0.8), false, 2.0)
	_canvas.draw_string(font, Vector2(14.0, size.y - 14.0),
		"левая кнопка — двигать     колесо — масштаб     правая кнопка — линейка     сетка %d м" % int(_grid_step),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1.0, 1.0, 1.0, 0.75))


func _draw_grid() -> void:
	var color: Color = Color(1.0, 1.0, 1.0, 0.10)
	var bold: Color = Color(1.0, 1.0, 1.0, 0.22)
	var first: int = int(ceil(_area_min.x / _grid_step))
	var last: int = int(floor(_area_max.x / _grid_step))
	for line in range(first, last + 1):
		var x: float = line * _grid_step
		var line_color: Color = color
		if line % 2 == 0:
			line_color = bold
		_canvas.draw_line(to_screen(Vector2(x, _area_min.y)), to_screen(Vector2(x, _area_max.y)), line_color)
	first = int(ceil(_area_min.y / _grid_step))
	last = int(floor(_area_max.y / _grid_step))
	for line in range(first, last + 1):
		var y: float = line * _grid_step
		var line_color: Color = color
		if line % 2 == 0:
			line_color = bold
		_canvas.draw_line(to_screen(Vector2(_area_min.x, y)), to_screen(Vector2(_area_max.x, y)), line_color)


## Стрелка ветра в центре каждого скользкого поля: куда сносит и как сильно.
func _draw_wind(font: Font) -> void:
	if _terrain == null:
		return
	var color: Color = Color(0.1, 0.2, 0.35, 0.95)
	for field in _terrain.field_count():
		var circle: Vector3 = _terrain.field_circle(field)
		var wind: Vector2 = _terrain.field_wind(field)
		var strength: float = wind.length()
		if strength <= 0.0:
			continue
		var center: Vector2 = to_screen(Vector2(circle.x, circle.y))
		var direction: Vector2 = Vector2(wind.x, -wind.y) / strength
		var length: float = 14.0 + 40.0 * strength
		var tail: Vector2 = center - direction * length * 0.5
		var head: Vector2 = center + direction * length * 0.5
		var side: Vector2 = Vector2(-direction.y, direction.x)
		_canvas.draw_line(tail, head, color, 2.0)
		_canvas.draw_line(head, head - direction * 7.0 + side * 5.0, color, 2.0)
		_canvas.draw_line(head, head - direction * 7.0 - side * 5.0, color, 2.0)
		_canvas.draw_string(font, center + Vector2(8.0, 18.0), "%.1f" % strength, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)


func _draw_landmarks(font: Font) -> void:
	if _layout == null:
		return
	for landmark in _layout.landmarks:
		var center: Vector2 = to_screen(Vector2(landmark["x"], landmark["y"]))
		# Значок не меньше 7 пикселей, чтобы читался на общем виде.
		var icon_size: float = maxf(landmark["size"] * _scale, 7.0)
		LandmarkArt.draw(_canvas, landmark["kind"], center, icon_size, landmark["angle"])
		_canvas.draw_string(font, center + Vector2(icon_size + 4.0, 5.0), landmark["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 1.0, 1.0, 0.85))


func _draw_checkpoints(font: Font) -> void:
	if _layout == null:
		return
	var color: Color = Color(1.0, 0.85, 0.3)
	var start: Vector2 = to_screen(_layout.start)
	_canvas.draw_circle(start, 5.0, color)
	_canvas.draw_string(font, start + Vector2(9.0, 5.0), "Старт", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
	for i in _layout.checkpoints.size():
		var center: Vector2 = to_screen(_layout.checkpoints[i])
		var radius: float = maxf(_layout.checkpoint_radius * _scale, 6.0)
		_canvas.draw_arc(center, radius, 0.0, TAU, 32, color, 2.0)
		var label: String = str(i + 1)
		if i == _layout.checkpoints.size() - 1:
			label = "%d Финиш" % (i + 1)
		_canvas.draw_string(font, center + Vector2(radius + 4.0, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, color)


func _draw_ruler(font: Font) -> void:
	if not _ruler_shown:
		return
	var color: Color = Color(0.5, 1.0, 1.0)
	var from: Vector2 = to_screen(_ruler_from)
	var to: Vector2 = to_screen(_ruler_to)
	_canvas.draw_line(from, to, color, 2.0)
	_canvas.draw_circle(from, 3.0, color)
	_canvas.draw_circle(to, 3.0, color)
	if _ruler_from.distance_to(_ruler_to) < 1.0:
		return
	var label: String = "курс %d°   %.2f км" % [
		roundi(ruler_course(_ruler_from, _ruler_to)) % 360, ruler_distance_km(_ruler_from, _ruler_to),
	]
	_canvas.draw_string(font, to + Vector2(10.0, -8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, color)


func _draw_here(font: Font) -> void:
	if _here_left <= 0.0:
		return
	var color: Color = Color(1.0, 0.4, 0.3)
	var center: Vector2 = to_screen(_here_position)
	var pulse: float = 0.5 + 0.5 * sin(_here_left * 8.0)
	_canvas.draw_circle(center, 5.0, color)
	_canvas.draw_arc(center, 10.0 + 6.0 * pulse, 0.0, TAU, 24, color, 2.0)
	_canvas.draw_string(font, center + Vector2(18.0, -10.0), "вы здесь", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, color)


func _draw_truth() -> void:
	var color: Color = Color(1.0, 0.3, 0.9)
	if true_trail.size() >= 2:
		var points: PackedVector2Array = PackedVector2Array()
		points.resize(true_trail.size())
		for i in true_trail.size():
			points[i] = to_screen(true_trail[i])
		_canvas.draw_polyline(points, color, 1.5)
	_canvas.draw_circle(to_screen(true_position), 4.0, color)
