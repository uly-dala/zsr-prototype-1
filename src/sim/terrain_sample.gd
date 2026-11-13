extends RefCounted
## Ответ местности на запрос «что в точке (x, y)».
## Модель машины получает местность только в этом виде.

const SurfaceParams = preload("res://src/sim/surface_params.gd")

## Высота, м.
var height: float = 0.0
## Уклон на восток: прирост высоты на метр пути (0,1 = 10 %).
var grade_east: float = 0.0
## Уклон на север.
var grade_north: float = 0.0
## Покрытие под машиной.
var surface: SurfaceParams
