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
## Наибольшая скорость заднего хода, м/с (допущение: около 30 км/ч).
@export var reverse_max_speed: float = 8.0
## Доля максимальной тяги на заднем ходу (допущение).
@export var reverse_thrust_share: float = 0.5

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

@export_group("Снос и удары")
## После выхода со скользкого поля снос от ветра гаснет за столько секунд (допущение).
@export var wind_drift_decay: float = 0.5
## Удар засчитывается, если машина входит в препятствие быстрее, м/с.
## Медленнее — это касание без штрафа (допущение).
@export var collision_hit_speed: float = 2.0
## Доля скорости, которая остаётся после удара о препятствие.
@export var collision_speed_keep: float = 0.2
## На сколько секунд удар блокирует управление.
@export var collision_block_time: float = 1.0
## Половина ширины машины для проверки удара, м.
@export var collision_margin: float = 1.0

@export_group("Управление")
## Доля доступной боковой силы шин, которую использует автоматика.
@export var autopilot_lateral_share: float = 0.4
## Потеря скорости на пределе сцепления при ручном манёвре, м/с за секунду.
@export var manual_scrub_decel: float = 4.0
## Через сколько секунд после отпускания W или S автоматика возвращает газ.
@export var manual_release_delay: float = 0.3

@export_group("Удержание скорости и расхода")
## Шаг заданной скорости, км/ч.
@export var target_speed_step: float = 5.0
## Наибольшая заданная скорость, км/ч.
@export var target_speed_max: float = 140.0
## Шаг заданного расхода, кг/мин.
@export var target_consumption_step: float = 5.0
## Наибольший заданный расход, кг/мин.
@export var target_consumption_max: float = 150.0
## Насколько резко автоматика догоняет заданную скорость: м/с² на 1 м/с ошибки.
@export var autopilot_speed_gain: float = 0.8
## Наибольший разгон автоматики, м/с² (допущение).
@export var autopilot_max_accel: float = 3.0
## Наибольшее торможение автоматики, м/с² (допущение).
@export var autopilot_max_brake: float = 3.0

@export_group("Удержание курса")
## Насколько резко автоматика доворачивает нос: рад/с на 1 рад ошибки курса.
@export var autopilot_course_gain: float = 1.5

@export_group("Точка")
## Точка считается пройденной в этом радиусе, м.
@export var point_pass_radius: float = 5.0
## При заданном курсе точку можно ставить в секторе ± столько градусов от курса.
@export var point_sector_deg: float = 60.0
## При заданном курсе точку можно ставить не дальше, м.
@export var point_max_range: float = 400.0
## Запас зоны клика: радиус поворота для зоны умножается на это число,
## чтобы точка на самой границе не снималась из-за запаздывания руля.
@export var point_zone_margin: float = 1.1
## Точка снимается как недостижимая, когда оказывается внутри окружности
## поворота, уменьшенной до этой доли (допущение).
@export var point_drop_slack: float = 0.85
## Ближе этого расстояния достижимость не проверяется: точка либо будет
## пройдена, либо останется позади (допущение), м.
@export var point_near_distance: float = 15.0
