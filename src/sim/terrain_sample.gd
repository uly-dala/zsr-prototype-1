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
## Ветер на скользком поле: ускорение на восток и на север, м/с².
## На обычном грунте ноль.
var wind_east: float = 0.0
var wind_north: float = 0.0


## Слой местности возвращает один и тот же объект на каждый запрос,
## поэтому тот, кому ответ нужен надолго, копирует его себе.
func copy_from(other) -> void:
	height = other.height
	grade_east = other.grade_east
	grade_north = other.grade_north
	surface = other.surface
	wind_east = other.wind_east
	wind_north = other.wind_north
