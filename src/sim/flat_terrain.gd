extends RefCounted
## Местность-заглушка шага 1: бесконечная ровная плоскость с одним покрытием.
## Отвечает на тот же запрос sample(x, y), что и будущий генератор (шаг 5),
## поэтому остальной код при замене не меняется.

const SurfaceParams = preload("res://src/sim/surface_params.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")

var _sample: TerrainSample = TerrainSample.new()


func _init(p_surface: SurfaceParams) -> void:
	_sample.surface = p_surface


func set_surface(p_surface: SurfaceParams) -> void:
	_sample.surface = p_surface


func get_surface() -> SurfaceParams:
	return _sample.surface


## Одно препятствие для проверок: x — восток, y — север, z — радиус.
## При нулевом радиусе препятствий на плоскости нет.
var test_obstacle: Vector3 = Vector3.ZERO


## Препятствие, которого касается машина: x — восток, y — север, z — радиус.
## Если касания нет, радиус равен нулю.
func obstacle_near(x: float, y: float, margin: float) -> Vector3:
	if test_obstacle.z <= 0.0:
		return Vector3.ZERO
	var d_east: float = test_obstacle.x - x
	var d_north: float = test_obstacle.y - y
	var touch: float = test_obstacle.z + margin
	if d_east * d_east + d_north * d_north < touch * touch:
		return test_obstacle
	return Vector3.ZERO


## x — восток, y — север, метры.
func sample(_x: float, _y: float) -> TerrainSample:
	return _sample
