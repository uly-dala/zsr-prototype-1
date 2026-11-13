extends RefCounted
## Вход модели машины (раздел 9.6): руль и газ с тормозом.

## Руль от -1 (влево) до 1 (вправо) относительно машины.
var steer: float = 0.0
## Газ и тормоз: от -1 (полный тормоз) до 1 (полный газ).
var throttle: float = 0.0


func is_zero() -> bool:
	return steer == 0.0 and throttle == 0.0
