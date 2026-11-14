extends RefCounted
## Таблица гонки из нескольких этапов (раздел 2.3): время каждого на этапе
## и суммарное, порядок и отставания на старте следующего этапа.
## Обычный объект без привязки к сцене.

var names: PackedStringArray = PackedStringArray()
## Суммарное время каждой машины, с.
var totals: PackedFloat64Array = PackedFloat64Array()
## По этапам: время каждой машины, с.
var stage_times: Array = []
## По этапам: доехала ли каждая машина.
var stage_finished: Array = []


func setup(p_names: PackedStringArray) -> void:
	names = p_names
	totals = PackedFloat64Array()
	totals.resize(names.size())
	totals.fill(0.0)
	stage_times = []
	stage_finished = []


func stages_done() -> int:
	return stage_times.size()


## Записать этап. times — время машин, с; finished — кто доехал.
## Не доехавший получает время худшего из доехавших плюс penalty;
## если не доехал никто — fallback_time плюс penalty.
func add_stage(times: PackedFloat64Array, finished: Array, penalty: float, fallback_time: float) -> void:
	var worst: float = -1.0
	for i in times.size():
		if finished[i]:
			worst = maxf(worst, times[i])
	if worst < 0.0:
		worst = fallback_time
	var result: PackedFloat64Array = PackedFloat64Array()
	for i in times.size():
		var time: float = times[i]
		if not finished[i]:
			time = worst + penalty
		result.append(time)
		totals[i] += time
	stage_times.append(result)
	stage_finished.append(finished.duplicate())


## Машины по местам: по суммарному времени, при равенстве — по номеру.
func order() -> PackedInt32Array:
	var list: Array = []
	for i in names.size():
		list.append(i)
	list.sort_custom(_is_ahead)
	return PackedInt32Array(list)


func _is_ahead(a: int, b: int) -> bool:
	if totals[a] != totals[b]:
		return totals[a] < totals[b]
	return a < b


## Место машины, с единицы.
func place_of(car: int) -> int:
	return order().find(car) + 1


## Порядок старта следующего этапа: по суммарному времени, но не доехавшие
## прошлый этап — после всех остальных.
func start_order() -> PackedInt32Array:
	var by_total: PackedInt32Array = order()
	if stage_finished.is_empty():
		return by_total
	var last: Array = stage_finished[stage_finished.size() - 1]
	var result: PackedInt32Array = PackedInt32Array()
	for car in by_total:
		if last[car]:
			result.append(car)
	for car in by_total:
		if not last[car]:
			result.append(car)
	return result


## Задержка старта каждой машины на следующем этапе, с: настоящие отставания
## по суммарному времени, но не больше gap_max между соседними.
func start_delays(gap_max: float) -> PackedFloat64Array:
	var delays: PackedFloat64Array = PackedFloat64Array()
	delays.resize(names.size())
	delays.fill(0.0)
	if stage_times.is_empty():
		return delays
	var sequence: PackedInt32Array = start_order()
	for position in range(1, sequence.size()):
		var car: int = sequence[position]
		var ahead: int = sequence[position - 1]
		var gap: float = clampf(totals[car] - totals[ahead], 0.0, gap_max)
		delays[car] = delays[ahead] + gap
	return delays


static func clock(seconds: float) -> String:
	var whole: int = int(seconds)
	if whole >= 3600:
		return "%d:%02d:%02d" % [int(whole / 3600.0), int(whole / 60.0) % 60, whole % 60]
	return "%d:%02d" % [int(whole / 60.0), whole % 60]


## Строки таблицы: место, имя, время последнего этапа и сумма.
func table_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if stage_times.is_empty():
		return lines
	var last: PackedFloat64Array = stage_times[stage_times.size() - 1]
	var finished: Array = stage_finished[stage_finished.size() - 1]
	var place: int = 1
	for car in order():
		var note: String = ""
		if not finished[car]:
			note = " (не доехал)"
		lines.append("%d. %s: этап %s%s, сумма %s" % [place, names[car], clock(last[car]), note, clock(totals[car])])
		place += 1
	return lines
