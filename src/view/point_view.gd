extends Node2D
## Точка на земле и зона, куда её можно поставить (раздел 3.4).
## Зона — полупрозрачная заливка, пока зажата правая кнопка мыши;
## пересчитывается каждый кадр: чем выше скорость и масса, тем она уже и дальше.
##
## Все координаты — Godot (x — восток, y — юг), углы — курс в радианах
## (0 — север, по часовой стрелке).

const SLICES_SECTOR: int = 48
const SLICES_FULL: int = 96
const FLASH_TIME: float = 0.5

var zone_color: Color = Color(0.45, 1.0, 0.6, 0.16)
var zone_bad_color: Color = Color(1.0, 0.4, 0.3, 0.16)
var point_color: Color = Color(0.5, 1.0, 0.65, 0.95)
var flash_color: Color = Color(1.0, 0.35, 0.25, 1.0)

# Зона.
var _zone_shown: bool = false
var _zone_origin: Vector2 = Vector2.ZERO
var _zone_heading: float = 0.0
var _zone_radius: float = 6.0
var _zone_center: float = 0.0
var _zone_half_angle: float = PI
var _zone_range: float = 400.0
var _zone_cursor_ok: bool = true
# Точка.
var _point_shown: bool = false
var _point_pos: Vector2 = Vector2.ZERO
var _point_radius: float = 5.0
# Вспышка маркера снятой точки.
var _flash_left: float = 0.0
var _flash_pos: Vector2 = Vector2.ZERO


func hide_zone() -> void:
	if _zone_shown:
		_zone_shown = false
		queue_redraw()


## origin — машина, heading — её курс, radius — радиус поворота для зоны,
## center и half_angle — сектор (при half_angle = PI сектора нет),
## max_range — дальняя граница, cursor_ok — можно ли поставить точку под курсором.
func show_zone(origin: Vector2, heading: float, radius: float, center: float,
		half_angle: float, max_range: float, cursor_ok: bool) -> void:
	_zone_shown = true
	_zone_origin = origin
	_zone_heading = heading
	_zone_radius = radius
	_zone_center = center
	_zone_half_angle = half_angle
	_zone_range = max_range
	_zone_cursor_ok = cursor_ok
	queue_redraw()


func set_point(shown: bool, pos: Vector2, radius: float) -> void:
	if shown == _point_shown and pos == _point_pos:
		return
	_point_shown = shown
	_point_pos = pos
	_point_radius = radius
	queue_redraw()


## Вспышка на месте точки, ставшей недостижимой.
func flash(pos: Vector2) -> void:
	_flash_pos = pos
	_flash_left = FLASH_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		queue_redraw()


func _draw() -> void:
	if _zone_shown:
		_draw_zone()
	if _point_shown:
		draw_arc(_point_pos, _point_radius, 0.0, TAU, 32, point_color)
		draw_line(_point_pos + Vector2(-1.5, 0.0), _point_pos + Vector2(1.5, 0.0), point_color)
		draw_line(_point_pos + Vector2(0.0, -1.5), _point_pos + Vector2(0.0, 1.5), point_color)
	if _flash_left > 0.0:
		var t: float = 1.0 - _flash_left / FLASH_TIME
		var color: Color = flash_color
		color.a = 1.0 - t
		draw_arc(_flash_pos, _point_radius * (1.0 + 2.0 * t), 0.0, TAU, 32, color)
		draw_arc(_flash_pos, _point_radius * (0.5 + t), 0.0, TAU, 32, color)


## Зона режется лучами от машины. Вдоль каждого луча допустим отрезок
## от хорды окружности поворота до дальней границы.
func _draw_zone() -> void:
	var slices: int = SLICES_SECTOR
	if _zone_half_angle >= PI:
		slices = SLICES_FULL
	var colors: PackedColorArray = PackedColorArray([zone_color])
	if not _zone_cursor_ok:
		colors = PackedColorArray([zone_bad_color])
	var no_uvs: PackedVector2Array = PackedVector2Array()
	var prev_inner: Vector2 = Vector2.ZERO
	var prev_outer: Vector2 = Vector2.ZERO
	var prev_open: bool = false
	for i in slices + 1:
		var angle: float = _zone_center - _zone_half_angle + 2.0 * _zone_half_angle * i / slices
		var direction: Vector2 = Vector2(sin(angle), -cos(angle))
		var near: float = 2.0 * _zone_radius * sin(absf(wrapf(angle - _zone_heading, -PI, PI)))
		var is_open: bool = near < _zone_range
		var inner: Vector2 = _zone_origin + direction * minf(near, _zone_range)
		var outer: Vector2 = _zone_origin + direction * _zone_range
		if i > 0 and (is_open or prev_open):
			if not prev_inner.is_equal_approx(prev_outer):
				draw_primitive(PackedVector2Array([prev_inner, prev_outer, outer]), colors, no_uvs)
			if not inner.is_equal_approx(outer) and not prev_inner.is_equal_approx(inner):
				draw_primitive(PackedVector2Array([prev_inner, outer, inner]), colors, no_uvs)
		prev_inner = inner
		prev_outer = outer
		prev_open = is_open
