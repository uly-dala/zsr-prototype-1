extends Node2D
## Слой отображения местности: создаёт и выгружает части вокруг камеры
## (раздел 9.4). Картинка и препятствия существуют только рядом с камерой;
## симуляция от загруженных частей не зависит.
##
## Часть создаётся в фоновом потоке: поток считает данные картинки и список
## препятствий, главный поток за кадр принимает не больше одной готовой части.
## Разница между границами загрузки и выгрузки не даёт частям мигать.

const ObstacleView = preload("res://src/view/obstacle_view.gd")
const TERRAIN_SHADER = preload("res://src/view/terrain.gdshader")

## Отладка (F3): рисовать границы частей.
var show_borders: bool = false
## Время создания последней части, мс.
var last_build_msec: int = 0

var _terrain = null
var _chunks: Dictionary = {}
var _pending: Dictionary = {}
var _ready_list: Array = []
var _task_ids: Array = []
var _mutex: Mutex = Mutex.new()
var _generation: int = 0
var _base_material: ShaderMaterial


func _ready() -> void:
	_base_material = ShaderMaterial.new()
	_base_material.shader = TERRAIN_SHADER


func _exit_tree() -> void:
	_wait_for_tasks()


## Сменить слой данных (GeneratedTerrain) или убрать его (null).
func set_terrain(terrain) -> void:
	_wait_for_tasks()
	_generation += 1
	for coord in _chunks:
		_chunks[coord].queue_free()
	_chunks.clear()
	_pending.clear()
	_mutex.lock()
	_ready_list.clear()
	_mutex.unlock()
	_terrain = terrain
	if terrain != null:
		_base_material.set_shader_parameter("hard_color", terrain.hard.color)
		_base_material.set_shader_parameter("sand_color", terrain.sand.color)
		_base_material.set_shader_parameter("slick_color", terrain.slick.color)
		_base_material.set_shader_parameter("cells", float(terrain.params.chunk_cells))
		_base_material.set_shader_parameter("chunk_size", terrain.params.chunk_size)
		_base_material.set_shader_parameter("contour_interval", terrain.params.contour_interval)
	queue_redraw()


func loaded_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _pending.size()


## Вызывается каждый кадр. center — положение камеры в координатах Godot.
func update_center(center: Vector2) -> void:
	if _terrain == null:
		return
	_release_finished_tasks()
	_accept_ready_chunk()
	_unload_far(center)
	_request_near(center)


func _request_near(center: Vector2) -> void:
	var params = _terrain.params
	var free_jobs: int = params.max_jobs - _pending.size()
	if free_jobs <= 0:
		return
	var size: float = params.chunk_size
	var radius: float = params.load_radius
	var wanted: Array = []
	var cx_from: int = int(floor((center.x - radius) / size))
	var cx_to: int = int(floor((center.x + radius) / size))
	var cy_from: int = int(floor((center.y - radius) / size))
	var cy_to: int = int(floor((center.y + radius) / size))
	for cx in range(cx_from, cx_to + 1):
		for cy in range(cy_from, cy_to + 1):
			var coord: Vector2i = Vector2i(cx, cy)
			if _chunks.has(coord) or _pending.has(coord):
				continue
			var distance: float = _distance_to_chunk(center, coord, size)
			if distance <= radius:
				wanted.append([distance, coord])
	if wanted.is_empty():
		return
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(free_jobs, wanted.size()):
		var coord: Vector2i = wanted[i][1]
		_pending[coord] = true
		_task_ids.append(WorkerThreadPool.add_task(_build_chunk.bind(_terrain, coord, _generation)))


## Работает в фоновом потоке: только чистые функции слоя данных.
func _build_chunk(terrain, coord: Vector2i, generation: int) -> void:
	var started: int = Time.get_ticks_msec()
	var data: PackedFloat32Array = terrain.build_chunk_data(coord.x, coord.y)
	# Часть экрана (x, y вниз) — это часть мира (x, -y - 1) с y на север.
	var obstacles: PackedFloat32Array = terrain.build_obstacles(coord.x, -coord.y - 1)
	var side: int = terrain.params.chunk_cells + 1
	var image: Image = Image.create_from_data(side, side, false, Image.FORMAT_RGBAF, data.to_byte_array())
	var result: Dictionary = {
		"coord": coord,
		"generation": generation,
		"image": image,
		"obstacles": obstacles,
		"msec": Time.get_ticks_msec() - started,
	}
	_mutex.lock()
	_ready_list.append(result)
	_mutex.unlock()


## Не больше одной готовой части за кадр.
func _accept_ready_chunk() -> void:
	var result = null
	_mutex.lock()
	if not _ready_list.is_empty():
		result = _ready_list.pop_front()
	_mutex.unlock()
	if result == null:
		return
	if result["generation"] != _generation:
		return
	var coord: Vector2i = result["coord"]
	_pending.erase(coord)
	last_build_msec = result["msec"]
	var params = _terrain.params
	var size: float = params.chunk_size
	var side: int = params.chunk_cells + 1

	var chunk: Node2D = Node2D.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	# Части рисуются под самим узлом, чтобы отладочные границы были поверх.
	chunk.show_behind_parent = true
	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(result["image"])
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = Vector2(coord.x * size, coord.y * size)
	sprite.scale = Vector2(size / side, size / side)
	var material_copy: ShaderMaterial = _base_material.duplicate() as ShaderMaterial
	material_copy.set_shader_parameter("origin", sprite.position)
	sprite.material = material_copy
	chunk.add_child(sprite)
	var obstacle_view: ObstacleView = ObstacleView.new()
	obstacle_view.obstacles = result["obstacles"]
	chunk.add_child(obstacle_view)
	add_child(chunk)
	_chunks[coord] = chunk
	if show_borders:
		queue_redraw()


func _unload_far(center: Vector2) -> void:
	var params = _terrain.params
	var removed: Array = []
	for coord in _chunks:
		if _distance_to_chunk(center, coord, params.chunk_size) > params.unload_radius:
			removed.append(coord)
	for coord in removed:
		_chunks[coord].queue_free()
		_chunks.erase(coord)
	if show_borders and not removed.is_empty():
		queue_redraw()


## Расстояние от точки до ближайшего места части, м.
func _distance_to_chunk(point: Vector2, coord: Vector2i, size: float) -> float:
	var left: float = coord.x * size
	var top: float = coord.y * size
	var dx: float = maxf(maxf(left - point.x, 0.0), point.x - (left + size))
	var dy: float = maxf(maxf(top - point.y, 0.0), point.y - (top + size))
	return sqrt(dx * dx + dy * dy)


## Завершённые фоновые задачи нужно принять, иначе они копятся в пуле.
func _release_finished_tasks() -> void:
	var running: Array = []
	for task_id in _task_ids:
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
		else:
			running.append(task_id)
	_task_ids = running


func _wait_for_tasks() -> void:
	for task_id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_task_ids.clear()


func _draw() -> void:
	if not show_borders or _terrain == null:
		return
	var size: float = _terrain.params.chunk_size
	for coord in _chunks:
		draw_rect(Rect2(coord.x * size, coord.y * size, size, size), Color(1.0, 0.3, 0.9, 0.7), false)
