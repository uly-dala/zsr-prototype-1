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
