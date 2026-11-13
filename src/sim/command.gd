extends RefCounted
## Команда машине (раздел 9.2). Единственный способ повлиять на машину:
## её отдаёт игрок, ИИ или запись повтора.
##
## Данные команды лежат в a и b:
##   MANUAL      a — руль от -1 до 1, b — газ и тормоз от -1 до 1; нули — «отпущено»
##   SET_TARGET  a — режим TargetMode, b — значение: км/ч или кг/мин
##   SET_COURSE  a — курс в градусах, active = false — «не задан»      (шаг 3)
##   SET_POINT   a — восток, b — север, active = false — «нет точки»   (шаг 4)

enum Type { MANUAL, SET_TARGET, SET_COURSE, SET_POINT }
## Режим удержания для SET_TARGET.
enum TargetMode { SPEED, CONSUMPTION }

## Номер шага симуляции, на котором команда принята. Ставит RaceSim.
var step_index: int = 0
var car_id: int = 0
var type: int = Type.MANUAL
var a: float = 0.0
var b: float = 0.0
var active: bool = true


func _init(p_type: int = Type.MANUAL, p_car_id: int = 0, p_a: float = 0.0, p_b: float = 0.0, p_active: bool = true) -> void:
	type = p_type
	car_id = p_car_id
	a = p_a
	b = p_b
	active = p_active
