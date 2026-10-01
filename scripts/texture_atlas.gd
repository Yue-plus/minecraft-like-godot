## 运行时程序化生成 4x4 方块贴图图集（16px/格），无需任何外部资源。
class_name TextureAtlas
extends RefCounted

const TILE_PX := 16
const COLS := 4
const ROWS := 4
const SIZE_PX := TILE_PX * COLS

enum Style {
	NOISE,
	GRASS_TOP,
	GRASS_SIDE,
	LOG_SIDE,
	LOG_TOP,
	LEAVES,
	WATER,
	PLANKS,
	BRICK,
	COBBLE,
	GLASS,
	SNOW_SIDE,
}

static func build() -> ImageTexture:
	var img := Image.create(SIZE_PX, SIZE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	_draw(img, 0, Color(0.35, 0.66, 0.24), Style.GRASS_TOP)
	_draw(img, 1, Color(0.52, 0.41, 0.30), Style.GRASS_SIDE)
	_draw(img, 2, Color(0.52, 0.41, 0.30), Style.NOISE)
	_draw(img, 3, Color(0.52, 0.52, 0.55), Style.NOISE)
	_draw(img, 4, Color(0.87, 0.80, 0.55), Style.NOISE)
	_draw(img, 5, Color(0.44, 0.32, 0.18), Style.LOG_SIDE)
	_draw(img, 6, Color(0.60, 0.45, 0.26), Style.LOG_TOP)
	_draw(img, 7, Color(0.24, 0.55, 0.22), Style.LEAVES)
	_draw(img, 8, Color(0.20, 0.42, 0.78), Style.WATER)
	_draw(img, 9, Color(0.94, 0.96, 0.99), Style.NOISE)
	_draw(img, 10, Color(0.68, 0.50, 0.28), Style.PLANKS)
	_draw(img, 11, Color(0.80, 0.88, 0.95), Style.GLASS)
	_draw(img, 12, Color(0.62, 0.28, 0.22), Style.BRICK)
	_draw(img, 13, Color(0.48, 0.48, 0.50), Style.COBBLE)
	_draw(img, 14, Color(0.22, 0.22, 0.24), Style.COBBLE)
	_draw(img, 15, Color(0.52, 0.41, 0.30), Style.SNOW_SIDE)
	return ImageTexture.create_from_image(img)

static func _draw(img: Image, tile: int, base: Color, style: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1013 + tile * 7919
	var ox := (tile % COLS) * TILE_PX
	var oy := (tile / COLS) * TILE_PX

	# 草/雪侧面的锯齿边界（按列预计算，保证同一列连续）
	var edge := PackedInt32Array()
	edge.resize(TILE_PX)
	for i in TILE_PX:
		edge[i] = 3 + (rng.randi() % 3)

	for y in TILE_PX:
		for x in TILE_PX:
			var c := base
			var a := 1.0
			match style:
				Style.NOISE:
					c = _shade(base, rng.randf_range(-0.10, 0.10))
				Style.GRASS_TOP:
					c = _shade(base, rng.randf_range(-0.14, 0.12))
					if rng.randf() < 0.12:
						c = _shade(base, 0.14)
				Style.GRASS_SIDE:
					if y < edge[x]:
						c = _shade(Color(0.35, 0.66, 0.24), rng.randf_range(-0.12, 0.10))
					else:
						c = _shade(base, rng.randf_range(-0.10, 0.10))
				Style.LOG_SIDE:
					var k := rng.randf_range(-0.06, 0.06)
					if x % 5 == 2 or x == TILE_PX - 1:
						k -= 0.10
					c = _shade(base, k)
				Style.LOG_TOP:
					var d := Vector2(x - 7.5, y - 7.5).length()
					c = _shade(base, (0.07 if int(d) % 2 == 0 else -0.07) + rng.randf_range(-0.03, 0.03))
				Style.LEAVES:
					c = _shade(base, rng.randf_range(-0.12, 0.10))
					if rng.randf() < 0.12:
						c = _shade(base, -0.20)
				Style.WATER:
					c = _shade(base, rng.randf_range(-0.05, 0.05) + sin(float(y) * 1.1) * 0.02)
				Style.PLANKS:
					var row := y / 4
					c = _shade(base, 0.05 if row % 2 == 0 else -0.05)
					if y % 4 == 0 or (x % 8 == 0 and row % 2 == 0):
						c = _shade(base, -0.20)
				Style.BRICK:
					var row := y / 4
					var off := 4 if row % 2 == 0 else 0
					if y % 4 == 0 or (x + off) % 8 == 0:
						c = Color(0.80, 0.75, 0.71)
					else:
						c = _shade(base, rng.randf_range(-0.08, 0.08))
				Style.COBBLE:
					c = _shade(base, rng.randf_range(-0.14, 0.14))
					if x % 4 == 0 or y % 4 == 0:
						c = _shade(base, -0.22)
				Style.GLASS:
					if x == 0 or y == 0 or x == TILE_PX - 1 or y == TILE_PX - 1:
						c = _shade(base, -0.08)
						a = 0.92
					else:
						c = base
						a = 0.16
						if x == y or x + y == TILE_PX - 1:
							a = 0.55
				Style.SNOW_SIDE:
					if y < edge[x] + 1:
						c = _shade(Color(0.94, 0.96, 0.99), rng.randf_range(-0.05, 0.03))
					else:
						c = _shade(base, rng.randf_range(-0.10, 0.10))
			img.set_pixel(ox + x, oy + y, Color(c.r, c.g, c.b, a))

static func _shade(c: Color, k: float) -> Color:
	return Color(
		clampf(c.r + k, 0.0, 1.0),
		clampf(c.g + k, 0.0, 1.0),
		clampf(c.b + k, 0.0, 1.0),
		c.a
	)
