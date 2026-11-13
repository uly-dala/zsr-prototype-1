extends RefCounted
## Запись заезда в CSV (раздел 9.5). Из этих файлов считаются критерии успеха.
## При запуске из редактора файлы лежат в папке logs проекта,
## в собранной игре — в user://logs.

const Car = preload("res://src/race/car.gd")
const Command = preload("res://src/sim/command.gd")

## Строка пишется раз в столько шагов: 6 шагов — 10 строк в секунду.
const SAMPLE_EVERY: int = 6
const HEADER: String = "step,time_s,x_m,y_m,heading_deg,speed_kmh,fuel_kg,mass_kg,consumption_kg_min,control,steer,throttle,lateral_ratio,surface,map_open,target_mode,target_value,auto_throttle"

var path: String = ""
var _file: FileAccess = null


func is_recording() -> bool:
	return _file != null


func start() -> void:
	stop()
	var dir_path: String = "user://logs"
	if OS.has_feature("editor"):
		dir_path = "res://logs"
	var dir_abs: String = ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	path = dir_abs.path_join("race_%s.csv" % stamp)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Не удалось открыть файл записи заезда: %s" % path)
		path = ""
		return
	_file.store_line(HEADER)


func stop() -> void:
	# Файл закрывается, когда на него не остаётся ссылок.
	_file = null


## Вызывается после каждого шага симуляции; пишет каждую SAMPLE_EVERY-ю строку.
func sample(step_index: int, time_s: float, car: Car, surface_id: String, map_open: bool) -> void:
	if _file == null or step_index % SAMPLE_EVERY != 0:
		return
	var s = car.state
	var control: String = "auto"
	if car.is_manual_active():
		control = "manual"
	var mode: String = "speed"
	if car.target_mode == Command.TargetMode.CONSUMPTION:
		mode = "consumption"
	_file.store_line("%d,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.1f,%.2f,%s,%.2f,%.2f,%.3f,%s,%d,%s,%.1f,%d" % [
		step_index, time_s, s.x, s.y, s.heading_deg(), s.speed() * 3.6, s.fuel, s.mass,
		s.consumption, control, s.steer, car.manual.throttle, s.lateral_ratio, surface_id,
		1 if map_open else 0, mode, car.target_value, 1 if car.auto_throttle else 0,
	])
