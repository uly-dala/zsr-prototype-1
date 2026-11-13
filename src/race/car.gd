extends RefCounted
## Машина в заезде: модель, состояние и последние принятые команды.
## Не знает, кто отдаёт команды.
##
## Шаг 1: исполняется только команда MANUAL. Когда она нулевая, машина едет
## прямо по текущему направлению (приоритет 4 из раздела 3.2).
## Автоматика появится здесь на шаге 2.

const CarParams = preload("res://src/sim/car_params.gd")
const CarSim = preload("res://src/sim/car_sim.gd")
const CarState = preload("res://src/sim/car_state.gd")
const CarInput = preload("res://src/sim/car_input.gd")
const TerrainSample = preload("res://src/sim/terrain_sample.gd")
const Command = preload("res://src/sim/command.gd")

var id: int = 0
var sim: CarSim
var state: CarState = CarState.new()
## Последняя команда ручного управления.
var manual: CarInput = CarInput.new()


func _init(p_id: int, p_params: CarParams) -> void:
	id = p_id
	sim = CarSim.new(p_params)
	state.mass = sim.total_mass(state.fuel)


func apply_command(command: Command) -> void:
	if command.type == Command.Type.MANUAL:
		manual.steer = clampf(command.a, -1.0, 1.0)
		manual.throttle = clampf(command.b, -1.0, 1.0)


## Машиной сейчас управляет игрок (или тот, кто отдаёт команды вручную).
func is_manual_active() -> bool:
	return not manual.is_zero()


func step(terrain: TerrainSample, dt: float) -> void:
	sim.step(state, manual, terrain, dt)
