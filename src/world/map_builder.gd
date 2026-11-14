extends RefCounted
## Картинка карты заезда (раздел 9.4): строится один раз перед стартом
## из слоя данных. Функции чистые, их можно вызывать из фоновых потоков.
## Большая карта строится полосами в нескольких потоках сразу.
##
## На картинке: покрытия, отмывка и горизонтали. Контрольные точки, ориентиры,
## сетка и стрелки ветра рисуются поверх на экране карты.


## Размер картинки в пикселях для прямоугольника местности.
static func image_size(terrain, area_min: Vector2, area_max: Vector2) -> Vector2i:
	var step_size: float = terrain.params.map_meters_per_pixel
	return Vector2i(
		maxi(1, int(round((area_max.x - area_min.x) / step_size))),
		maxi(1, int(round((area_max.y - area_min.y) / step_size))))


## terrain — GeneratedTerrain. Картинка покрывает прямоугольник от area_min
## (юго-запад) до area_max (северо-восток); верхняя строка — север.
static func build_image(terrain, area_min: Vector2, area_max: Vector2) -> Image:
	var size: Vector2i = image_size(terrain, area_min, area_max)
	return assemble(size, [build_band(terrain, area_min, area_max, 0, size.y)])


## Собрать картинку из полос, идущих сверху вниз.
static func assemble(size: Vector2i, bands: Array) -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	for band in bands:
		bytes.append_array(band)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, bytes)


## Полоса картинки: строки от row_from до row_to, не включая row_to.
## Возвращает по три байта на пиксель.
static func build_band(terrain, area_min: Vector2, area_max: Vector2, row_from: int, row_to: int) -> PackedByteArray:
	var step_size: float = terrain.params.map_meters_per_pixel
	var interval: float = terrain.params.map_contour_interval
	var width: int = image_size(terrain, area_min, area_max).x
	var rows: int = row_to - row_from

	# Высоты в узлах сетки: на один ряд и столбец больше, чем пикселей.
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize((width + 1) * (rows + 1))
	for row in rows + 1:
		var north: float = area_max.y - (row_from + row) * step_size
		for column in width + 1:
			heights[row * (width + 1) + column] = terrain.height_at(area_min.x + column * step_size, north)

	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(width * rows * 3)
	var index: int = 0
	for row in rows:
		var north: float = area_max.y - (row_from + row + 0.5) * step_size
		for column in width:
			var east: float = area_min.x + (column + 0.5) * step_size
			var here: float = heights[row * (width + 1) + column]
			var to_east: float = heights[row * (width + 1) + column + 1]
			var to_south: float = heights[(row + 1) * (width + 1) + column]
			var color: Color = terrain.hard.color
			var on_field: bool = terrain.field_at(east, north) >= 0
			if on_field:
				color = terrain.slick.color
			elif terrain.sand_at(east, north) > 0.5:
				color = terrain.sand.color
			if not on_field:
				# Отмывка: свет с северо-запада.
				var shade: float = clampf(((to_east - here) + (to_south - here)) / step_size * 2.2, -0.3, 0.3)
				color = color * (1.0 + shade)
				# Горизонталь проходит между соседними пикселями.
				var level: float = floor(here / interval)
				if level != floor(to_east / interval) or level != floor(to_south / interval):
					color = color * 0.68
			bytes[index] = int(clampf(color.r, 0.0, 1.0) * 255.0)
			bytes[index + 1] = int(clampf(color.g, 0.0, 1.0) * 255.0)
			bytes[index + 2] = int(clampf(color.b, 0.0, 1.0) * 255.0)
			index += 3
	return bytes
