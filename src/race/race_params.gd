extends Resource
## Формат заезда (раздел 2.1): это данные, а не код. Формат — список этапов;
## каждый этап — местность из генератора со своим зерном и одним набором чисел.

## Название формата на экране.
@export var title: String = "Короткий"
## Числа местности и маршрута, общие для всех этапов формата: WorldGenParams.
@export var world: Resource
## Зёрна генератора: по одному на этап. Сколько зёрен, столько этапов.
@export var seeds: PackedInt32Array = PackedInt32Array([1])

@export_group("Этапы")
## Наибольший разрыв между соседними машинами на старте этапа, с (раздел 2.3).
@export var start_gap_max: float = 60.0
## Машина без топлива получает время худшего финишировавшего плюс столько, с.
@export var dnf_penalty: float = 300.0
## Сколько секунд на километр маршрута даётся на этап. Кто не уложился,
## считается не доехавшим.
@export var time_limit_per_km: float = 90.0


func stage_count() -> int:
	return seeds.size()


## Числа местности этапа с номером index, с нуля: WorldGenParams.
func stage_world(index: int) -> Resource:
	var result: Resource = world.duplicate()
	result.world_seed = seeds[index]
	return result
