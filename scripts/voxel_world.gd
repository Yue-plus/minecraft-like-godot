## 体素世界：无限程序化地形、区块流式加载、方块读写与体素射线检测。
class_name VoxelWorld
extends Node3D

const SIZE := 16
const HEIGHT := 48
const WATER_LEVEL := 18
const VIEW_RADIUS := 6      # 生成网格的区块半径
const DATA_RADIUS := 7      # 生成体素数据的区块半径（需比 VIEW_RADIUS 大 1，供 AO 采样）
const KEEP_RADIUS := 10     # 超出该半径的区块卸载

var solid_material: StandardMaterial3D
var water_material: StandardMaterial3D
var chunks: Dictionary = {}
var target: Node3D

var noise_hills: FastNoiseLite
var noise_mount: FastNoiseLite
var noise_cave: FastNoiseLite

var _dirty: Dictionary = {}
var _unload_timer := 2.0

# ------------------------------------------------------------------ 初始化

func _ready() -> void:
	var atlas := TextureAtlas.build()

	solid_material = StandardMaterial3D.new()
	solid_material.albedo_texture = atlas
	solid_material.vertex_color_use_as_albedo = true
	solid_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	solid_material.roughness = 0.9
	solid_material.metallic = 0.0
	solid_material.uv1_scale = Vector3(1, 1, 1)

	water_material = StandardMaterial3D.new()
	water_material.albedo_texture = atlas
	water_material.vertex_color_use_as_albedo = true
	water_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color = Color(1, 1, 1, 0.68)
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material.roughness = 0.15
	water_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	water_material.metallic_specular = 0.35
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	noise_hills = FastNoiseLite.new()
	noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_hills.frequency = 0.0075
	noise_hills.fractal_octaves = 4
	noise_hills.fractal_gain = 0.45

	noise_mount = FastNoiseLite.new()
	noise_mount.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_mount.frequency = 0.004
	noise_mount.fractal_octaves = 3

	noise_cave = FastNoiseLite.new()
	noise_cave.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_cave.frequency = 0.055
	noise_cave.fractal_octaves = 3

# ------------------------------------------------------------------ 体素访问

func get_block(gx: int, gy: int, gz: int) -> int:
	if gy < 0 or gy >= HEIGHT:
		return BlockTypes.ID.AIR
	var c: Chunk = chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return BlockTypes.ID.AIR
	return c.voxels[(gy * SIZE + (gz & 15)) * SIZE + (gx & 15)]

func set_block(gx: int, gy: int, gz: int, id: int) -> void:
	if gy < 0 or gy >= HEIGHT:
		return
	var cp := Vector2i(gx >> 4, gz >> 4)
	var c: Chunk = chunks.get(cp)
	if c == null or not c.data_ready:
		return
	c.voxels[(gy * SIZE + (gz & 15)) * SIZE + (gx & 15)] = id
	mark_dirty(cp)
	var lx := gx & 15
	var lz := gz & 15
	if lx == 0:
		mark_dirty(cp + Vector2i(-1, 0))
	elif lx == SIZE - 1:
		mark_dirty(cp + Vector2i(1, 0))
	if lz == 0:
		mark_dirty(cp + Vector2i(0, -1))
	elif lz == SIZE - 1:
		mark_dirty(cp + Vector2i(0, 1))

func mark_dirty(cp: Vector2i) -> void:
	var c: Chunk = chunks.get(cp)
	if c != null and c.data_ready:
		_dirty[cp] = true

func is_occluder_at(gx: int, gy: int, gz: int) -> int:
	return BlockTypes.OPAQUE[get_block(gx, gy, gz)]

## 自上而下找到第一个固体方块的高度
func surface_y(wx: int, wz: int) -> int:
	for y in range(HEIGHT - 1, 0, -1):
		var b := get_block(wx, y, wz)
		if b != BlockTypes.ID.AIR and b != BlockTypes.ID.WATER:
			return y
	return HEIGHT - 1

# ------------------------------------------------------------------ 地形生成

func height_at(wx: int, wz: int) -> int:
	var fx := float(wx)
	var fz := float(wz)
	var h := 24.0
	h += noise_hills.get_noise_2d(fx, fz) * 12.0
	h += noise_hills.get_noise_2d(fx * 4.6 + 300.0, fz * 4.6 - 120.0) * 3.0
	var m := noise_mount.get_noise_2d(fx * 0.52 - 55.0, fz * 0.52 + 88.0)
	if m > 0.10:
		h += (m - 0.10) * 22.0
	return clampi(int(h), 2, HEIGHT - 8)

func _create_chunk_data(cp: Vector2i) -> void:
	var c := Chunk.new()
	c.chunk_pos = cp
	c.world = self
	c.name = "Chunk_%d_%d" % [cp.x, cp.y]
	add_child(c)
	chunks[cp] = c
	_generate(c)
	c.data_ready = true

func _generate(c: Chunk) -> void:
	var ox := c.origin_x
	var oz := c.origin_z
	var v := c.voxels
	const AIR := BlockTypes.ID.AIR
	const WATER := BlockTypes.ID.WATER
	const SAND := BlockTypes.ID.SAND
	const SNOW := BlockTypes.ID.SNOW
	const GRASS := BlockTypes.ID.GRASS
	const BEDROCK := BlockTypes.ID.BEDROCK
	const DIRT := BlockTypes.ID.DIRT
	const STONE := BlockTypes.ID.STONE
	const WOOD := BlockTypes.ID.WOOD
	const LEAVES := BlockTypes.ID.LEAVES

	var heights := PackedInt32Array()
	heights.resize(SIZE * SIZE)
	for lx in SIZE:
		for lz in SIZE:
			heights[lx * SIZE + lz] = height_at(ox + lx, oz + lz)

	for lx in SIZE:
		for lz in SIZE:
			var h: int = heights[lx * SIZE + lz]
			for y in range(0, h + 1):
				var id: int
				if y == h:
					if h <= WATER_LEVEL + 1:
						id = SAND
					elif h >= 34:
						id = SNOW
					else:
						id = GRASS
				elif y == 0:
					id = BEDROCK
				elif y >= h - 2:
					id = DIRT
				else:
					id = STONE
				v[(y * SIZE + lz) * SIZE + lx] = id
			for y in range(h + 1, WATER_LEVEL + 1):
				v[(y * SIZE + lz) * SIZE + lx] = WATER

	# 洞穴
	for ly in range(1, 40):
		for lz in SIZE:
			for lx in SIZE:
				var i := (ly * SIZE + lz) * SIZE + lx
				if v[i] == AIR:
					continue
				var n := noise_cave.get_noise_3d(
					float(ox + lx) * 1.1, float(ly) * 1.6, float(oz + lz) * 1.1)
				if n > 0.50:
					v[i] = WATER if ly <= WATER_LEVEL else AIR

	# 树木（含 3 格边距，保证跨区块的树完整）
	for lx in range(-3, SIZE + 3):
		for lz in range(-3, SIZE + 3):
			var wx := ox + lx
			var wz := oz + lz
			var h := height_at(wx, wz)
			if h <= WATER_LEVEL + 1 or h >= 32:
				continue
			if hash2(wx, wz) > 0.025:
				continue
			var trunk := 4 + int(hash2(wx + 71, wz - 37) * 3.0)
			for i in trunk:
				_set_local(c, wx, h + 1 + i, wz, WOOD)
			for dy in range(-2, 3):
				var rad := 2 if dy <= 0 else 1
				for dx in range(-rad, rad + 1):
					for dz in range(-rad, rad + 1):
						if dx == 0 and dz == 0 and dy < 0:
							continue
						if dx * dx + dz * dz > rad * rad + 1:
							continue
						_set_local_soft(c, wx + dx, h + trunk + dy, wz + dz, LEAVES)

func _set_local(c: Chunk, wx: int, y: int, wz: int, id: int) -> void:
	if y < 1 or y >= HEIGHT:
		return
	var lx := wx - c.origin_x
	var lz := wz - c.origin_z
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	c.voxels[(y * SIZE + lz) * SIZE + lx] = id

func _set_local_soft(c: Chunk, wx: int, y: int, wz: int, id: int) -> void:
	if y < 1 or y >= HEIGHT:
		return
	var lx := wx - c.origin_x
	var lz := wz - c.origin_z
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	var i := (y * SIZE + lz) * SIZE + lx
	if c.voxels[i] == BlockTypes.ID.AIR:
		c.voxels[i] = id

static func hash2(x: int, z: int) -> float:
	var n: int = x * 374761393 + z * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n) / 2147483647.0

# ------------------------------------------------------------------ 流式加载

func preload_area(pos: Vector3, radius: int) -> void:
	var pc := _chunk_of(pos)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if not chunks.has(pc + Vector2i(dx, dz)):
				_create_chunk_data(pc + Vector2i(dx, dz))
	for dx in range(-(radius - 1), radius):
		for dz in range(-(radius - 1), radius):
			var c: Chunk = chunks.get(pc + Vector2i(dx, dz))
			if c != null and c.data_ready and not c.mesh_ready:
				c.build_mesh()

func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x)) >> 4, int(floor(pos.z)) >> 4)

func _process(delta: float) -> void:
	# 编辑过的区块优先重建
	var n := 0
	for cp in _dirty.keys():
		var c: Chunk = chunks.get(cp)
		if c != null and c.data_ready:
			c.build_mesh()
		_dirty.erase(cp)
		n += 1
		if n >= 4:
			break

	if target == null or not target.is_inside_tree():
		return
	var pc := _chunk_of(target.global_position)
	var t0 := Time.get_ticks_usec()

	# 1) 生成体素数据（由近到远）
	for r in range(0, DATA_RADIUS + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if max(abs(dx), abs(dz)) != r:
					continue
				if not chunks.has(pc + Vector2i(dx, dz)):
					_create_chunk_data(pc + Vector2i(dx, dz))
					if Time.get_ticks_usec() - t0 > 6000:
						return

	# 2) 生成网格（需要 8 邻域数据就绪，否则 AO 会出错）
	for r in range(0, VIEW_RADIUS + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if max(abs(dx), abs(dz)) != r:
					continue
				var cp := pc + Vector2i(dx, dz)
				var c: Chunk = chunks.get(cp)
				if c == null or not c.data_ready or c.mesh_ready:
					continue
				if not _neighbors_ready(cp):
					continue
				c.build_mesh()
				if Time.get_ticks_usec() - t0 > 9000:
					return

	# 3) 卸载远处区块
	_unload_timer -= delta
	if _unload_timer <= 0.0:
		_unload_timer = 2.0
		for cp in chunks.keys():
			if abs(cp.x - pc.x) > KEEP_RADIUS or abs(cp.y - pc.y) > KEEP_RADIUS:
				var c: Chunk = chunks[cp]
				chunks.erase(cp)
				_dirty.erase(cp)
				c.queue_free()

func _neighbors_ready(cp: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var c: Chunk = chunks.get(cp + Vector2i(dx, dz))
			if c == null or not c.data_ready:
				return false
	return true

# ------------------------------------------------------------------ 射线检测

## 体素 DDA 射线检测，返回 {pos: Vector3i, normal: Vector3i, block: int} 或 {}
func raycast_voxel(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var ix := int(floor(origin.x))
	var iy := int(floor(origin.y))
	var iz := int(floor(origin.z))

	var step_x := 0
	var step_y := 0
	var step_z := 0
	var t_max_x := INF
	var t_max_y := INF
	var t_max_z := INF
	var t_delta_x := INF
	var t_delta_y := INF
	var t_delta_z := INF

	if dir.x > 0.0:
		step_x = 1
		t_max_x = (float(ix + 1) - origin.x) / dir.x
		t_delta_x = 1.0 / dir.x
	elif dir.x < 0.0:
		step_x = -1
		t_max_x = (float(ix) - origin.x) / dir.x
		t_delta_x = -1.0 / dir.x
	if dir.y > 0.0:
		step_y = 1
		t_max_y = (float(iy + 1) - origin.y) / dir.y
		t_delta_y = 1.0 / dir.y
	elif dir.y < 0.0:
		step_y = -1
		t_max_y = (float(iy) - origin.y) / dir.y
		t_delta_y = -1.0 / dir.y
	if dir.z > 0.0:
		step_z = 1
		t_max_z = (float(iz + 1) - origin.z) / dir.z
		t_delta_z = 1.0 / dir.z
	elif dir.z < 0.0:
		step_z = -1
		t_max_z = (float(iz) - origin.z) / dir.z
		t_delta_z = -1.0 / dir.z

	var normal := Vector3i(0, 1, 0)
	var t := 0.0
	for _i in range(0, 256):
		var b := get_block(ix, iy, iz)
		if b != BlockTypes.ID.AIR and b != BlockTypes.ID.WATER:
			return {"pos": Vector3i(ix, iy, iz), "normal": normal, "block": b}
		if t_max_x < t_max_y and t_max_x < t_max_z:
			ix += step_x
			t = t_max_x
			t_max_x += t_delta_x
			normal = Vector3i(-step_x, 0, 0)
		elif t_max_y < t_max_z:
			iy += step_y
			t = t_max_y
			t_max_y += t_delta_y
			normal = Vector3i(0, -step_y, 0)
		else:
			iz += step_z
			t = t_max_z
			t_max_z += t_delta_z
			normal = Vector3i(0, 0, -step_z)
		if t > max_dist or iy < -1 or iy > HEIGHT:
			break
	return {}

# ------------------------------------------------------------------ 出生点

## 该列是否会生长树木（与 _generate 中的规则保持一致）
func has_tree_at(wx: int, wz: int) -> bool:
	var h := height_at(wx, wz)
	if h <= WATER_LEVEL + 1 or h >= 32:
		return false
	return hash2(wx, wz) <= 0.025

## 附近 3 格内是否有树（树叶最大向外延伸 2 格）
func _tree_near(wx: int, wz: int) -> bool:
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if has_tree_at(wx + dx, wz + dz):
				return true
	return false

func find_spawn() -> Vector3i:
	for r in range(0, 64):
		var count := 24 if r > 0 else 1
		for a in range(0, count):
			var ang := float(a) / float(count) * TAU
			var wx := int(round(cos(ang) * float(r) * 12.0))
			var wz := int(round(sin(ang) * float(r) * 12.0))
			var h := height_at(wx, wz)
			if h <= WATER_LEVEL + 2:
				continue
			if r > 0 and _tree_near(wx, wz):
				continue
			if r == 0 and _tree_near(0, 0):
				continue
			return Vector3i(wx, h, wz)
	return Vector3i(0, HEIGHT - 8, 0)
