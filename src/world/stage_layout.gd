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
## Склады топлива: x — восток, y — север.
var depots: PackedVector2Array = PackedVector2Array()
var depot_radius: float = 15.0

## Участок трассы с границами (раздел 2.1): прямой коридор между двумя стенами.
var has_track: bool = false
var track_start: Vector2 = Vector2.ZERO
var track_end: Vector2 = Vector2.ZERO
var track_half_width: float = 20.0
## Стены трассы: пары точек «начало, конец».
var walls: PackedVector2Array = PackedVector2Array()
## Ворота трассы по порядку: вход, промежуточные, выход.
var gates: PackedVector2Array = PackedVector2Array()
## Препятствия на трассе: по четыре числа — восток, север, радиус, вид.
var track_obstacles: PackedFloat32Array = PackedFloat32Array()

## Всё, что машина должна пройти по порядку: контрольные точки и ворота
## трассы между ними. Эти списки получает симуляция.
var waypoints: PackedVector2Array = PackedVector2Array()
var waypoint_radii: PackedFloat32Array = PackedFloat32Array()
## Подписи для экрана: «контрольная точка 2», «ворота трассы 1 из 4».
var waypoint_labels: PackedStringArray = PackedStringArray()
## Номер контрольной точки для каждого места в списке, с нуля; у ворот -1.
var waypoint_checkpoint: PackedInt32Array = PackedInt32Array()
## Склад, который лежит на пути к этому месту, или -1.
var leg_depots: PackedInt32Array = PackedInt32Array()

var _track_leg: int = -1

var _start_clear: float = 80.0


func _init(params: WorldGenParams) -> void:
	checkpoint_radius = params.checkpoint_radius
	_start_clear = params.start_clear_radius
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.world_seed, 4242))
	_place_checkpoints(params, rng)
	_place_track(params)
	_place_depots(params, rng)
	_place_landmarks(params, rng)
	_build_waypoints()


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


## Трасса: прямой коридор вдоль отрезка маршрута, две сплошные стены,
## ворота через равные промежутки и свои препятствия.
func _place_track(params: WorldGenParams) -> void:
	# Свои случайные числа: трасса не меняет остальную расстановку.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.world_seed, 7107))
	_track_leg = params.track_leg
	if _track_leg < 0 or _track_leg >= checkpoints.size():
		return
	var from: Vector2 = start
	if _track_leg > 0:
		from = checkpoints[_track_leg - 1]
	var to: Vector2 = checkpoints[_track_leg]
	var leg_length: float = from.distance_to(to)
	var length: float = minf(params.track_length, leg_length - params.track_offset - 600.0)
	if length < 300.0:
		return
	has_track = true
	track_half_width = params.track_width * 0.5
	var direction: Vector2 = (to - from).normalized()
	var side: Vector2 = direction.orthogonal()
	track_start = from + direction * params.track_offset
	track_end = track_start + direction * length
	walls.append(track_start + side * track_half_width)
	walls.append(track_end + side * track_half_width)
	walls.append(track_start - side * track_half_width)
	walls.append(track_end - side * track_half_width)
	# Ворота: вход, через каждые track_gate_spacing и выход.
	var gate_count: int = maxi(1, int(round(length / params.track_gate_spacing)))
	for i in gate_count + 1:
		gates.append(track_start + direction * (length * i / gate_count))
	# Препятствия: одно на track_obstacle_spacing метров, не у самых стен
	# и не в воротах.
	var obstacle_count: int = int(floor(length / params.track_obstacle_spacing))
	for i in obstacle_count:
		var along: float = (i + 0.5) * params.track_obstacle_spacing + rng.randf_range(-30.0, 30.0)
		var across: float = rng.randf_range(-0.5, 0.5) * track_half_width
		var radius: float = rng.randf_range(1.5, 3.0)
		var spot: Vector2 = track_start + direction * along + side * across
		var in_gate: bool = false
		for gate in gates:
			if spot.distance_to(gate) < track_half_width + radius:
				in_gate = true
		if in_gate:
			continue
		track_obstacles.append(spot.x)
		track_obstacles.append(spot.y)
		track_obstacles.append(radius)
		track_obstacles.append(0.0)


## Расстояние от места до оси трассы, м.
func _distance_to_track(spot: Vector2) -> float:
	var axis: Vector2 = track_end - track_start
	var along: float = clampf((spot - track_start).dot(axis) / axis.length_squared(), 0.0, 1.0)
	return spot.distance_to(track_start + axis * along)


## Список всего, что проходится по порядку: перед контрольной точкой отрезка
## с трассой стоят её ворота.
func _build_waypoints() -> void:
	for i in checkpoints.size():
		if has_track and i == _track_leg:
			for g in gates.size():
				waypoints.append(gates[g])
				waypoint_radii.append(track_half_width)
				waypoint_labels.append("ворота трассы %d из %d" % [g + 1, gates.size()])
				waypoint_checkpoint.append(-1)
				leg_depots.append(-1)
		waypoints.append(checkpoints[i])
		waypoint_radii.append(checkpoint_radius)
		if i == checkpoints.size() - 1:
			waypoint_labels.append("контрольная точка %d, финиш" % (i + 1))
		else:
			waypoint_labels.append("контрольная точка %d" % (i + 1))
		waypoint_checkpoint.append(i)
		if i < depots.size():
			leg_depots.append(i)
		else:
			leg_depots.append(-1)


## Передать симуляции всё, что проходится по порядку, и стены трассы.
## sim — RaceSim.
func apply_to(sim) -> void:
	sim.checkpoints = waypoints
	sim.checkpoint_radius = checkpoint_radius
	sim.checkpoint_radii = waypoint_radii
	sim.leg_depots = leg_depots
	sim.walls = walls


## Сколько контрольных точек (без ворот) среди первых count мест списка.
func checkpoints_among(count: int) -> int:
	var total: int = 0
	for i in mini(count, waypoint_checkpoint.size()):
		if waypoint_checkpoint[i] >= 0:
			total += 1
	return total


## Насколько путь from -> via -> to длиннее прямого from -> to, м.
static func detour_length(from: Vector2, via: Vector2, to: Vector2) -> float:
	return from.distance_to(via) + via.distance_to(to) - from.distance_to(to)


## Склады лежат в стороне от прямых между контрольными точками (раздел 5.5):
## по одному на отрезок, крюк от depot_detour_min до depot_detour_max.
func _place_depots(params: WorldGenParams, rng: RandomNumberGenerator) -> void:
	depot_radius = params.depot_radius
	var from: Vector2 = start
	for i in mini(params.depot_count, checkpoints.size()):
		var to: Vector2 = checkpoints[i]
		var along: float = rng.randf_range(0.35, 0.65)
		if has_track and i == _track_leg:
			# На отрезке с трассой склад стоит после её выхода.
			var after_track: float = (from.distance_to(track_end) + 300.0) / from.distance_to(to)
			# Случайное число то же, что без трассы: остальные склады и ориентиры
			# от появления трассы не сдвигаются.
			along = lerpf(minf(after_track, 0.85), 0.9, (along - 0.35) / 0.3)
		var detour: float = rng.randf_range(params.depot_detour_min, params.depot_detour_max)
		var side: float = 1.0
		if rng.randf() < 0.5:
			side = -1.0
		var base: Vector2 = from.lerp(to, along)
		var normal: Vector2 = (to - from).normalized().orthogonal()
		# Смещение от отрезка подбирается делением пополам под нужный крюк.
		var low: float = 0.0
		var high: float = 3000.0
		for step in 30:
			var middle: float = (low + high) * 0.5
			if detour_length(from, base + normal * middle, to) < detour:
				low = middle
			else:
				high = middle
		var spot: Vector2 = base + normal * low * side
		var edge: float = 200.0
		if spot.x < params.area_min.x + edge or spot.x > params.area_max.x - edge \
				or spot.y < params.area_min.y + edge or spot.y > params.area_max.y - edge:
			spot = base - normal * low * side
		depots.append(spot)
		from = to


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
		for depot in depots:
			if spot.distance_to(depot) < 200.0:
				is_free = false
		if has_track and _distance_to_track(spot) < track_half_width + 150.0:
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
	for depot in depots:
		zones.append(Vector3(depot.x, depot.y, depot_radius + 25.0))
	if has_track:
		# Трасса и полоса вокруг стен: случайных препятствий и скользких полей
		# здесь нет, на трассе стоят свои препятствия.
		var length: float = track_start.distance_to(track_end)
		var steps: int = int(ceil(length / 40.0))
		for i in steps + 1:
			var spot: Vector2 = track_start.lerp(track_end, float(i) / steps)
			zones.append(Vector3(spot.x, spot.y, track_half_width + 30.0))
	return zones
