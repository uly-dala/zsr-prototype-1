extends RefCounted
## Симуляция заезда без привязки к сцене: местность, машины, счёт шагов.
## Обычный объект, а не узел: один и тот же код работает в игре, в тестах
## без окна, при ускорении времени и при воспроизведении повтора.

const CarParams = preload("res://src/sim/car_params.gd")
const Car = preload("res://src/race/car.gd")
const Command = preload("res://src/sim/command.gd")
const WorldState = preload("res://src/race/world_state.gd")

## Шагов симуляции в секунду (раздел 9.1).
const STEPS_PER_SECOND: int = 60
const DT: float = 1.0 / 60.0

## Слой данных местности: объект с функциями sample(x, y) и obstacle_near(x, y, margin).
var terrain
var cars: Array = []
var step_index: int = 0
## Все принятые команды с номерами шагов. Вместе с начальным состоянием это повтор.
var command_log: Array = []
## Контрольные точки по порядку: x — восток, y — север. Последняя — финиш.
var checkpoints: PackedVector2Array = PackedVector2Array()
## Радиус контрольной точки, м.
var checkpoint_radius: float = 40.0
## Свой радиус для каждого места списка (ворота трассы уже контрольных точек).
## Если список пуст, у всех checkpoint_radius.
var checkpoint_radii: PackedFloat32Array = PackedFloat32Array()
## Склад на пути к каждому месту списка или -1. Если список пуст, склад
## с тем же номером, что и место.
var leg_depots: PackedInt32Array = PackedInt32Array()
## Сплошные стены: пары точек «начало, конец» (участок трассы с границами).
var walls: PackedVector2Array = PackedVector2Array()
## Склады топлива и их остатки (раздел 5.5). Остатки — изменяемое состояние
## мира: оно хранится здесь, отдельно от местности и частей.
var world_state: WorldState = WorldState.new()


func _init(p_terrain) -> void:
	terrain = p_terrain


## Добавить машину. heading в радианах: 0 — север, по часовой стрелке.
func add_car(p_params: CarParams, fuel: float, x: float, y: float, heading: float) -> Car:
	var car: Car = Car.new(cars.size(), p_params)
	car.state.x = x
	car.state.y = y
	car.state.heading = heading
	car.state.fuel = clampf(fuel, 0.0, p_params.fuel_capacity)
	car.state.mass = car.sim.total_mass(car.state.fuel)
	cars.append(car)
	return car


## Принять команду: она записывается с номером текущего шага и действует с него.
func submit(command: Command) -> void:
	if command.car_id < 0 or command.car_id >= cars.size():
		return
	command.step_index = step_index
	command_log.append(command)
	cars[command.car_id].apply_command(command)


## Продвинуть заезд на один шаг.
func step() -> void:
	for car in cars:
		car.step(terrain.sample(car.state.x, car.state.y), DT)
		# Препятствия сплошные: после шага машина выталкивается наружу.
		var margin: float = car.sim.params.collision_margin
		var obstacle: Vector3 = terrain.obstacle_near(car.state.x, car.state.y, margin)
		if obstacle.z > 0.0:
			car.collide(obstacle.x, obstacle.y, obstacle.z + margin)
		_collide_walls(car, margin)
		_check_checkpoint(car)
		world_state.try_refuel(car)
	step_index += 1


## Склад, который лежит на пути к месту списка с номером leg, или -1.
func depot_of_leg(leg: int) -> int:
	if leg < 0:
		return -1
	if not leg_depots.is_empty():
		if leg < leg_depots.size():
			return leg_depots[leg]
		return -1
	if leg < world_state.depots.size():
		return leg
	return -1


## Стены сплошные: машина не подходит к стене ближе margin. Ближайшая точка
## стены работает как препятствие радиусом margin.
func _collide_walls(car: Car, margin: float) -> void:
	var index: int = 0
	while index + 1 < walls.size():
		var from: Vector2 = walls[index]
		var axis: Vector2 = walls[index + 1] - from
		var spot: Vector2 = Vector2(car.state.x, car.state.y)
		var along: float = clampf((spot - from).dot(axis) / axis.length_squared(), 0.0, 1.0)
		var nearest: Vector2 = from + axis * along
		if spot.distance_squared_to(nearest) < margin * margin:
			car.collide(nearest.x, nearest.y, margin)
		index += 2


## Точки проходятся по порядку: пропущенная не засчитывается, нужно вернуться.
func _check_checkpoint(car: Car) -> void:
	if car.next_checkpoint >= checkpoints.size():
		return
	var target: Vector2 = checkpoints[car.next_checkpoint]
	var d_east: float = car.state.x - target.x
	var d_north: float = car.state.y - target.y
	var radius: float = checkpoint_radius
	if car.next_checkpoint < checkpoint_radii.size():
		radius = checkpoint_radii[car.next_checkpoint]
	if d_east * d_east + d_north * d_north > radius * radius:
		return
	car.checkpoint_steps.append(step_index)
	car.next_checkpoint += 1
	if car.next_checkpoint == checkpoints.size():
		car.finish_step = step_index


## Место машины в гонке, с единицы. Финишировавшие идут по времени финиша,
## остальные — по числу взятых точек и расстоянию до следующей.
func place_of(car_id: int) -> int:
	var mine: float = _progress(cars[car_id])
	var place: int = 1
	for car in cars:
		if car.id != car_id and _progress(car) > mine:
			place += 1
	return place


## Чем больше, тем выше место.
func _progress(car: Car) -> float:
	if car.finish_step >= 0:
		return 1000000000.0 - car.finish_step
	if car.next_checkpoint >= checkpoints.size():
		return float(car.next_checkpoint) * 100000.0
	var target: Vector2 = checkpoints[car.next_checkpoint]
	var left: float = Vector2(car.state.x, car.state.y).distance_to(target)
	return float(car.next_checkpoint) * 100000.0 - left


## Время заезда, с.
func time_seconds() -> float:
	return step_index * DT
