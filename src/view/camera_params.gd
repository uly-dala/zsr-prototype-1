extends Resource
## Параметры камеры. Дизайн-документ, раздел 7.1.

## Высота экрана на местности для трёх зумов, м: ближний, средний, дальний.
@export var zoom_heights: PackedFloat32Array = PackedFloat32Array([170.0, 330.0, 500.0])
## Зум при старте: 0, 1 или 2.
@export var start_zoom_index: int = 1
## Изначальное стандартное положение машины на экране в долях экрана:
## центр по горизонтали, четверть высоты от нижнего края.
@export var default_car_frac: Vector2 = Vector2(0.5, 0.75)
## Машина не подходит к краю экрана ближе этой доли.
@export var edge_margin: float = 0.08
## Время быстрого возврата в стандартное положение, с.
@export var quick_return_time: float = 0.3
## Щелчок средней кнопкой отличается от сдвига: курсор сдвинулся не больше, пикселей.
@export var click_move_threshold: float = 5.0
## Скорость сдвига камеры стрелками, долей экрана в секунду.
@export var arrow_shift_rate: float = 0.6
## Сколько секунд показывать метку стандартного положения.
@export var marker_time: float = 1.0
