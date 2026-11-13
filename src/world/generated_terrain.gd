extends RefCounted
## Слой данных местности: местность как функция (раздел 9.4).
## Высота, покрытие и ветер в любой точке вычисляются по координатам и зерну,
## без обращения к загруженным частям. Симуляция всех машин работает только
## с этим слоем; картинка строится из него же.
##
## Координаты: x — восток, y — север, метры.
## Функции height_at, sand_at, field_at, build_obstacles и build_chunk_data
## ничего не меняют в объекте, поэтому их можно вызывать из фонового потока.

const WorldGenParams = preload("res://src/world/world_gen_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")

## Размер клетки для поиска скользких полей, м.
const FIELD_CELL: float = 1000.0
## Чисел на одно препятствие в массиве: восток, север, радиус, вид.
const OBSTACLE_STRIDE: int = 4
const OBSTACLE_CACHE_LIMIT: int = 400

var params: WorldGenParams
var hard: SurfaceParams
var sand: SurfaceParams
var slick: SurfaceParams

var _height_noise: FastNoiseLite
var _sand_noise: FastNoiseLite
# Скользкие поля: по пять чисел на поле — восток, север, радиус, ветер на восток, ветер на север.
var _fields: PackedFloat32Array = PackedFloat32Array()
var _field_grid: Dictionary = {}
var _sample: TerrainSample = TerrainSample.new()
var _obstacle_cache: Dictionary = {}


func _init(p_params: WorldGenParams, p_hard: SurfaceParams, p_sand: SurfaceParams, p_slick: SurfaceParams) -> void:
	params = p_params
	hard = p_hard
	sand = p_sand
	slick = p_slick
	_height_noise = FastNoiseLite.new()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.seed = params.world_seed
	_height_noise.frequency = 1.0 / params.height_period
	_height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_height_noise.fractal_octaves = 3
	_sand_noise = FastNoiseLite.new()
	_sand_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_sand_noise.seed = params.world_seed + 1000
	_sand_noise.frequency = 1.0 / params.sand_period
	_sand_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_sand_noise.fractal_octaves = 2
	_place_fields()


# --- Запросы симуляции --------------------------------------------------------

## «Что в точке (x, y)». Возвращает один и тот же объект: читать сразу.
func sample(x: float, y: float) -> TerrainSample:
	var result: TerrainSample = _sample
	result.height = height_at(x, y)
	var field: int = field_at(x, y)
	if field >= 0:
		# Скользкое поле ровное; на нём дует ветер.
		result.surface = slick
		result.grade_east = 0.0
		result.grade_north = 0.0
		result.wind_east = _fields[field * 5 + 3]
		result.wind_north = _fields[field * 5 + 4]
		return result
	var grade_east: float = (height_at(x + 1.0, y) - height_at(x - 1.0, y)) * 0.5
	var grade_north: float = (height_at(x, y + 1.0) - height_at(x, y - 1.0)) * 0.5
	var steepness: float = sqrt(grade_east * grade_east + grade_north * grade_north)
	if steepness > params.max_grade:
		var keep: float = params.max_grade / steepness
		grade_east *= keep
		grade_north *= keep
	result.grade_east = grade_east
	result.grade_north = grade_north
	result.wind_east = 0.0
	result.wind_north = 0.0
	if sand_at(x, y) > 0.5:
		result.surface = sand
	else:
		result.surface = hard
	return result


## Препятствие, которого касается машина в точке (x, y): x — восток,
## y — север, z — радиус. Если касания нет, радиус равен нулю.
## margin — половина ширины машины, м.
func obstacle_near(x: float, y: float, margin: float) -> Vector3:
	var size: float = params.chunk_size
	var reach: float = params.obstacle_radius_max + margin
	var cx_from: int = int(floor((x - reach) / size))
	var cx_to: int = int(floor((x + reach) / size))
	var cy_from: int = int(floor((y - reach) / size))
	var cy_to: int = int(floor((y + reach) / size))
	for cx in range(cx_from, cx_to + 1):
		for cy in range(cy_from, cy_to + 1):
			var list: PackedFloat32Array = _cached_obstacles(cx, cy)
			var index: int = 0
			while index < list.size():
				var d_east: float = list[index] - x
				var d_north: float = list[index + 1] - y
				var touch: float = list[index + 2] + margin
				if d_east * d_east + d_north * d_north < touch * touch:
					return Vector3(list[index], list[index + 1], list[index + 2])
				index += OBSTACLE_STRIDE
	return Vector3.ZERO


# --- Чистые функции слоя данных -----------------------------------------------

## Высота, м.
func height_at(x: float, y: float) -> float:
	return _height_noise.get_noise_2d(x, y) * params.height_amplitude


## Песок: больше 0,5 — песок. Значение плавно меняется у края пятна.
func sand_at(x: float, y: float) -> float:
	return clampf((_sand_noise.get_noise_2d(x, y) - params.sand_threshold) * 6.0 + 0.5, 0.0, 1.0)


## Номер скользкого поля в точке или -1.
func field_at(x: float, y: float) -> int:
	var cell: Vector2i = Vector2i(int(floor(x / FIELD_CELL)), int(floor(y / FIELD_CELL)))
	if not _field_grid.has(cell):
		return -1
	var candidates: PackedInt32Array = _field_grid[cell]
	for field in candidates:
		var d_east: float = x - _fields[field * 5]
		var d_north: float = y - _fields[field * 5 + 1]
		var radius: float = _fields[field * 5 + 2]
		if d_east * d_east + d_north * d_north < radius * radius:
			return field
	return -1


func field_count() -> int:
	return int(_fields.size() / 5.0)


## Поле по номеру: x — восток, y — север, z — радиус.
func field_circle(field: int) -> Vector3:
	return Vector3(_fields[field * 5], _fields[field * 5 + 1], _fields[field * 5 + 2])


## Ветер на поле: боковое ускорение на восток и на север, м/с².
func field_wind(field: int) -> Vector2:
	return Vector2(_fields[field * 5 + 3], _fields[field * 5 + 4])


## Препятствия части (cx, cy): части считаются по сетке chunk_size от начала
## координат, cy растёт на север. Возвращает по четыре числа на препятствие:
## восток, север, радиус, вид (0 — камень, 1 — заросли).
## Результат зависит только от зерна и координат части.
func build_obstacles(cx: int, cy: int) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	var size: float = params.chunk_size
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(params.world_seed, cx, cy))
	var mean: float = params.obstacle_density * size * size / 1000000.0
	var count: int = maxi(0, roundi(rng.randfn(mean, sqrt(maxf(mean, 0.0)))))
	var clear: float = params.start_clear_radius
	for i in count:
		var x: float = (cx + rng.randf()) * size
		var y: float = (cy + rng.randf()) * size
		var radius: float = rng.randf_range(params.obstacle_radius_min, params.obstacle_radius_max)
		var kind: float = float(rng.randi() % 2)
		if x * x + y * y < clear * clear:
			continue
		# На скользких полях препятствий нет (раздел 5.4).
		if _near_field(x, y, radius):
			continue
		result.append(x)
		result.append(y)
		result.append(radius)
		result.append(kind)
	return result


## Данные картинки части для экрана. Часть (gcx, gcy) считается в координатах
## экрана Godot: gcy растёт на юг. На каждый узел сетки четыре числа:
## высота (м), песок (0–1), скользкое (0 или 1), направление ветра (доля круга).
func build_chunk_data(gcx: int, gcy: int) -> PackedFloat32Array:
	var cells: int = params.chunk_cells
	var step_size: float = params.chunk_size / cells
	var side: int = cells + 1
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(side * side * 4)
	var index: int = 0
	for j in side:
		var north: float = -(gcy * params.chunk_size + j * step_size)
		for i in side:
			var east: float = gcx * params.chunk_size + i * step_size
			data[index] = height_at(east, north)
			data[index + 1] = sand_at(east, north)
			var field: int = field_at(east, north)
			if field >= 0:
				data[index + 2] = 1.0
				data[index + 3] = fposmod(atan2(_fields[field * 5 + 3], _fields[field * 5 + 4]), TAU) / TAU
			else:
				data[index + 2] = 0.0
				data[index + 3] = 0.0
			index += 4
	return data


# --- Внутреннее ---------------------------------------------------------------

func _cached_obstacles(cx: int, cy: int) -> PackedFloat32Array:
	var key: Vector2i = Vector2i(cx, cy)
	if _obstacle_cache.has(key):
		return _obstacle_cache[key]
	if _obstacle_cache.size() >= OBSTACLE_CACHE_LIMIT:
		_obstacle_cache.clear()
	var list: PackedFloat32Array = build_obstacles(cx, cy)
	_obstacle_cache[key] = list
	return list


## Лежит ли круг (x, y, radius) на скользком поле или касается его.
func _near_field(x: float, y: float, radius: float) -> bool:
	var field: int = 0
	var total: int = field_count()
	while field < total:
		var d_east: float = x - _fields[field * 5]
		var d_north: float = y - _fields[field * 5 + 1]
		var reach: float = _fields[field * 5 + 2] + radius
		if d_east * d_east + d_north * d_north < reach * reach:
			return true
		field += 1
	return false


## Расставить скользкие поля: сначала заданные вручную, потом из зерна.
func _place_fields() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.world_seed, 7919))
	for extra in params.extra_slick_fields:
		_add_field(extra.x, extra.y, extra.z, rng)
	var placed: int = 0
	var attempts: int = 0
	while placed < params.slick_count and attempts < params.slick_count * 20:
		attempts += 1
		var x: float = rng.randf_range(params.area_min.x, params.area_max.x)
		var y: float = rng.randf_range(params.area_min.y, params.area_max.y)
		var radius: float = rng.randf_range(params.slick_radius_min, params.slick_radius_max)
		# Не на старте и не внахлёст с другим полем.
		if sqrt(x * x + y * y) < radius + params.start_clear_radius + 200.0:
			continue
		if _near_field(x, y, radius):
			continue
		_add_field(x, y, radius, rng)
		placed += 1


func _add_field(x: float, y: float, radius: float, rng: RandomNumberGenerator) -> void:
	var field: int = field_count()
	var direction: float = rng.randf() * TAU
	var strength: float = rng.randf_range(params.wind_min, params.wind_max)
	_fields.append(x)
	_fields.append(y)
	_fields.append(radius)
	_fields.append(sin(direction) * strength)
	_fields.append(cos(direction) * strength)
	var cx_from: int = int(floor((x - radius) / FIELD_CELL))
	var cx_to: int = int(floor((x + radius) / FIELD_CELL))
	var cy_from: int = int(floor((y - radius) / FIELD_CELL))
	var cy_to: int = int(floor((y + radius) / FIELD_CELL))
	for cx in range(cx_from, cx_to + 1):
		for cy in range(cy_from, cy_to + 1):
			var cell: Vector2i = Vector2i(cx, cy)
			var list: PackedInt32Array = PackedInt32Array()
			if _field_grid.has(cell):
				list = _field_grid[cell]
			list.append(field)
			_field_grid[cell] = list
