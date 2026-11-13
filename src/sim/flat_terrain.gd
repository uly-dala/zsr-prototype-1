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


## x — восток, y — север, метры.
func sample(_x: float, _y: float) -> TerrainSample:
	return _sample
