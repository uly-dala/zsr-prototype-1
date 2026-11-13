extends RefCounted
## Источник команд «игрок». Опрашивает клавиатуру и отдаёт симуляции команды;
## команда отправляется только когда ввод изменился, поэтому запись повтора короткая.
##
## Клавиши читаются по физическому положению, так что WASD работает
## при любой раскладке клавиатуры.
## A и D поворачивают руль относительно машины (раздел 3.1).

const Command = preload("res://src/sim/command.gd")

var car_id: int = 0
var _last_steer: float = 0.0
var _last_throttle: float = 0.0


func _init(p_car_id: int) -> void:
	car_id = p_car_id


## Вызывается перед каждым шагом симуляции. sim — RaceSim.
func poll(sim) -> void:
	var steer: float = 0.0
	if Input.is_physical_key_pressed(KEY_D):
		steer += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		steer -= 1.0
	var throttle: float = 0.0
	if Input.is_physical_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		throttle -= 1.0
	if steer != _last_steer or throttle != _last_throttle:
		_last_steer = steer
		_last_throttle = throttle
		sim.submit(Command.new(Command.Type.MANUAL, car_id, steer, throttle))


## Колесо мыши: изменить заданную скорость или расход на steps шагов.
func adjust_target(sim, steps: int) -> void:
	var car = sim.cars[car_id]
	var value: float = car.target_value + steps * car.target_step(car.target_mode)
	value = clampf(value, 0.0, car.max_target(car.target_mode))
	if value != car.target_value:
		sim.submit(Command.new(Command.Type.SET_TARGET, car_id, car.target_mode, value))


## Tab: переключить режим «скорость / расход». Новое заданное значение берётся
## из текущего движения машины и округляется до шага, чтобы переключение
## не вызывало рывка.
func toggle_mode(sim) -> void:
	var car = sim.cars[car_id]
	var mode: int = Command.TargetMode.CONSUMPTION
	var current: float = car.state.consumption
	if car.target_mode == Command.TargetMode.CONSUMPTION:
		mode = Command.TargetMode.SPEED
		current = car.state.speed() * 3.6
	var step_size: float = car.target_step(mode)
	var value: float = clampf(round(current / step_size) * step_size, 0.0, car.max_target(mode))
	sim.submit(Command.new(Command.Type.SET_TARGET, car_id, mode, value))
