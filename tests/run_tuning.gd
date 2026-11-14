extends SceneTree
## Прогоны для настройки чисел. Запуск без окна:
##   Godot --headless --path <папка проекта> --script res://tests/run_tuning.gd
## Проще всего через run_tuning.bat. Итог печатается в консоль и пишется
## в logs/tuning.log. Прогон занимает несколько минут.

const Tuning = preload("res://tests/tuning.gd")


func _init() -> void:
	var started: int = Time.get_ticks_msec()
	var tuning: Tuning = Tuning.new()
	print("ZSR, прототип 1: прогоны для настройки. Это займёт несколько минут.")
	tuning.run()
	var report: PackedStringArray = PackedStringArray()
	report.append("ZSR, прототип 1: прогоны для настройки, %s" % Time.get_datetime_string_from_system())
	report.append_array(tuning.lines)
	report.append("")
	report.append("Расчёт занял %.0f с" % ((Time.get_ticks_msec() - started) / 1000.0))
	var dir_abs: String = ProjectSettings.globalize_path("res://logs")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var file: FileAccess = FileAccess.open(dir_abs.path_join("tuning.log"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(report) + "\n")
		file = null
	quit(0)
