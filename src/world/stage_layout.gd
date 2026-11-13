extends RefCounted
## Объекты этапа, заданные явно поверх шума (раздел 9.4): старт, контрольные
## точки и ориентиры. Сейчас расставляются из зерна; на шаге 10 список можно
## будет поправить руками.
##
## Координаты: x — восток, y — север, метры.

const WorldGenParams = preload("res://src/world/world_gen_params.gd")

## Виды ориентиров. Вид вместе с номером даёт уникальное имя: «Озеро 2».
const KIND_NAMES: Array = ["Столб", "Остов", "Озеро", "Кратер", "Круг камней", "Маяк"]
## Размер ориентира по видам, м: от и до.
const KIND_SIZES: Array = [[10.0, 16.0], [30.0, 50.0], [40.0, 80.0], [30.0, 55.0], [20.0, 30.0], [8.0, 12.0]]

var start: Vector2 = Vector2.ZERO
## Контрольные точки по порядку; последняя — финиш.
var checkpoints: PackedVector2Array = PackedVector2Array()
var checkpoint_radius: float = 40.0
## Длина маршрута по прямым между точками, м.
var route_length: float = 0.0
## Ориентиры: словари с ключами kind, name, x, y, size, angle.
var landmarks: Array = []

var _start_clear: float = 80.0


func _init(params: WorldGenParams) -> void:
	checkpoint_radius = params.checkpoint_radius
	_start_clear = params.start_clear_radius
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.world_seed, 4242))
	_place_checkpoints(params, rng)
	_place_landmarks(params, rng)


## Маршрут идёт в основном на север; отрезки отклоняются то в одну, то в
## другую сторону и не выходят за границы местности.
func _place_checkpoints(params: WorldGenParams, rng: RandomNumberGenerator) -> void:
	var position: Vector2 = start
	var side: float = 1.0
	if rng.randf() < 0.5:
		side = -1.0
	var edge: float = 400.0
	var lengths: Array = []
	var total: float = 0.0
	for i in params.checkpoint_count:
		var share: float = rng.randf_range(params.segment_min, params.segment_max)
		lengths.append(share)
		total += share
	for i in params.checkpoint_count:
		var length: float = lengths[i] * params.route_length / total
		var deviation: float = deg_to_rad(rng.randf_range(params.deviation_min, params.deviation_max)) * side
		var next: Vector2 = position + Vector2(sin(deviation), cos(deviation)) * length
		if next.x < params.area_min.x + edge or next.x > params.area_max.x - edge:
			deviation = -deviation
			next = position + Vector2(sin(deviation), cos(deviation)) * length
		next.y = minf(next.y, params.area_max.y - edge)
		route_length += position.distance_to(next)
		checkpoints.append(next)
		position = next
		side = -side


func _place_landmarks(params: WorldGenParams, rng: RandomNumberGenerator) -> void:
	var numbers: Array = [0, 0, 0, 0, 0, 0]
	var edge: float = 200.0
	var attempts: int = 0
	while landmarks.size() < params.landmark_count and attempts < params.landmark_count * 60:
		attempts += 1
		var x: float = rng.randf_range(params.area_min.x + edge, params.area_max.x - edge)
		var y: float = rng.randf_range(params.area_min.y + edge, params.area_max.y - edge)
		var spot: Vector2 = Vector2(x, y)
		if spot.distance_to(start) < 250.0:
			continue
		var is_free: bool = true
		for checkpoint in checkpoints:
			if spot.distance_to(checkpoint) < checkpoint_radius + 150.0:
				is_free = false
		for other in landmarks:
			if spot.distance_to(Vector2(other["x"], other["y"])) < params.landmark_spacing:
				is_free = false
		if not is_free:
			continue
		var kind: int = landmarks.size() % KIND_NAMES.size()
		numbers[kind] += 1
		landmarks.append({
			"kind": kind,
			"name": "%s %d" % [KIND_NAMES[kind], numbers[kind]],
			"x": x,
			"y": y,
			"size": rng.randf_range(KIND_SIZES[kind][0], KIND_SIZES[kind][1]),
			"angle": rng.randf() * TAU,
		})


## Места, где не должно быть препятствий и скользких полей:
## x — восток, y — север, z — радиус.
func clear_zones() -> PackedVector3Array:
	var zones: PackedVector3Array = PackedVector3Array()
	zones.append(Vector3(start.x, start.y, _start_clear))
	for checkpoint in checkpoints:
		zones.append(Vector3(checkpoint.x, checkpoint.y, checkpoint_radius + 10.0))
	for landmark in landmarks:
		zones.append(Vector3(landmark["x"], landmark["y"], landmark["size"] * 1.6 + 15.0))
	return zones
