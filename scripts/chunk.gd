## 单个区块：16 x 48 x 16 体素，负责生成渲染网格与碰撞体。
##
## 网格生成使用一层“填充数组”(pad)：把本区块与 8 个邻域的一圈边界体素复制到
## (SIZE+2) x (HEIGHT+2) x (SIZE+2) 的连续数组里，这样面剔除与 AO 采样都变成了
## 无分支的纯索引运算，避免 GDScript 中大量的函数调用开销。
class_name Chunk
extends Node3D

const SIZE := 16
const HEIGHT := 48

# 填充数组步长（SIZE = 16 -> S2 = 18）
const S2 := 18
const DX := 1
const DZ := 18
const DY := 324
const PAD_SIZE := S2 * (HEIGHT + 2) * S2

# 面顺序: +X, -X, +Y, -Y, +Z, -Z
# 对每张面: base 为最小角, u/v 为面内两轴, 保证 u × v = normal（逆时针缠绕）
const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_BASE: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(0, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, 0),
]
const FACE_U: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, 1), Vector3i(1, 0, 0),
	Vector3i(1, 0, 0), Vector3i(0, 1, 0),
]
const FACE_V: Array[Vector3i] = [
	Vector3i(0, 0, 1), Vector3i(0, 1, 0),
	Vector3i(1, 0, 0), Vector3i(0, 0, 1),
	Vector3i(0, 1, 0), Vector3i(1, 0, 0),
]
# 上面 3 个向量在 pad 中对应的索引偏移
const FACE_N_OFF: Array[int] = [DX, -DX, DY, -DY, DZ, -DZ]
const FACE_U_OFF: Array[int] = [DY, DZ, DZ, DX, DX, DY]
const FACE_V_OFF: Array[int] = [DZ, DY, DX, DZ, DY, DX]
# 简易方向光照系数（顶面最亮）
const FACE_LIGHT: Array[float] = [0.80, 0.80, 1.00, 0.55, 0.68, 0.68]

const ATLAS_COLS := 4
const ATLAS_ROWS := 4
const TILE_PX := 16

var chunk_pos := Vector2i.ZERO
var voxels := PackedByteArray()
var data_ready := false
var mesh_ready := false
var origin_x := 0
var origin_z := 0

# 故意不标类型：Chunk 与 VoxelWorld 互相引用，避免 class_name 循环依赖
var world

var _solid: MeshInstance3D
var _water: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D

func _ready() -> void:
	origin_x = chunk_pos.x * SIZE
	origin_z = chunk_pos.y * SIZE
	voxels.resize(SIZE * HEIGHT * SIZE)
	position = Vector3(float(origin_x), 0.0, float(origin_z))

	_solid = MeshInstance3D.new()
	_solid.name = "Solid"
	_solid.material_override = world.solid_material
	_solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_solid)

	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.material_override = world.water_material
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

	_body = StaticBody3D.new()
	_body.name = "Body"
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)
	add_child(_body)

# ---------------------------------------------------------------- 体素访问

func local_block(x: int, y: int, z: int) -> int:
	if y < 0 or y >= HEIGHT:
		return BlockTypes.ID.AIR
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		return voxels[(y * SIZE + z) * SIZE + x]
	return world.get_block(origin_x + x, y, origin_z + z)

# ---------------------------------------------------------------- 网格构建

func build_mesh() -> void:
	var pad := _build_pad()
	_apply(_solid, _build_faces(pad, false))
	_apply(_water, _build_faces(pad, true))

	_shape.shape = null
	if _solid.mesh != null:
		_shape.shape = (_solid.mesh as ArrayMesh).create_trimesh_shape()
	mesh_ready = true

func _apply(mi: MeshInstance3D, arr: Array) -> void:
	if arr[4].is_empty():
		mi.mesh = null
		mi.visible = false
		return
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = arr[0]
	a[Mesh.ARRAY_NORMAL] = arr[1]
	a[Mesh.ARRAY_TEX_UV] = arr[2]
	a[Mesh.ARRAY_COLOR] = arr[3]
	a[Mesh.ARRAY_INDEX] = arr[4]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mi.mesh = m
	mi.visible = true

func _build_pad() -> PackedByteArray:
	var pad := PackedByteArray()
	pad.resize(PAD_SIZE)
	pad.fill(0)
	var v := voxels

	for ly in HEIGHT:
		var yb := (ly + 1) * DY
		var src_row := ly * SIZE * SIZE
		for lz in SIZE:
			var dst := yb + (lz + 1) * DZ + 1
			var src := src_row + lz * SIZE
			for lx in SIZE:
				pad[dst + lx] = v[src + lx]

	# 一圈边界体素（含 4 个对角列）
	var last := S2 - 1
	for ly in HEIGHT:
		var yb := (ly + 1) * DY
		for lz in SIZE:
			var zb := (lz + 1) * DZ
			pad[yb + zb] = world.get_block(origin_x - 1, ly, origin_z + lz)
			pad[yb + zb + last] = world.get_block(origin_x + SIZE, ly, origin_z + lz)
		for lx in SIZE:
			var xb := lx + 1
			pad[yb + xb] = world.get_block(origin_x + lx, ly, origin_z - 1)
			pad[yb + last * DZ + xb] = world.get_block(origin_x + lx, ly, origin_z + SIZE)
		pad[yb] = world.get_block(origin_x - 1, ly, origin_z - 1)
		pad[yb + last] = world.get_block(origin_x + SIZE, ly, origin_z - 1)
		pad[yb + last * DZ] = world.get_block(origin_x - 1, ly, origin_z + SIZE)
		pad[yb + last * DZ + last] = world.get_block(origin_x + SIZE, ly, origin_z + SIZE)
	return pad

## 返回 [verts, normals, uvs, colors, indices]
func _build_faces(pad: PackedByteArray, water_pass: bool) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var opq := BlockTypes.OPAQUE
	var light_f := FACE_LIGHT

	# 每列最高的非空方块，避免遍历整根 48 格高的空气柱
	var tops := PackedInt32Array()
	tops.resize(SIZE * SIZE)
	for lx in SIZE:
		for lz in SIZE:
			var col := (lz + 1) * DZ + lx + 1
			var t := -1
			for y in range(HEIGHT - 1, -1, -1):
				if pad[(y + 1) * DY + col] != 0:
					t = y
					break
			tops[lx * SIZE + lz] = t

	for lx in SIZE:
		for lz in SIZE:
			var top := tops[lx * SIZE + lz]
			if top < 0:
				continue
			var col := (lz + 1) * DZ + lx + 1

			for ly in range(0, top + 1):
				var i0 := (ly + 1) * DY + col
				var id: int = pad[i0]
				if id == BlockTypes.ID.AIR:
					continue
				if (id == BlockTypes.ID.WATER) != water_pass:
					continue

				for f in 6:
					var nb: int = pad[i0 + FACE_N_OFF[f]]
					if nb != 0:
						if opq[nb] == 1:
							continue
						if nb == id:
							continue

					var n: Vector3i = FACE_NORMALS[f]
					var base: Vector3i = FACE_BASE[f]
					var u: Vector3i = FACE_U[f]
					var vv: Vector3i = FACE_V[f]
					var n_off: int = FACE_N_OFF[f]
					var u_off: int = FACE_U_OFF[f]
					var v_off: int = FACE_V_OFF[f]
					var ni: int = i0 + n_off
					var slot := 2
					if f == 2:
						slot = 0
					elif f == 3:
						slot = 1
					var tile := BlockTypes.tile_for(id, slot)
					var light: float = light_f[f]
					var start := verts.size()
					var ao0 := 0
					var ao1 := 0
					var ao2 := 0
					var ao3 := 0

					for k in 4:
						var i := 1 if (k == 1 or k == 2) else 0
						var j := 1 if (k == 2 or k == 3) else 0
						var px: int = lx + base.x + i * u.x + j * vv.x
						var py: int = ly + base.y + i * u.y + j * vv.y
						var pz: int = lz + base.z + i * u.z + j * vv.z
						verts.append(Vector3(px, py, pz))
						norms.append(Vector3(n.x, n.y, n.z))

						# 环境光遮蔽：面外侧的两个边 + 一个角
						var du := 1 if i == 1 else -1
						var dv := 1 if j == 1 else -1
						var a1: int = du * u_off
						var a2: int = dv * v_off
						var s1 := opq[pad[ni + a1]]
						var s2 := opq[pad[ni + a2]]
						var sc := opq[pad[ni + a1 + a2]]
						var a := 0
						if s1 == 1 and s2 == 1:
							a = 0
						else:
							a = 3 - (s1 + s2 + sc)
						match k:
							0: ao0 = a
							1: ao1 = a
							2: ao2 = a
							_: ao3 = a

						var b := light * (0.45 + 0.55 * float(a) / 3.0)
						cols.append(Color(b, b, b))

						var cx: int = px - lx
						var cy: int = py - ly
						var cz: int = pz - lz
						var lu: float
						var lv: float
						if n.y != 0:
							lu = float(cx)
							lv = float(cz)
						else:
							lu = float(cz) if n.x != 0 else float(cx)
							lv = 1.0 - float(cy)
						uvs.append(_tile_uv(tile, lu, lv))

					# 注意：Godot 的正面是顺时针缠绕（参考 PlaneMesh），
					# 因此这里的索引顺序与面外法线方向相反。
					if ao0 + ao2 > ao1 + ao3:
						idxs.append(start + 1); idxs.append(start + 3); idxs.append(start + 2)
						idxs.append(start + 1); idxs.append(start + 0); idxs.append(start + 3)
					else:
						idxs.append(start + 0); idxs.append(start + 2); idxs.append(start + 1)
						idxs.append(start + 0); idxs.append(start + 3); idxs.append(start + 2)

	return [verts, norms, uvs, cols, idxs]

static func _tile_uv(tile: int, lu: float, lv: float) -> Vector2:
	var pad := 0.5 / float(TILE_PX)
	var col := tile & 3
	var row := tile >> 2
	return Vector2(
		(float(col) + pad + lu * (1.0 - 2.0 * pad)) / float(ATLAS_COLS),
		(float(row) + pad + lv * (1.0 - 2.0 * pad)) / float(ATLAS_ROWS))
