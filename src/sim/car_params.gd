extends Resource
## Параметры машины. Дизайн-документ, раздел 4.1.
## Все числа стартовые и правятся в data/car_default.tres без изменения кода.

@export_group("Масса")
## Масса без топлива, кг.
@export var dry_mass: float = 1000.0
## Вместимость бака, кг.
@export var fuel_capacity: float = 500.0

@export_group("Двигатель")
## Максимальная мощность, Вт.
@export var max_power: float = 150000.0
## Максимальная тяга, Н.
@export var max_thrust: float = 8000.0
## Расход топлива, кг на 1 Дж работы двигателя (0,05 кг на 1 кДж).
@export var fuel_per_joule: float = 0.00005

@export_group("Шины")
## Замедление при торможении с пустым баком, м/с².
@export var brake_decel: float = 10.0
## Боковое ускорение на пределе сцепления с пустым баком, м/с².
@export var lateral_accel: float = 9.0
## Показатель падения сцепления с массой: 0 — честная физика, 1 — шины ограничены силой.
@export var grip_mass_exponent: float = 0.45
## Масса, для которой заданы brake_decel и lateral_accel, кг.
@export var reference_mass: float = 1000.0
## Наименьший радиус поворота на малой скорости, м (допущение, в документе не задан).
@export var min_geometric_radius: float = 6.0
## Скорость привода руля, долей полного хода в секунду (допущение).
@export var steer_rate: float = 3.0

@export_group("Сопротивление")
## Аэродинамическое сопротивление: сила = коэффициент · v², скорость в м/с.
@export var drag_coefficient: float = 0.6
## Ускорение свободного падения, м/с².
@export var gravity: float = 9.81

@export_group("Управление")
## Доля доступной боковой силы шин, которую использует автоматика.
@export var autopilot_lateral_share: float = 0.4
## Потеря скорости на пределе сцепления при ручном манёвре, м/с за секунду.
@export var manual_scrub_decel: float = 4.0
