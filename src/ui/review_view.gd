extends Control
## Разбор после финиша (раздел 7.5): итог заезда, время и путь по отрезкам,
## графики топлива и скорости. Карта с истинным путём стоит слева, её рисует
## MapView. Главный инструмент обучения: игрок видит, где его представление
## о пути разошлось с действительностью.

const RaceLog = preload("res://src/race/race_log.gd")

## Доля ширины экрана, которую слева занимает карта.
const MAP_SHARE: float = 0.62

var _log: RaceLog = null
var _title: String = ""
var _lines: PackedStringArray = PackedStringArray()


## Строка внизу: что делают клавиши.
var footer: String = "R или Enter — новый заезд"


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## title — итог одной строкой; lines — строки итогов под ним.
func show_review(race_log: RaceLog, title: String, lines: PackedStringArray) -> void:
	_log = race_log
	_title = title
	_lines = lines
	visible = true
	queue_redraw()


func hide_review() -> void:
	visible = false
	_log = null


func _draw() -> void:
	if _log == null:
		return
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.03, 0.82))
	var left: float = size.x * MAP_SHARE + 24.0
	var width: float = size.x - left - 24.0
	var y: float = 64.0
	draw_string(font, Vector2(left, y), _title, HORIZONTAL_ALIGNMENT_LEFT, width, 30, Color(1.0, 0.9, 0.5))
	y += 18.0
	for line in _lines:
		y += 21.0
		draw_string(font, Vector2(left, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, 16, Color(0.95, 0.93, 0.88))
	y += 30.0
	var chart_height: float = clampf((size.y - y - 130.0) * 0.5, 60.0, 220.0)
	_draw_chart(font, Rect2(left, y, width, chart_height), _log.fuel, "топливо, кг", Color(0.4, 0.85, 1.0))
	y += chart_height + 46.0
	_draw_chart(font, Rect2(left, y, width, chart_height), _log.speed, "скорость, км/ч", Color(0.6, 1.0, 0.6))
	y += chart_height + 30.0
	draw_string(font, Vector2(left, y), "удар — красная черта     заправка — синяя     контрольная точка — жёлтая",
		HORIZONTAL_ALIGNMENT_LEFT, width, 15, Color(1.0, 1.0, 1.0, 0.7))
	draw_string(font, Vector2(left, size.y - 28.0), footer,
		HORIZONTAL_ALIGNMENT_LEFT, width, 20, Color(1.0, 0.9, 0.5))


## График величины по времени заезда с отметками событий.
func _draw_chart(font: Font, rect: Rect2, values: PackedFloat32Array, caption: String, color: Color) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.25), false, 1.0)
	var count: int = values.size()
	if count < 2:
		return
	var total_time: float = maxf(_log.times[count - 1], 1.0)
	var top: float = 1.0
	for value in values:
		top = maxf(top, value)
	top = ceil(top / 50.0) * 50.0
	for event in _log.events:
		var event_color: Color = Color(0.0, 0.0, 0.0, 0.0)
		if event["kind"] == "hit":
			event_color = Color(1.0, 0.3, 0.25, 0.8)
		elif event["kind"] == "refuel":
			event_color = Color(0.35, 0.6, 1.0, 0.9)
		elif event["kind"] == "checkpoint":
			event_color = Color(1.0, 0.85, 0.3, 0.8)
		else:
			continue
		var x: float = rect.position.x + rect.size.x * event["time"] / total_time
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), event_color, 1.0)
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(count)
	for i in count:
		points[i] = Vector2(
			rect.position.x + rect.size.x * _log.times[i] / total_time,
			rect.end.y - rect.size.y * clampf(values[i] / top, 0.0, 1.0))
	draw_polyline(points, color, 2.0)
	draw_string(font, rect.position + Vector2(6.0, 18.0), "%s (верх шкалы %d)" % [caption, int(top)],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, color)
	draw_string(font, Vector2(rect.end.x - 70.0, rect.end.y + 17.0), _clock(total_time),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 1.0, 1.0, 0.7))
	draw_string(font, Vector2(rect.position.x, rect.end.y + 17.0), "0:00",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 1.0, 1.0, 0.7))


func _clock(seconds: float) -> String:
	var whole: int = int(seconds)
	return "%d:%02d" % [int(whole / 60.0), whole % 60]
