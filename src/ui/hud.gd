extends Control
## Экран шага 1: строки с числами машины и метка стандартного положения камеры.
## Настоящий экран заезда (раздел 7.4) появится на шаге 2.

var _label: Label
var _course_label: Label
var _marker_visible: bool = false
var _marker_frac: Vector2 = Vector2(0.5, 0.75)
var _marker_color: Color = Color(1.0, 0.9, 0.5, 0.9)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Экран не должен перехватывать мышь: клики идут в игру.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.position = Vector2(24.0, 18.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_constant_override("line_spacing", 4)
	add_child(_label)
	_course_label = Label.new()
	_course_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_course_label.add_theme_font_size_override("font_size", 20)
	_course_label.add_theme_color_override("font_color", Color(0.75, 0.97, 1.0))
	_course_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_course_label.add_theme_constant_override("shadow_offset_x", 1)
	_course_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_course_label)


func set_lines(content: String) -> void:
	if _label != null and _label.text != content:
		_label.text = content


## Указатель курса рядом с машиной: текущий и заданный курс числами (раздел 7.3).
## car_frac — положение машины на экране в долях экрана.
func set_course_text(content: String, car_frac: Vector2) -> void:
	if _course_label == null:
		return
	if _course_label.text != content:
		_course_label.text = content
	_course_label.position = size * car_frac + Vector2(28.0, -52.0)


## Показать или скрыть метку стандартного положения машины на экране.
func set_marker(shown: bool, frac: Vector2) -> void:
	if shown == _marker_visible and frac == _marker_frac:
		return
	_marker_visible = shown
	_marker_frac = frac
	queue_redraw()


func _draw() -> void:
	if not _marker_visible:
		return
	var center: Vector2 = size * _marker_frac
	draw_arc(center, 18.0, 0.0, TAU, 40, _marker_color, 2.0)
	draw_line(center + Vector2(-28.0, 0.0), center + Vector2(-8.0, 0.0), _marker_color, 2.0)
	draw_line(center + Vector2(8.0, 0.0), center + Vector2(28.0, 0.0), _marker_color, 2.0)
	draw_line(center + Vector2(0.0, -28.0), center + Vector2(0.0, -8.0), _marker_color, 2.0)
	draw_line(center + Vector2(0.0, 8.0), center + Vector2(0.0, 28.0), _marker_color, 2.0)
