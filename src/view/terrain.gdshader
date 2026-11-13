shader_type canvas_item;
// Картинка части местности. Текстура части — данные слоя местности:
// R — высота в метрах, G — песок (0–1), B — скользкое (0–1),
// A — направление ветра на скользком поле (доля круга, 0 — на север).
// Рельеф показан горизонталями и отмывкой (раздел 5.2).

uniform vec3 hard_color : source_color = vec3(0.33, 0.27, 0.21);
uniform vec3 sand_color : source_color = vec3(0.6, 0.5, 0.33);
uniform vec3 slick_color : source_color = vec3(0.5, 0.58, 0.63);
uniform float cells = 128.0;
uniform float chunk_size = 512.0;
uniform float contour_interval = 5.0;
// Левый верхний угол части в мире, м: нужен, чтобы узоры не рвались на стыках.
uniform vec2 origin = vec2(0.0, 0.0);

void fragment() {
	float texels = cells + 1.0;
	float texel = 1.0 / texels;
	float cell = chunk_size / cells;
	vec2 uv = (UV * cells + 0.5) / texels;
	vec4 data = texture(TEXTURE, uv);
	vec2 pos = origin + UV * chunk_size;

	float sand = smoothstep(0.4, 0.6, data.g);
	float slick = smoothstep(0.4, 0.6, data.b);

	// Грунт и песок с рябью.
	vec3 color = mix(hard_color, sand_color, sand);
	color *= 1.0 + sand * 0.05 * sin((pos.x + pos.y * 0.6) * 0.9);

	// Отмывка: свет с северо-запада. slope.x — подъём на восток, slope.y — на юг.
	float hx = texture(TEXTURE, uv + vec2(texel, 0.0)).r - texture(TEXTURE, uv - vec2(texel, 0.0)).r;
	float hy = texture(TEXTURE, uv + vec2(0.0, texel)).r - texture(TEXTURE, uv - vec2(0.0, texel)).r;
	vec2 slope = vec2(hx, hy) / (2.0 * cell);
	color *= 1.0 + clamp((slope.x + slope.y) * 2.2, -0.3, 0.3);

	// Горизонтали.
	float level = data.r / contour_interval;
	float line = 1.0 - smoothstep(0.0, 1.5 * fwidth(level), abs(fract(level - 0.5) - 0.5));
	color = mix(color, color * 0.62, line * 0.7);

	// Скользкое поле: ровный блеск и полосы позёмки, бегущие по ветру.
	float angle = data.a * 6.2831853;
	vec2 wind = vec2(sin(angle), -cos(angle));
	vec2 side = vec2(-wind.y, wind.x);
	float streak = sin(dot(pos, side) * 0.35) * sin(dot(pos, wind) * 0.05 - TIME * 3.0);
	vec3 ice = slick_color * (1.0 + 0.1 * smoothstep(0.3, 1.0, streak));
	color = mix(color, ice, slick);

	COLOR = vec4(color, 1.0);
}
