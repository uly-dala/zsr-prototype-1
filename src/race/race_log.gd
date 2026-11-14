extends RefCounted
## Журнал заезда одной машины для разбора после финиша (раздел 7.5):
## истинный путь, топливо и скорость по времени, места манёвров, ударов
## и заправок, время и путь по отрезкам. Здесь же копятся числа для
## критериев успеха из раздела 10.

const Car = preload("res://src/race/car.gd")
const Command = preload("res://src/sim/command.gd")

## Путь и графики пишутся раз в столько шагов: 30 шагов — дважды в секунду.
const SAMPLE_EVERY: int = 30

## Истинный путь: x — восток, y — север, м.
var path: PackedVector2Array = PackedVector2Array()
## Графики: время (с), топливо (кг), скорость (км/ч).
var times: PackedFloat32Array = PackedFloat32Array()
var fuel: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
## События: словари с ключами kind, time, x, y.
## kind: "maneuver" — начало объезда на A или D, "hit" — удар,
## "refuel" — заправка, "checkpoint" — контрольная точка.
var events: Array = []
## Отрезки маршрута: словари с ключами time (с) и distance (м) — сколько
## времени и пути ушло на отрезок до очередной контрольной точки.
var legs: Array = []

## Время заезда игрока на момент его конца, с.
var end_time: float = 0.0
## Счётчики шагов для критериев успеха.
var steps: int = 0
var manual_steps: int = 0
var map_steps: int = 0
var consumption_steps: int = 0
var map_opens: int = 0
## В заезде использовались отладочные клавиши: повтор его не воспроизведёт.
var debug_used: bool = false

var _seen_hits: int = 0
var _seen_refuels: int = 0
var _seen_checkpoint: int = 0
var _was_steering: bool = false
var _was_map_open: bool = false
var _leg_start_time: float = 0.0
var _leg_start_distance: float = 0.0


## Вызывается после каждого шага симуляции.
func record(step_index: int, time: float, car: Car, map_open: bool) -> void:
	var state = car.state
	steps += 1
	if car.is_manual_active():
		manual_steps += 1
	if map_open:
		map_steps += 1
		if not _was_map_open:
			map_opens += 1
	_was_map_open = map_open
	if car.target_mode == Command.TargetMode.CONSUMPTION:
		consumption_steps += 1

	var steering: bool = car.manual.steer != 0.0
	if steering and not _was_steering:
		_add_event("maneuver", time, state.x, state.y)
	_was_steering = steering
	if car.hits != _seen_hits:
		_seen_hits = car.hits
		_add_event("hit", time, state.x, state.y)
	if car.refuels != _seen_refuels:
		_seen_refuels = car.refuels
		_add_event("refuel", time, state.x, state.y)
	if car.next_checkpoint != _seen_checkpoint:
		_seen_checkpoint = car.next_checkpoint
		_add_event("checkpoint", time, state.x, state.y)
		legs.append({"time": time - _leg_start_time, "distance": state.distance - _leg_start_distance})
		_leg_start_time = time
		_leg_start_distance = state.distance

	if step_index % SAMPLE_EVERY == 0:
		_sample(time, state)


## Последняя точка пути и графиков: вызывается в конце заезда.
func close(time: float, car: Car) -> void:
	end_time = time
	_sample(time, car.state)


func count(kind: String) -> int:
	var total: int = 0
	for event in events:
		if event["kind"] == kind:
			total += 1
	return total


## Доля шагов от всего заезда, от 0 до 1.
func share(counted_steps: int) -> float:
	if steps <= 0:
		return 0.0
	return float(counted_steps) / steps


func _sample(time: float, state) -> void:
	path.append(Vector2(state.x, state.y))
	times.append(time)
	fuel.append(state.fuel)
	speed.append(state.speed() * 3.6)


func _add_event(kind: String, time: float, x: float, y: float) -> void:
	events.append({"kind": kind, "time": time, "x": x, "y": y})
