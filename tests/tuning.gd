extends RefCounted
## Прогоны для настройки чисел короткого формата (шаг 10). Запуск:
## run_tuning.bat. Итог пишется в logs/tuning.log.
##
## Здесь нет проверок «прошло / не прошло»: это измерения. По ним решается,
## какие числа менять в data/*.tres.

const CarParams = preload("res://src/sim/car_params.gd")
const SurfaceParams = preload("res://src/sim/surface_params.gd")
const CarSim = preload("res://src/sim/car_sim.gd")
const Command = preload("res://src/sim/command.gd")
const RaceSim = preload("res://src/race/race_sim.gd")
const WorldGenParams = preload("res://src/world/world_gen_params.gd")
const GeneratedTerrain = preload("res://src/world/generated_terrain.gd")
const StageLayout = preload("res://src/world/stage_layout.gd")
const RaceParams = preload("res://src/race/race_params.gd")
const AiParams = preload("res://src/input/ai_params.gd")
const AiInput = preload("res://src/input/ai_input.gd")

## Наибольшая длительность одного заезда: 20 минут игрового времени.
const STEP_LIMIT: int = 72000

var lines: PackedStringArray = PackedStringArray()

var _car: CarParams
var _hard: SurfaceParams
var _sand: SurfaceParams
var _slick: SurfaceParams
var _base: WorldGenParams
var _ai: AiParams


func run() -> void:
	_car = load("res://data/car_default.tres") as CarParams
	_hard = load("res://data/surface_hard.tres") as SurfaceParams
	_sand = load("res://data/surface_sand.tres") as SurfaceParams
	_slick = load("res://data/surface_slick.tres") as SurfaceParams
	_base = load("res://data/world_default.tres") as WorldGenParams
	_ai = load("res://data/ai_default.tres") as AiParams
	_terrain_cost()
	_strategies()
	_full_races()
	_long_formats()


func _say(text: String) -> void:
	lines.append(text)
	print(text)


## Параметры мира с заменами: словарь «имя свойства -> значение».
func _world_params(changes: Dictionary) -> WorldGenParams:
	var result: WorldGenParams = _base.duplicate() as WorldGenParams
	for key in changes:
		result.set(key, changes[key])
	return result


func _describe(changes: Dictionary) -> String:
	if changes.is_empty():
		return "как сейчас"
	var parts: PackedStringArray = PackedStringArray()
	for key in changes:
		parts.append("%s=%s" % [key, str(changes[key])])
	return ", ".join(parts)


# --- 1. Во сколько раз местность дороже ровного грунта -------------------------

## Одна машина без препятствий держит скорость и едет по прямой 8 км на север
## по трём параллельным линиям. Расход сравнивается с расчётом для ровного грунта.
func _terrain_cost() -> void:
	_say("")
	_say("== 1. Цена местности: расход на км против ровного твёрдого грунта, без препятствий")
	var variants: Array = [
		{},
		{"height_amplitude": 0.0, "sand_threshold": 2.0},
	]
	var model: CarSim = CarSim.new(_car)
	for changes in variants:
		var text: String = ""
		for speed_kmh in [90.0, 108.0]:
			var used: float = 0.0
			var driven: float = 0.0
			var climbed: float = 0.0
			var on_sand: float = 0.0
			for line_x in [-1500.0, 0.0, 1500.0]:
				var probe: Dictionary = changes.duplicate()
				probe["obstacle_density"] = 0.0
				probe["slick_count"] = 0
				var world: GeneratedTerrain = GeneratedTerrain.new(_world_params(probe), _hard, _sand, _slick)
				var race: RaceSim = RaceSim.new(world)
				var car = race.add_car(_car, 500.0, line_x, 0.0, 0.0)
				race.submit(Command.new(Command.Type.SET_TARGET, 0, Command.TargetMode.SPEED, speed_kmh))
				race.submit(Command.new(Command.Type.SET_COURSE, 0, 0.0, 0.0, true))
				var last_height: float = world.height_at(line_x, 0.0)
				var sand_steps: int = 0
				while car.state.y < 8000.0 and car.state.fuel > 0.0 and race.step_index < STEP_LIMIT:
					race.step()
					if race.step_index % 30 == 0:
						var height: float = world.height_at(car.state.x, car.state.y)
						climbed += maxf(0.0, height - last_height)
						last_height = height
						if world.sand_at(car.state.x, car.state.y) > 0.5:
							sand_steps += 1
				used += 500.0 - car.state.fuel
				driven += car.state.distance
				on_sand += sand_steps * 30.0 / maxf(1.0, race.step_index)
			var per_km: float = used / maxf(driven, 1.0) * 1000.0
			var flat: float = model.consumption_for_speed(speed_kmh / 3.6, 1250.0, _hard) / 60.0 / (speed_kmh / 3.6) * 1000.0
			text += "   %d км/ч: %.1f кг/км (ровный %.1f, в %.2f раза), подъём %.0f м/км, песок %.0f %%" % [
				int(speed_kmh), per_km, flat, per_km / flat, climbed / maxf(driven, 1.0) * 1000.0, on_sand / 3.0 * 100.0,
			]
		_say("%s:%s" % [_describe(changes), text])


# --- Общий заезд ----------------------------------------------------------------

## Заезд соперников без игрока. racers — словари с ключами kind, и по желанию
## cruise (км/ч), fuel (кг), refuels (предел заправок).
## Возвращает словарь: cars — итоги машин, stock — остатки складов.
func _race(world_params: WorldGenParams, racers: Array, step_limit: int = STEP_LIMIT) -> Dictionary:
	var layout: StageLayout = StageLayout.new(world_params)
	var world: GeneratedTerrain = GeneratedTerrain.new(world_params, _hard, _sand, _slick, layout.clear_zones())
	var race: RaceSim = RaceSim.new(world)
	world.set_extra_obstacles(layout.track_obstacles)
	layout.apply_to(race)
	race.world_state.setup(layout.depots, world_params.depot_stock, world_params.depot_portion,
		world_params.depot_radius, world_params.depot_max_speed)
	var rivals: Array = []
	var numbers: Array = [0, 0, 0]
	for racer in racers:
		var kind: int = racer["kind"]
		numbers[kind] += 1
		var rival: AiInput = AiInput.new(race.cars.size(), kind, numbers[kind], _ai, world_params.world_seed)
		if racer.has("cruise"):
			rival.cruise_speed = racer["cruise"]
		if racer.has("refuels"):
			rival.max_refuels = racer["refuels"]
		var fuel: float = rival.start_fuel()
		if racer.has("fuel"):
			fuel = racer["fuel"]
		race.add_car(_car, fuel, (rivals.size() - racers.size() * 0.5) * 7.0, 0.0, 0.0)
		rivals.append(rival)
	var running: bool = true
	while running and race.step_index < step_limit:
		for rival in rivals:
			rival.decide(race, world, layout.landmarks)
		race.step()
		if race.step_index % 600 == 0:
			running = false
			for car in race.cars:
				if car.finish_step < 0 and (car.state.fuel > 0.0 or car.state.speed() > 0.5):
					running = true
	var results: Array = []
	for rival in rivals:
		var car = race.cars[rival.car_id]
		results.append({
			"kind": rival.kind,
			"title": rival.title,
			"cruise": rival.cruise_speed,
			"finished": car.finish_step >= 0,
			"time": car.finish_step * RaceSim.DT,
			"points": layout.checkpoints_among(car.next_checkpoint),
			"fuel": car.state.fuel,
			"distance": car.state.distance,
			"refuels": car.refuels,
			"taken": car.fuel_taken,
			"hits": car.hits,
		})
	return {"cars": results, "stock": race.world_state.stock, "route": layout.route_length}


func _clock(seconds: float) -> String:
	var whole: int = int(seconds)
	return "%d:%02d" % [int(whole / 60.0), whole % 60]


# --- 2. Три стратегии из раздела 6 ----------------------------------------------

## Каждая стратегия едет одна, склады полные. Критерий раздела 10: лучшие
## времена трёх стратегий отличаются не больше чем на 5 %.
func _strategies() -> void:
	_say("")
	_say("== 2. Три стратегии в одиночку: время, остаток топлива, заправки, удары")
	var strategies: Array = [
		{"name": "полный бак, 80 км/ч, без заправки", "kind": AiInput.Kind.ECONOMY, "cruise": 80.0, "fuel": 500.0, "refuels": 0},
		{"name": "полный бак, 90 км/ч, без заправки", "kind": AiInput.Kind.ECONOMY, "cruise": 90.0, "fuel": 500.0, "refuels": 0},
		{"name": "полный бак, 108 км/ч, одна заправка", "kind": AiInput.Kind.MIDDLE, "cruise": 108.0, "fuel": 500.0, "refuels": 1},
		{"name": "300 кг, 120 км/ч, две заправки", "kind": AiInput.Kind.SPRINTER, "cruise": 120.0, "fuel": 300.0, "refuels": 2},
		{"name": "300 кг, 120 км/ч, заправки без предела", "kind": AiInput.Kind.SPRINTER, "cruise": 120.0, "fuel": 300.0, "refuels": -1},
	]
	var worlds: Array = [
		{},
		{"obstacle_density": 120.0},
		{"depot_detour_min": 900.0, "depot_detour_max": 1800.0},
	]
	for changes in worlds:
		_say("-- местность: %s" % _describe(changes))
		for strategy in strategies:
			var text: String = ""
			var best: float = 0.0
			var finished: int = 0
			for seed_value in [1, 2, 3, 4, 5]:
				var probe: Dictionary = changes.duplicate()
				probe["world_seed"] = seed_value
				var outcome: Dictionary = _race(_world_params(probe), [strategy])
				var car: Dictionary = outcome["cars"][0]
				if car["finished"]:
					finished += 1
					if best == 0.0 or car["time"] < best:
						best = car["time"]
					text += "  %s/%dкг/з%d/у%d" % [_clock(car["time"]), int(car["fuel"]), car["refuels"], car["hits"]]
				else:
					text += "  НЕТ(т%d,%.1fкм,з%d,у%d)" % [car["points"], car["distance"] / 1000.0, car["refuels"], car["hits"]]
			_say("%s: доехало %d из 5, лучшее %s |%s" % [strategy["name"], finished, _clock(best), text])


# --- 3. Девять соперников --------------------------------------------------------

func _full_races() -> void:
	_say("")
	_say("== 3. Девять соперников: сколько доехало по типам, лучшее время типа, остатки складов")
	var racers: Array = []
	for kind in 3:
		for number in 3:
			racers.append({"kind": kind})
	var worlds: Array = [
		{},
		{"obstacle_density": 120.0},
		{"depot_stock": 1200.0},
	]
	for changes in worlds:
		_say("-- местность: %s" % _describe(changes))
		for seed_value in [1, 2, 3]:
			var probe: Dictionary = changes.duplicate()
			probe["world_seed"] = seed_value
			var outcome: Dictionary = _race(_world_params(probe), racers)
			var finished: Array = [0, 0, 0]
			var best: Array = [0.0, 0.0, 0.0]
			var hits: int = 0
			var taken: float = 0.0
			for car in outcome["cars"]:
				hits += car["hits"]
				taken += car["taken"]
				if car["finished"]:
					finished[car["kind"]] += 1
					if best[car["kind"]] == 0.0 or car["time"] < best[car["kind"]]:
						best[car["kind"]] = car["time"]
			var stock_text: String = ""
			for value in outcome["stock"]:
				stock_text += " %d" % int(value)
			_say("зерно %d: доехало спринтеров %d, середняков %d, экономных %d | лучшее %s, %s, %s | ударов %d, взято %d кг, склады:%s" % [
				seed_value, finished[0], finished[1], finished[2], _clock(best[0]), _clock(best[1]), _clock(best[2]),
				hits, int(taken), stock_text,
			])


# --- 4. Длинные форматы ----------------------------------------------------------

## Девять соперников на этапе формата «Этапы» и на марафоне: кто доехал,
## за сколько, сколько заправок и что осталось на складах.
func _long_formats() -> void:
	_say("")
	_say("== 4. Длинные форматы: девять соперников, без игрока")
	var racers: Array = []
	for kind in 3:
		for number in 3:
			racers.append({"kind": kind})
	for path in ["res://data/format_stages.tres", "res://data/format_marathon.tres"]:
		var format: RaceParams = load(path) as RaceParams
		if format == null or format.world == null:
			_say("файл формата не загрузился: %s" % path)
			continue
		var stages: int = mini(format.stage_count(), 2)
		for stage in stages:
			var world_params: WorldGenParams = format.stage_world(stage) as WorldGenParams
			var limit: int = int(world_params.route_length / 1000.0 * format.time_limit_per_km * 60.0)
			var started: int = Time.get_ticks_msec()
			var outcome: Dictionary = _race(world_params, racers, limit)
			_say("-- %s, этап %d: маршрут %.1f км, расчёт %.0f с" % [format.title, stage + 1,
				outcome["route"] / 1000.0, (Time.get_ticks_msec() - started) / 1000.0])
			for car in outcome["cars"]:
				var status: String = "НЕ ДОЕХАЛ, точек %d, топливо %d кг" % [car["points"], int(car["fuel"])]
				if car["finished"]:
					status = "финиш %s, топливо %d кг" % [_long_clock(car["time"]), int(car["fuel"])]
				_say("%s, %d км/ч: %s, путь %.1f км, заправок %d (%d кг), ударов %d" % [car["title"], int(car["cruise"]),
					status, car["distance"] / 1000.0, car["refuels"], int(car["taken"]), car["hits"]])
			var stock_text: String = ""
			for value in outcome["stock"]:
				stock_text += " %d" % int(value)
			_say("остатки на складах, кг:%s" % stock_text)


func _long_clock(seconds: float) -> String:
	var whole: int = int(seconds)
	if whole >= 3600:
		return "%d:%02d:%02d" % [int(whole / 3600.0), int(whole / 60.0) % 60, whole % 60]
	return "%d:%02d" % [int(whole / 60.0), whole % 60]
