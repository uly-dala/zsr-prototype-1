extends RefCounted
## Рисунки ориентиров. Одни и те же и на местности, и на карте (раздел 7.3):
## ориентир на карте должен узнаваться на земле.
##
## kind: 0 столб, 1 остов корабля, 2 озеро, 3 кратер, 4 круг камней, 5 маяк.


## canvas — узел, на котором идёт рисование; center — место в его координатах;
## size — размер ориентира в тех же единицах; angle — поворот, радианы.
static func draw(canvas: CanvasItem, kind: int, center: Vector2, size: float, angle: float) -> void:
	match kind:
		0:
			_draw_pillar(canvas, center, size)
		1:
			_draw_wreck(canvas, center, size, angle)
		2:
			_draw_lake(canvas, center, size, angle)
		3:
			_draw_crater(canvas, center, size)
		4:
			_draw_stone_ring(canvas, center, size, angle)
		_:
			_draw_beacon(canvas, center, size)


static func _draw_pillar(canvas: CanvasItem, center: Vector2, size: float) -> void:
	# Длинная тень на юго-восток и тёмная вершина.
	var shadow: PackedVector2Array = PackedVector2Array([
		center + Vector2(-0.6, 0.6) * size,
		center + Vector2(0.6, -0.6) * size,
		center + Vector2(3.4, 2.2) * size,
		center + Vector2(2.2, 3.4) * size,
	])
	canvas.draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.35))
	canvas.draw_circle(center, size, Color(0.22, 0.18, 0.16))
	canvas.draw_circle(center + Vector2(-0.25, -0.25) * size, size * 0.55, Color(0.62, 0.55, 0.48))


static func _draw_wreck(canvas: CanvasItem, center: Vector2, size: float, angle: float) -> void:
	# Вытянутый корпус с рёбрами.
	var along: Vector2 = Vector2(cos(angle), sin(angle)) * size
	var across: Vector2 = Vector2(-sin(angle), cos(angle)) * size * 0.3
	var hull: PackedVector2Array = PackedVector2Array([
		center - along + across * 0.6,
		center - along * 0.5 + across,
		center + along * 0.6 + across,
		center + along,
		center + along * 0.6 - across,
		center - along * 0.5 - across,
		center - along - across * 0.6,
	])
	canvas.draw_colored_polygon(hull, Color(0.48, 0.30, 0.20))
	for rib in 4:
		var offset: Vector2 = along * (-0.5 + rib * 0.33)
		canvas.draw_line(center + offset + across, center + offset - across, Color(0.16, 0.12, 0.10), size * 0.06)


static func _draw_lake(canvas: CanvasItem, center: Vector2, size: float, angle: float) -> void:
	# Два перекрывающихся круга дают неровный берег.
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * size * 0.45
	canvas.draw_circle(center - offset * 0.5, size * 0.8, Color(0.16, 0.36, 0.52))
	canvas.draw_circle(center + offset, size * 0.6, Color(0.16, 0.36, 0.52))
	canvas.draw_circle(center - offset * 0.3, size * 0.45, Color(0.24, 0.48, 0.66))


static func _draw_crater(canvas: CanvasItem, center: Vector2, size: float) -> void:
	canvas.draw_circle(center, size, Color(0.56, 0.48, 0.40))
	canvas.draw_circle(center, size * 0.72, Color(0.14, 0.11, 0.10))
	canvas.draw_circle(center + Vector2(0.12, 0.12) * size, size * 0.5, Color(0.24, 0.20, 0.17))


static func _draw_stone_ring(canvas: CanvasItem, center: Vector2, size: float, angle: float) -> void:
	for stone in 7:
		var direction: float = angle + TAU * stone / 7.0
		canvas.draw_circle(center + Vector2(cos(direction), sin(direction)) * size, size * 0.2, Color(0.80, 0.78, 0.72))


static func _draw_beacon(canvas: CanvasItem, center: Vector2, size: float) -> void:
	# Красный треугольник с белой серединой, видимый издалека.
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -1.6) * size,
		center + Vector2(1.4, 1.0) * size,
		center + Vector2(-1.4, 1.0) * size,
	])
	canvas.draw_colored_polygon(triangle, Color(0.85, 0.20, 0.15))
	canvas.draw_circle(center, size * 0.45, Color(1.0, 0.96, 0.85))
