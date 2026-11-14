extends Resource
## Параметры соперников под управлением ИИ. Дизайн-документ, раздел 8.

@export_group("Типы")
## Заправка на старте, кг: спринтер, середняк, экономный.
@export var start_fuel: PackedFloat32Array = PackedFloat32Array([300.0, 500.0, 500.0])
## Крейсерская скорость, км/ч: от и до для каждого типа.
@export var speed_min: PackedFloat32Array = PackedFloat32Array([115.0, 100.0, 75.0])
@export var speed_max: PackedFloat32Array = PackedFloat32Array([125.0, 110.0, 90.0])

@export_group("Счисление")
## Ошибка знания своего положения растёт на столько метров за метр пути.
@export var drift_rate: float = 0.03
## Наибольшая ошибка положения, м.
@export var error_cap: float = 150.0
## Дальность, с которой ИИ видит цель и едет по ней, а не по счислению, м.
@export var sight_radius: float = 250.0
## Рядом с ориентиром (ближе этого) ИИ исправляет своё положение, м.
@export var landmark_fix_radius: float = 150.0

@export_group("Препятствия")
## Вероятность заметить препятствие заранее и объехать его точкой.
@export var notice_probability: float = 0.6
## За сколько секунд пути ИИ ставит точку, если заметил заранее.
@export var early_time: float = 5.0
## За сколько секунд пути ИИ перехватывает руль, если заметил поздно.
@export var late_time: float = 2.0
## Вероятность прозевать препятствие: перехват слишком поздний.
@export var miss_probability: float = 0.15
## За сколько секунд пути перехватывает руль прозевавший.
@export var miss_time: float = 0.9
## Запас сбоку от препятствия при объезде точкой, м.
@export var clearance: float = 6.0

@export_group("Топливо")
## Запас при расчёте, хватит ли топлива до финиша.
@export var fuel_margin: float = 1.15
## Во сколько раз местность дороже ровного грунта: песок, подъёмы, объезды,
## разгоны после ударов. Начальная оценка; в пути ИИ меряет свой расход сам.
@export var terrain_factor: float = 1.5
## На склад заезжают, если в баке есть место хотя бы на столько, кг.
@export var min_refuel_space: float = 100.0
## Наименьшая скорость при экономии топлива, км/ч.
@export var saving_speed_min: float = 50.0
## Наименьшая скорость на подходе к цели, км/ч.
@export var approach_speed_min: float = 20.0
## Скорость проезда склада, км/ч.
@export var depot_speed: float = 25.0
