extends SceneTree

var _fails := 0
var _checks := 0
var _the_world: VoxelWorld

func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  [OK]   " + msg)
	else:
		_fails += 1
		print("  [FAIL] " + msg)

func _solid_mi(c: Chunk) -> MeshInstance3D:
	return c.get("_solid") as MeshInstance3D

func _water_mi(c: Chunk) -> MeshInstance3D:
	return c.get("_water") as MeshInstance3D

func _has_collision(c: Chunk) -> bool:
	var cs := c.get("_shape") as CollisionShape3D
	return cs != null and cs.shape != null

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# 等待场景树真正就绪（保证各节点的 _ready 已经执行）
	await process_frame
	await process_frame

	print("=== 烟测开始 ===")

	var atlas := TextureAtlas.build()
	_ok(atlas != null, "贴图集生成")
	_ok(atlas.get_width() == 64 and atlas.get_height() == 64, "贴图集尺寸 64x64")

	var world := VoxelWorld.new()
	root.add_child(world)
	_the_world = world
	await process_frame
	_ok(world.solid_material != null and world.solid_material.albedo_texture != null, "世界材质已就绪")
	_ok(world.noise_hills != null, "地形噪声已就绪")

	var t0 := Time.get_ticks_usec()
	world.preload_area(Vector3(8.5, 30.0, 8.5), 2)
	var t_gen := (Time.get_ticks_usec() - t0) / 1000.0
	_ok(world.chunks.size() == 25, "预加载 25 个区块数据 (实际 %d)" % world.chunks.size())
	print("  [INFO] preload_area(r=2) 耗时 %.1f ms" % t_gen)

	var meshed := 0
	var surf_total := 0
	var collision := 0
	var water_chunks := 0
	for cp in world.chunks.keys():
		var c: Chunk = world.chunks[cp]
		if c.mesh_ready:
			meshed += 1
			var m := _solid_mi(c).mesh
			if m != null:
				surf_total += m.get_surface_count()
			if _has_collision(c):
				collision += 1
			if _water_mi(c).mesh != null:
				water_chunks += 1
	_ok(meshed == 9, "9 个中心区块已生成网格 (实际 %d)" % meshed)
	_ok(collision == meshed, "已网格化区块都有碰撞体 (%d/%d)" % [collision, meshed])
	_ok(surf_total > 0, "固体网格表面数量 > 0 (合计 %d)" % surf_total)
	print("  [INFO] 含水面的区块数: %d" % water_chunks)

	var c0: Chunk = world.chunks[Vector2i(0, 0)]
	t0 = Time.get_ticks_usec()
	c0.build_mesh()
	var t_mesh := (Time.get_ticks_usec() - t0) / 1000.0
	print("  [INFO] 单区块 build_mesh 耗时 %.1f ms" % t_mesh)
	_ok(t_mesh < 150.0, "单区块网格重建 < 150ms")

	_check_geometry(c0)

	# --- 地形 ---
	var h := world.height_at(0, 0)
	_ok(h >= 2 and h <= VoxelWorld.HEIGHT - 8, "height_at 在合法范围 (%d)" % h)
	var sy := world.surface_y(4, 4)
	_ok(sy > 0, "surface_y > 0 (%d)" % sy)
	_ok(world.get_block(4, sy, 4) != BlockTypes.ID.AIR, "地表位置为实体方块")

	# --- 出生点选择 ---
	var sp := world.find_spawn()
	_ok(world.height_at(sp.x, sp.z) > VoxelWorld.WATER_LEVEL + 2, "出生点位于海平面以上 (%s)" % str(sp))
	_ok(not world._tree_near(sp.x, sp.z), "出生点附近没有树（不会卡在树叶里）")

	# --- 方块读写 ---
	var pp := Vector3i(4, VoxelWorld.HEIGHT - 2, 4)
	_ok(world.get_block(pp.x, pp.y, pp.z) == BlockTypes.ID.AIR, "高空位置初始为空气")
	world.set_block(pp.x, pp.y, pp.z, BlockTypes.ID.STONE)
	_ok(world.get_block(pp.x, pp.y, pp.z) == BlockTypes.ID.STONE, "set_block / get_block 往返正确")
	_ok(world._dirty.size() >= 1, "编辑后区块被标记为脏 (脏数 %d)" % world._dirty.size())
	world.set_block(pp.x, pp.y, pp.z, BlockTypes.ID.AIR)
	world._dirty.clear()

	world.set_block(-1, 5, 4, BlockTypes.ID.STONE)
	_ok(world._dirty.has(Vector2i(-1, 0)) and world._dirty.has(Vector2i(0, 0)),
		"跨边界编辑同时标记两个区块")
	world.set_block(-1, 5, 4, BlockTypes.ID.AIR)
	world._dirty.clear()

	# --- 射线检测 ---
	var top := VoxelWorld.HEIGHT - 1
	var hit := world.raycast_voxel(Vector3(4.5, float(top), 4.5), Vector3(0, -1, 0), 100.0)
	_ok(not hit.is_empty(), "向下射线命中方块")
	if not hit.is_empty():
		_ok(hit.normal == Vector3i(0, 1, 0), "向下命中法线为 +Y (%s)" % str(hit.normal))
		_ok(hit.pos.y == sy, "命中高度与 surface_y 一致 (%d vs %d)" % [hit.pos.y, sy])
	_ok(world.raycast_voxel(Vector3(4.5, float(top), 4.5), Vector3(0, 1, 0), 10.0).is_empty(), "向上射线不命中")
	_ok(not world.raycast_voxel(Vector3(0.5, float(top), 0.5), Vector3(1, -3, 1).normalized(), 200.0).is_empty(), "斜向射线命中方块")
	_ok(world.raycast_voxel(Vector3(500.5, 40.5, 500.5), Vector3(0, -1, 0), 5.0).is_empty(), "未加载区域射线安全返回空")

	# --- 负坐标区块 ---
	world.preload_area(Vector3(-40.0, 30.0, -40.0), 1)
	var neg_ok := true
	for cp in world.chunks.keys():
		if cp.x < 0 or cp.y < 0:
			var c: Chunk = world.chunks[cp]
			if not c.mesh_ready and c.data_ready and world._neighbors_ready(cp):
				c.build_mesh()
			if c.mesh_ready and _solid_mi(c).mesh == null:
				neg_ok = false
	_ok(neg_ok, "负坐标区块生成正常")
	var nb := world.get_block(-41, 3, -41)
	_ok(nb >= 0 and nb <= 13, "负坐标 get_block 返回合法方块 (%d)" % nb)

	_check_water()
	_check_physics()

	# --- 玩家落地（真实物理） ---
	var pl := Player.new()
	root.add_child(pl)
	pl.world = world
	world.target = pl
	pl.global_position = Vector3(4.5, float(VoxelWorld.HEIGHT - 2), 4.5)
	world.preload_area(pl.global_position, 2)
	for i in range(0, 120):
		await process_frame
		await physics_frame
		if i % 20 == 0:
			var cp := Vector2i(int(pl.global_position.x) >> 4, int(pl.global_position.z) >> 4)
			var cc: Chunk = world.chunks.get(cp)
			print("  [TRACE] i=%d y=%.2f vel=%.2f chunk=%s shape=%s floor=%s" % [
				i, pl.global_position.y, pl.velocity.y, str(cp),
				str(cc != null and _has_collision(cc)), str(pl.is_on_floor())])
	var ly2 := pl.global_position.y
	print("  [INFO] 玩家最终高度 %.2f（地表 %d，期望约 %.2f）" % [ly2, sy, float(sy) + 1.9])
	_ok(ly2 > 0.0, "玩家没有掉出世界")
	_ok(abs(ly2 - (float(sy) + 1.9)) < 1.5, "玩家稳定站在地表上")
	_ok(pl.is_on_floor(), "玩家处于站立状态")

	_check_actions()
	await _check_movement(pl)

	# --- 流式加载 / 卸载 ---
	pl.global_position = Vector3(200.0, 30.0, 200.0)
	var before := world.chunks.size()
	for i in range(0, 1500):
		world._process(0.016)
	print("  [INFO] 流转 1500 帧后区块数 %d -> %d" % [before, world.chunks.size()])
	_ok(world.chunks.size() > before, "流式加载生成了新区块")

	var pc := Vector2i(12, 12)
	var leaked := 0
	for cp in world.chunks.keys():
		if abs(cp.x - pc.x) > VoxelWorld.KEEP_RADIUS or abs(cp.y - pc.y) > VoxelWorld.KEEP_RADIUS:
			leaked += 1
	_ok(leaked == 0, "远处区块已被卸载 (残留 %d)" % leaked)

	print("=== 检查 %d 项，失败 %d 项 ===" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

## 校验网格数据的正确性（UV 范围、法线、缠绕方向、面数与暴力统计一致）
func _check_geometry(c: Chunk) -> void:
	var mesh := _solid_mi(c).mesh as ArrayMesh
	_ok(mesh != null and mesh.get_surface_count() > 0, "中心区块存在渲染网格")
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	_ok(verts.size() > 0 and idx.size() > 0, "网格顶点/索引非空 (%d 顶点, %d 索引)" % [verts.size(), idx.size()])

	var uv_ok := true
	for v in uvs:
		if v.x < 0.0 or v.x > 1.0 or v.y < 0.0 or v.y > 1.0:
			uv_ok = false
	_ok(uv_ok, "所有 UV 落在 [0,1] 内")

	var norm_ok := true
	var expect_unit := true
	for n in norms:
		if absi(int(round(n.length() * 1000.0)) - 1000) > 2:
			expect_unit = false
		if abs(n.x) + abs(n.y) + abs(n.z) < 0.99:
			norm_ok = false
	_ok(norm_ok and expect_unit, "法线为单位向量且轴向")

	var col_ok := true
	for col in cols:
		if col.r < 0.2 or col.r > 1.001 or abs(col.r - col.g) > 0.001:
			col_ok = false
	_ok(col_ok, "顶点色在合理亮度范围内")

	var idx_ok := true
	for i in idx:
		if i < 0 or i >= verts.size():
			idx_ok = false
	_ok(idx_ok and idx.size() % 3 == 0, "索引范围合法且为 3 的倍数")

	# 缠绕方向：Godot 正面为顺时针，因此叉积方向应与存储的顶点法线相反
	var wind_ok := true
	var bad := 0
	for t in range(0, idx.size(), 3):
		var p0 := verts[idx[t]]
		var p1 := verts[idx[t + 1]]
		var p2 := verts[idx[t + 2]]
		var nrm := (p1 - p0).cross(p2 - p0)
		if nrm.length_squared() < 0.000001:
			continue
		nrm = nrm.normalized()
		if nrm.dot(norms[idx[t]]) > -0.5:
			wind_ok = false
			bad += 1
	_ok(wind_ok, "三角形缠绕方向符合 Godot 正面惯例 (异常 %d 个)" % bad)

	# 面数与暴力统计一致
	var expected := _brute_force_faces(world_of(c), c)
	var got := _count_mesh_faces(verts, norms)
	var same := true
	for d in 6:
		if got[d] != expected[d]:
			same = false
	_ok(same, "面数与暴力统计一致 (网格 %s vs 参考 %s)" % [str(got), str(expected)])

	var pad_bad := _validate_pad(world_of(c), c)
	_ok(pad_bad == 0, "填充数组 pad 内容与世界数据一致 (不一致 %d 处)" % pad_bad)

func world_of(c: Chunk):
	return c.get_parent()

## 找一片低于海平面的地形，确认这里生成了水体方块与水面网格
func _check_water() -> void:
	var w := _the_world
	var spot := Vector2i.ZERO
	var found := false
	for r in range(1, 40):
		for a in range(0, 32):
			var ang := float(a) / 32.0 * TAU
			var wx := int(round(cos(ang) * r * 24.0))
			var wz := int(round(sin(ang) * r * 24.0))
			if w.height_at(wx, wz) < VoxelWorld.WATER_LEVEL - 1:
				spot = Vector2i(wx, wz)
				found = true
				break
		if found:
			break
	if not found:
		print("  [SKIP] 附近没有找到水域")
		return
	print("  [INFO] 水域探测点: %s (地形高度 %d)" % [str(spot), w.height_at(spot.x, spot.y)])
	w.preload_area(Vector3(spot.x, 20.0, spot.y), 1)
	var water_blocks := 0
	var water_mesh_chunks := 0
	for y in range(0, VoxelWorld.WATER_LEVEL + 1):
		if w.get_block(spot.x, y, spot.y) == BlockTypes.ID.WATER:
			water_blocks += 1
	for cp in w.chunks.keys():
		var c: Chunk = w.chunks[cp]
		if not c.mesh_ready and c.data_ready and w._neighbors_ready(cp):
			c.build_mesh()
		if c.mesh_ready and _water_mi(c).mesh != null:
			water_mesh_chunks += 1
	_ok(water_blocks > 0, "存在水体方块 (%d 格水柱)" % water_blocks)
	_ok(water_mesh_chunks > 0, "水面网格已生成 (%d 个区块)" % water_mesh_chunks)

## 测试环境与 main.gd 一样注册按键映射
func _check_actions() -> void:
	# main.gd 在运行时注册输入；这里单独运行脚本时需要复用同样的注册
	if not InputMap.has_action("move_forward"):
		var keys := {
			"move_forward": KEY_W, "move_back": KEY_S,
			"move_left": KEY_A, "move_right": KEY_D,
			"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL,
		}
		for name in keys.keys():
			InputMap.add_action(name)
			var ev := InputEventKey.new()
			ev.keycode = keys[name]
			InputMap.action_add_event(name, ev)
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "crouch"]:
		Input.action_release(a)

## 验证 WASD 四个方向以及转身后的朝向是否正确
func _check_movement(pl: Player) -> void:
	pl.flying = true
	pl.pitch = 0.0
	var cases := [
		# yaw, 动作, 期望位移方向
		[0.0, "move_forward", Vector3(0, 0, -1)],
		[0.0, "move_back", Vector3(0, 0, 1)],
		[0.0, "move_right", Vector3(1, 0, 0)],
		[0.0, "move_left", Vector3(-1, 0, 0)],
		[PI * 0.5, "move_forward", Vector3(-1, 0, 0)],
		[PI * 0.5, "move_right", Vector3(0, 0, -1)],
	]
	for c in cases:
		pl.yaw = c[0]
		pl.global_position = Vector3(6.0, 44.0, 6.0)
		pl.velocity = Vector3.ZERO
		await physics_frame
		var started := pl.global_position
		Input.action_press(c[1])
		await physics_frame
		Input.action_release(c[1])
		var moved := pl.global_position - started
		var moved_xz := Vector3(moved.x, 0.0, moved.z)
		_ok(moved_xz.dot(c[2]) > 0.001,
			"yaw=%.2f 时 %s 朝 %s 移动（实际 %s）" % [c[0], c[1], str(c[2]), str(moved_xz)])
	pl.flying = false

## 直接用物理引擎查询，确认地形碰撞体确实存在于物理空间中
func _check_physics() -> void:
	var w := _the_world
	var space := w.get_world_3d().direct_space_state
	await physics_frame
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(4.5, 46.0, 4.5), Vector3(4.5, 0.0, 4.5))
	q.exclude = []
	var r := space.intersect_ray(q)
	print("  [INFO] 物理射线结果: %s" % str(r))
	_ok(not r.is_empty(), "物理空间中存在地形碰撞体")

	var c: Chunk = w.chunks.get(Vector2i(0, 0))
	var cs := c.get("_shape") as CollisionShape3D
	print("  [INFO] 碰撞体所在节点: %s / shape=%s" % [str(cs.get_parent().name), str(cs.shape)])
	if cs.shape is ConcavePolygonShape3D:
		var data := (cs.shape as ConcavePolygonShape3D).data
		print("  [INFO] trimesh 顶点数: %d" % (data.size() / 3))
		_ok(data.size() > 0, "trimesh 数据非空")
	else:
		_ok(false, "trimesh 数据非空")

	# 参考 Godot 内置网格的缠绕惯例
	var pm := PlaneMesh.new()
	var pm_a := pm.get_mesh_arrays()
	var pm_v: PackedVector3Array = pm_a[Mesh.ARRAY_VERTEX]
	var pm_i: PackedInt32Array = pm_a[Mesh.ARRAY_INDEX]
	if pm_i.is_empty():
		pm_i = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var pm_n := (pm_v[pm_i[1]] - pm_v[pm_i[0]]).cross(pm_v[pm_i[2]] - pm_v[pm_i[0]])
	print("  [INFO] PlaneMesh(应朝 +Y) 三角缠绕法线 = %s" % str(pm_n.normalized()))
	var qm := QuadMesh.new()
	var qm_a := qm.get_mesh_arrays()
	var qm_v: PackedVector3Array = qm_a[Mesh.ARRAY_VERTEX]
	var qm_i: PackedInt32Array = qm_a[Mesh.ARRAY_INDEX]
	var qm_n := (qm_v[qm_i[1]] - qm_v[qm_i[0]]).cross(qm_v[qm_i[2]] - qm_v[qm_i[0]])
	print("  [INFO] QuadMesh(应朝 +Z) 三角缠绕法线 = %s" % str(qm_n.normalized()))

	# 对照组：手工放一个静态盒子，确认物理本身工作正常
	var box_body := StaticBody3D.new()
	var box_shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4, 1, 4)
	box_shape.shape = bs
	box_body.add_child(box_shape)
	box_body.position = Vector3(4.5, 40.0, 4.5)
	_the_world.add_child(box_body)
	await physics_frame
	var q2 := PhysicsRayQueryParameters3D.create(
		Vector3(4.5, 46.0, 4.5), Vector3(4.5, 0.0, 4.5))
	q2.exclude = []
	var r2 := space.intersect_ray(q2)
	_ok(not r2.is_empty(), "对照组：手工静态盒体可被射线命中")
	print("  [INFO] 对照组命中: y=%s" % str(r2.get("position", "无")))
	box_body.queue_free()

func _validate_pad(world, c: Chunk) -> int:
	var pad := c._build_pad()
	var bad := 0
	for y in range(-1, Chunk.HEIGHT + 1):
		for z in range(-1, Chunk.SIZE + 1):
			for x in range(-1, Chunk.SIZE + 1):
				var want: int = world.get_block(c.origin_x + x, y, c.origin_z + z)
				var got: int = pad[((y + 1) * Chunk.DY) + ((z + 1) * Chunk.DZ) + (x + 1)]
				if got != want:
					bad += 1
	return bad

func _face_dir_index(n: Vector3) -> int:
	if n.x > 0.5: return 0
	if n.x < -0.5: return 1
	if n.y > 0.5: return 2
	if n.y < -0.5: return 3
	if n.z > 0.5: return 4
	return 5

func _count_mesh_faces(verts: PackedVector3Array, norms: PackedVector3Array) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0, 0]
	for i in norms.size():
		out[_face_dir_index(norms[i])] += 1
	# 每个面 4 个顶点
	for d in 6:
		out[d] = out[d] / 4
	return out

func _brute_force_faces(world, c: Chunk) -> Array[int]:
	var dirs := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	var out: Array[int] = [0, 0, 0, 0, 0, 0]
	for y in Chunk.HEIGHT:
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var id: int = c.voxels[(y * Chunk.SIZE + z) * Chunk.SIZE + x]
				if id == 0 or id == BlockTypes.ID.WATER:
					continue
				for d in 6:
					var dd: Vector3i = dirs[d]
					var nb: int = world.get_block(c.origin_x + x + dd.x, y + dd.y, c.origin_z + z + dd.z)
					var visible := true
					if nb != 0:
						if BlockTypes.OPAQUE[nb] == 1:
							visible = false
						elif nb == id:
							visible = false
					if visible:
						out[d] += 1
	return out
