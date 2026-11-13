extends RefCounted
## Состояние машины. Координаты мира: x — восток, y — север, метры.
## Курс в радианах: 0 — север, растёт по часовой стрелке.
##
## Остальная игра читает отсюда только выход модели (раздел 9.6):
## положение, направление носа, вектор скорости, массу, топливо, расход.

# --- Состояние, которое интегрирует модель ---
var x: float = 0.0
var y: float = 0.0
var heading: float = 0.0
var vel_east: float = 0.0
var vel_north: float = 0.0
## Топливо, кг.
var fuel: float = 0.0
## Фактическое положение руля от -1 до 1 (догоняет заданное).
var steer: float = 0.0
## Пройденный путь, м.
var distance: float = 0.0

# --- Величины последнего шага: для экрана, записи и отладки ---
## Полная масса, кг.
var mass: float = 0.0
## Скорость поворота носа, рад/с.
var yaw_rate: float = 0.0
## Тяга двигателя, Н.
var thrust: float = 0.0
## Мощность двигателя, Вт.
var engine_power: float = 0.0
## Расход топлива, кг/мин.
var consumption: float = 0.0
## Боковое ускорение от шин, м/с² (плюс — вправо).
var lateral_accel: float = 0.0
## Доля использованной боковой силы шин, от 0 до 1.
var lateral_ratio: float = 0.0
## Потеря скорости на манёвре, м/с².
var scrub_decel: float = 0.0


## Скорость, м/с.
func speed() -> float:
	return sqrt(vel_east * vel_east + vel_north * vel_north)


## Скорость вдоль носа, м/с.
func forward_speed() -> float:
	return vel_east * sin(heading) + vel_north * cos(heading)


## Курс в градусах от 0 до 360.
func heading_deg() -> float:
	return fposmod(rad_to_deg(heading), 360.0)


## Задать курс и скорость вдоль него.
func set_motion(p_heading: float, p_speed: float) -> void:
	heading = p_heading
	vel_east = sin(p_heading) * p_speed
	vel_north = cos(p_heading) * p_speed
