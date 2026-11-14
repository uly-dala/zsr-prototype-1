extends RefCounted
## Изменяемое состояние мира (раздел 9.3): остатки топлива на складах.
## Запас склада общий и конечный: первые машины получают полную порцию,
## остальным достаётся остаток или ничего (раздел 5.5).

## Склады: x — восток, y — север.
var depots: PackedVector2Array = PackedVector2Array()
## Остаток на каждом складе, кг.
var stock: PackedFloat32Array = PackedFloat32Array()
var depot_radius: float = 15.0
## Сколько машина забирает за раз, кг.
var portion: float = 200.0
## Забрать топливо можно медленнее этой скорости, м/с.
var max_speed: float = 30.0 / 3.6


## Расставить склады с полным запасом.
func setup(p_depots: PackedVector2Array, p_stock: float, p_portion: float, p_radius: float, max_speed_kmh: float) -> void:
	depots = p_depots
	stock = PackedFloat32Array()
	stock.resize(depots.size())
	stock.fill(p_stock)
	portion = p_portion
	depot_radius = p_radius
	max_speed = max_speed_kmh / 3.6


## Номер склада, в круге которого стоит точка (x, y), или -1.
func depot_at(x: float, y: float) -> int:
	for i in depots.size():
		var d_east: float = x - depots[i].x
		var d_north: float = y - depots[i].y
		if d_east * d_east + d_north * d_north <= depot_radius * depot_radius:
			return i
	return -1


## Машина car (Car) проезжает склад медленнее max_speed: забирает порцию,
## но не больше свободного места в баке и остатка. С одного склада — один раз.
## Возвращает взятое, кг.
func try_refuel(car) -> float:
	if depots.is_empty():
		return 0.0
	var depot: int = depot_at(car.state.x, car.state.y)
	if depot < 0 or car.depots_used.has(depot):
		return 0.0
	if car.state.speed() > max_speed:
		return 0.0
	var space: float = car.sim.params.fuel_capacity - car.state.fuel
	var amount: float = minf(minf(portion, space), stock[depot])
	if amount <= 0.0:
		return 0.0
	stock[depot] -= amount
	car.state.fuel += amount
	car.state.mass = car.sim.total_mass(car.state.fuel)
	car.depots_used[depot] = true
	car.refuels += 1
	car.fuel_taken += amount
	return amount
