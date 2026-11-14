extends RefCounted
## Источник команд «запись повтора» (раздел 9.2). Список команд всех машин
## с номерами шагов вместе с начальным состоянием — это и есть повтор:
## та же сборка игры воспроизводит по нему заезд точно.

const Command = preload("res://src/sim/command.gd")

var _commands: Array = []
var _next: int = 0


## commands — журнал команд RaceSim.command_log или прочитанный из файла.
func _init(commands: Array) -> void:
	_commands = commands
	_next = 0


## Вызывается перед каждым шагом: отдаёт команды, принятые на этом шаге.
func feed(sim) -> void:
	while _next < _commands.size() and _commands[_next].step_index <= sim.step_index:
		var source: Command = _commands[_next]
		sim.submit(Command.new(source.type, source.car_id, source.a, source.b, source.active))
		_next += 1


func is_finished() -> bool:
	return _next >= _commands.size()


## Журнал команд -> данные для файла.
static func commands_to_data(commands: Array) -> Array:
	var data: Array = []
	for command in commands:
		data.append([command.step_index, command.car_id, command.type, command.a, command.b, command.active])
	return data


## Данные из файла -> журнал команд.
static func commands_from_data(data: Array) -> Array:
	var commands: Array = []
	for row in data:
		var command: Command = Command.new(int(row[2]), int(row[1]), float(row[3]), float(row[4]), bool(row[5]))
		command.step_index = int(row[0])
		commands.append(command)
	return commands
