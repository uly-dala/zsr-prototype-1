extends RefCounted
## Симуляция заезда без привязки к сцене: местность, машины, счёт шагов.
## Обычный объект, а не узел: один и тот же код работает в игре, в тестах
## без окна, при ускорении времени и при воспроизведении повтора.

const CarParams = preload("res://src/sim/car_params.gd")
const Car = preload("res://src/race/car.gd")
const Command = preload("res://src/sim/command.gd")

## Шагов симуляции в секунду (раздел 9.1).
const STEPS_PER_SECOND: int = 60
const DT: float = 1.0 / 60.0

## Слой данных местности: объект с функциями sample(x, y) и obstacle_near(x, y, margin).
var terrain
var cars: Array = []
var step_index: int = 0
## Все принятые команды с номерами шагов. Вместе с начальным состоянием это повтор.
var command_log: Array = []


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
	step_index += 1


## Время заезда, с.
func time_seconds() -> float:
	return step_index * DT
