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
@export var start_clear_radius: float = 80.0

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
@export var height_amplitude: float = 45.0
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
