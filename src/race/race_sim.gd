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
		_check_checkpoint(car)
		world_state.try_refuel(car)
	step_index += 1


## Точки проходятся по порядку: пропущенная не засчитывается, нужно вернуться.
func _check_checkpoint(car: Car) -> void:
	if car.next_checkpoint >= checkpoints.size():
		return
	var target: Vector2 = checkpoints[car.next_checkpoint]
	var d_east: float = car.state.x - target.x
	var d_north: float = car.state.y - target.y
	if d_east * d_east + d_north * d_north > checkpoint_radius * checkpoint_radius:
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
