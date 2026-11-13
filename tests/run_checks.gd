extends SceneTree
## Запуск автопроверок без окна:
##   Godot --headless --path <папка проекта> --script res://tests/run_checks.gd
## Проще всего через run_checks.bat в корне проекта.
## Итог печатается в консоль и пишется в logs/checks.log.

const Checks = preload("res://tests/checks.gd")


func _init() -> void:
	var checks: Checks = Checks.new()
	checks.run()

	var report: PackedStringArray = PackedStringArray()
	report.append("ZSR, прототип 1: автопроверки, %s" % Time.get_datetime_string_from_system())
	report.append("Godot %s" % Engine.get_version_info().get("string", "?"))
	report.append_array(checks.lines)
	report.append("")
	report.append("Итог: пройдено %d, ошибок %d" % [checks.passed, checks.failed])
	var text: String = "\n".join(report)
	print(text)

	var dir_abs: String = ProjectSettings.globalize_path("res://logs")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var file: FileAccess = FileAccess.open(dir_abs.path_join("checks.log"), FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
		file = null

	var exit_code: int = 0
	if checks.failed > 0 or checks.passed == 0:
		exit_code = 1
	quit(exit_code)
