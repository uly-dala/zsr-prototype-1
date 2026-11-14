extends Resource
## Параметры генератора местности. Дизайн-документ, разделы 5 и 9.4.
## Одно и то же зерно всегда даёт одну и ту же местность.

## Зерно генератора.
@export var world_seed: int = 1

@export_group("Границы заезда")
## Юго-западный угол местности заезда: восток и север, м.
@export var area_min: Vector2 = Vector2(-3000.0, -500.0)
## Северо-восточный угол. Короткий формат: 6 × 13 км.
@export var area_max: Vector2 = Vector2(3000.0, 12500.0)
## Вокруг старта нет препятствий и скользких полей, м.
@export var start_clear_radius: float = 150.0

@export_group("Маршрут")
## Контрольных точек на этапе; последняя — финиш.
@export var checkpoint_count: int = 4
## Длина маршрута по прямым между точками, м.
@export var route_length: float = 14000.0
## Соотношение длин отрезков: каждый получает случайную долю в этих пределах,
## затем отрезки растягиваются так, чтобы в сумме дать route_length.
@export var segment_min: float = 3200.0
@export var segment_max: float = 3800.0
## Отклонение отрезка от севера, градусы (в документе не больше 45).
## Маршрут 14 км умещается в 13 км местности только зигзагом.
@export var deviation_min: float = 25.0
@export var deviation_max: float = 42.0
## Радиус контрольной точки, м.
@export var checkpoint_radius: float = 40.0

@export_group("Участок трассы с границами")
## На каком отрезке маршрута лежит трасса: 1 — от первой контрольной точки
## ко второй. Отрицательное число — трассы нет.
@export var track_leg: int = 1
## Длина трассы, м.
@export var track_length: float = 1500.0
## Ширина трассы между стенами, м.
@export var track_width: float = 40.0
## Трасса начинается через столько метров после контрольной точки.
@export var track_offset: float = 250.0
## На трассе одно препятствие на столько метров пути.
@export var track_obstacle_spacing: float = 150.0
## Ворота внутри трассы стоят через столько метров. Их нужно пройти по
## порядку, поэтому трассу нельзя объехать снаружи.
@export var track_gate_spacing: float = 500.0

@export_group("Заправка на старте")
## Выбор топлива на старте: от, до и шаг, кг.
@export var start_fuel_min: float = 200.0
@export var start_fuel_max: float = 500.0
@export var start_fuel_step: float = 50.0
## Значение, с которого начинается выбор, кг.
@export var start_fuel_default: float = 350.0

@export_group("Склады топлива")
## Складов на этапе: по одному на отрезок маршрута.
@export var depot_count: int = 4
## Запас одного склада, кг. Общий для всех машин и конечный.
@export var depot_stock: float = 900.0
## Сколько машина забирает за раз, кг.
@export var depot_portion: float = 300.0
## Радиус склада, м (допущение, в документе не задан).
@export var depot_radius: float = 15.0
## Забрать топливо можно, проезжая медленнее этой скорости, км/ч.
@export var depot_max_speed: float = 30.0
## Крюк до склада: насколько путь через склад длиннее прямого отрезка, м.
@export var depot_detour_min: float = 300.0
@export var depot_detour_max: float = 900.0

@export_group("Ориентиры")
## Сколько ориентиров на местности.
@export var landmark_count: int = 22
## Ориентиры стоят не ближе друг к другу, м.
@export var landmark_spacing: float = 700.0

@export_group("Карта")
## Разрешение картинки карты: метров на пиксель.
@export var map_meters_per_pixel: float = 25.0
## Шаг горизонталей на карте, м.
@export var map_contour_interval: float = 10.0
## Шаг сетки на карте, м.
@export var map_grid_step: float = 500.0

@export_group("Рельеф")
## Размах высот: высота меняется от -amplitude до +amplitude, м.
@export var height_amplitude: float = 30.0
## Характерный размер холма, м.
@export var height_period: float = 1200.0
## Наибольший уклон: 0,15 — это 15 %.
@export var max_grade: float = 0.15
## Шаг горизонталей на экране, м.
@export var contour_interval: float = 5.0

@export_group("Песок")
## Характерный размер песчаного пятна, м.
@export var sand_period: float = 900.0
## Порог шума: чем выше, тем меньше песка (от -1 до 1).
@export var sand_threshold: float = 0.3

@export_group("Скользкие поля")
## Сколько полей расставляет генератор внутри границ заезда.
@export var slick_count: int = 8
## Радиус поля, м.
@export var slick_radius_min: float = 180.0
@export var slick_radius_max: float = 350.0
## Боковое ускорение от ветра на поле, м/с².
@export var wind_min: float = 0.2
@export var wind_max: float = 0.5
## Поля, заданные вручную: x — восток, y — север, z — радиус, м.
@export var extra_slick_fields: PackedVector3Array = PackedVector3Array()

@export_group("Препятствия")
## Препятствий на квадратный километр. 227 — это в среднем одно на 400 м
## пути для полосы шириной 11 м (машина и средний камень).
@export var obstacle_density: float = 227.0
## Радиус препятствия, м (диаметр от 3 до 15 м).
@export var obstacle_radius_min: float = 1.5
@export var obstacle_radius_max: float = 7.5

@export_group("Части")
## Размер части, м.
@export var chunk_size: float = 512.0
## Ячеек данных на сторону части.
@export var chunk_cells: int = 128
## Части загружены в пределах этого расстояния от камеры, м.
@export var load_radius: float = 1500.0
## Части выгружаются дальше этого расстояния, м.
@export var unload_radius: float = 2500.0
## Сколько частей создаётся в фоне одновременно.
@export var max_jobs: int = 3
