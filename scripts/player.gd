## 玩家控制器：第一人称移动（行走 / 疾跑 / 飞行）、挖掘与放置方块。
class_name Player
extends CharacterBody3D

const MOUSE_SENS := 0.0022
const WALK_SPEED := 4.8
const SPRINT_SPEED := 7.8
const FLY_SPEED := 12.0
const JUMP_VELOCITY := 9.4
const GRAVITY := 28.0
const REACH := 6.0
const EYE_HEIGHT := 0.7

var world: VoxelWorld
var hud
var flying := false
var yaw := 0.0
var pitch := 0.0
var selected := 0
var spawn := Vector3(8.5, 40.0, 8.5)
var hotbar := PackedInt32Array([
	BlockTypes.ID.GRASS, BlockTypes.ID.DIRT, BlockTypes.ID.STONE,
	BlockTypes.ID.SAND, BlockTypes.ID.WOOD, BlockTypes.ID.LEAVES,
	BlockTypes.ID.PLANKS, BlockTypes.ID.GLASS, BlockTypes.ID.BRICK,
])

var camera: Camera3D
var highlight: MeshInstance3D
var _target: Dictionary = {}
var _break_timer := 0.0
var _place_timer := 0.0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	add_child(col)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	camera.near = 0.05
	camera.far = 500.0
	add_child(camera)

	highlight = MeshInstance3D.new()
	highlight.name = "BlockHighlight"
	highlight.mesh = _wire_box()
	highlight.top_level = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.02, 0.02, 0.02, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.flags_no_depth_test = true
	highlight.material_override = m
	highlight.visible = false
	add_child(highlight)

# -------------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			yaw -= event.relative.x * MOUSE_SENS
			pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.52, 1.52)
		return

	if event is InputEventMouseButton:
		# 滚轮滚动一格会触发一次 pressed=true 与一次 pressed=false，
		# 不过滤松开事件会导致选择物品一次跳两格。
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected = (selected + 8) % 9
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected = (selected + 1) % 9
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				flying = not flying
				if flying:
					velocity.y = 0.0
			_:
				if event.keycode >= KEY_1 and event.keycode <= KEY_9:
					selected = event.keycode - KEY_1

# -------------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	rotation.y = yaw
	camera.rotation.x = pitch

	_break_timer -= delta
	_place_timer -= delta
	_update_target()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _target.is_empty():
		highlight.visible = false
		return

	var p: Vector3i = _target.pos
	highlight.visible = true
	highlight.global_position = Vector3(p.x, p.y, p.z) + Vector3(0.5, 0.5, 0.5)

	if _pressed("break_block") and _break_timer <= 0.0:
		_break_timer = 0.15
		world.set_block(p.x, p.y, p.z, BlockTypes.ID.AIR)

	if _pressed("place_block") and _place_timer <= 0.0:
		_place_timer = 0.2
		var np: Vector3i = p + _target.normal
		if not _blocks_player(np):
			world.set_block(np.x, np.y, np.z, hotbar[selected])

func _physics_process(delta: float) -> void:
	if global_position.y < -40.0:
		global_position = spawn
		velocity = Vector3.ZERO

	var b := Basis(Vector3.UP, yaw)
	var fwd := -b.z
	var right := b.x
	# fwd 已经是朝向（Godot 约定为 -Z），所以按前进键取 +1
	var forward_in := 0.0
	var strafe_in := 0.0
	if _pressed("move_forward"):
		forward_in += 1.0
	if _pressed("move_back"):
		forward_in -= 1.0
	if _pressed("move_right"):
		strafe_in += 1.0
	if _pressed("move_left"):
		strafe_in -= 1.0
	var wish := fwd * forward_in + right * strafe_in
	if wish.length() > 1.0:
		wish = wish.normalized()

	if flying:
		var speed := FLY_SPEED * (1.8 if _pressed("sprint") else 1.0)
		var vy := 0.0
		if _pressed("jump"):
			vy += speed
		if _pressed("crouch"):
			vy -= speed
		velocity = wish * speed + Vector3(0.0, vy, 0.0)
	else:
		var speed := SPRINT_SPEED if _pressed("sprint") else WALK_SPEED
		var target := wish * speed
		var accel := 55.0 if is_on_floor() else 14.0
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
		velocity.y -= GRAVITY * delta
		if _pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

	move_and_slide()

# -------------------------------------------------------------------- 辅助

func _update_target() -> void:
	if world == null:
		return
	var o := camera.global_position
	var d := -camera.global_transform.basis.z
	_target = world.raycast_voxel(o, d, REACH)

func get_target() -> Dictionary:
	return _target

## 动作可能尚未注册（例如单独运行脚本时），这里做一次安全兜底
static func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)

func _blocks_player(p: Vector3i) -> bool:
	var pp := global_position
	var bmin := Vector3(p.x, p.y, p.z)
	var bmax := bmin + Vector3.ONE
	var pmin := pp + Vector3(-0.36, -0.92, -0.36)
	var pmax := pp + Vector3(0.36, 0.92, 0.36)
	return (bmin.x < pmax.x and bmax.x > pmin.x
			and bmin.y < pmax.y and bmax.y > pmin.y
			and bmin.z < pmax.z and bmax.z > pmin.z)

func _wire_box() -> ArrayMesh:
	var pts := [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	var s := 1.006
	var off := Vector3(0.5, 0.5, 0.5)
	var v := PackedVector3Array()
	for e in edges:
		v.append((pts[e[0]] - off) * s)
		v.append((pts[e[1]] - off) * s)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m
