extends Resource
## Параметры покрытия. Дизайн-документ, раздел 5.1.

## Короткое имя для записей заезда.
@export var id: String = "hard"
## Название для экрана.
@export var title: String = "Твёрдый грунт"
## Коэффициент сопротивления качению.
@export var rolling_coefficient: float = 0.03
## Сцепление, доля от твёрдого грунта.
@export var grip: float = 1.0
## Цвет земли на экране.
@export var color: Color = Color(0.33, 0.27, 0.21)
