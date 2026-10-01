## 主场景：组装世界、玩家、光照与日夜循环。
extends Node3D

const DAY_LENGTH := 300.0   # 一整天（含夜晚）秒数

const SKY_DAY_TOP := Color(0.24, 0.48, 0.85)
const SKY_DAY_HORIZON := Color(0.62, 0.76, 0.92)
const SKY_NIGHT_TOP := Color(0.02, 0.04, 0.12)
const SKY_NIGHT_HORIZON := Color(0.06, 0.09, 0.20)
const AMBIENT_DAY := Color(0.55, 0.62, 0.72)
const AMBIENT_NIGHT := Color(0.16, 0.19, 0.30)
const SKY_DAY_GROUND := Color(0.34, 0.42, 0.50)
const SKY_NIGHT_GROUND := Color(0.04, 0.05, 0.11)

var world: VoxelWorld
var player: Player
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var env: WorldEnvironment
var time_of_day := 0.35

func _ready() -> void:
	_setup_input()

	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	add_child(world)

	player = Player.new()
	player.name = "Player"
	add_child(player)

	var sp := world.find_spawn()
	player.spawn = Vector3(sp.x + 0.5, float(sp.y) + 3.0, sp.z + 0.5)
	player.global_position = player.spawn
	player.world = world
	world.target = player

	world.preload_area(player.global_position, 3)
	# 站在该列最上方实体方块的顶面上（+2 保证 1.8 高的胶囊不会卡进方块）
	var top := world.surface_y(sp.x, sp.z)
	player.global_position = Vector3(sp.x + 0.5, float(top) + 2.0, sp.z + 0.5)
	player.spawn = player.global_position
	player.velocity = Vector3.ZERO

	_setup_environment()

	var hud := Hud.new()
	hud.name = "Hud"
	hud.player = player
	hud.world = world
	add_child(hud)
	player.hud = hud

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_DAY_TOP
	sky_mat.sky_horizon_color = SKY_DAY_HORIZON
	sky_mat.ground_bottom_color = SKY_DAY_GROUND
	sky_mat.ground_horizon_color = SKY_DAY_HORIZON
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.08
	sky_mat.energy_multiplier = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_DAY
	environment.ambient_light_energy = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = SKY_DAY_HORIZON
	environment.fog_density = 0.011
	environment.fog_sky_affect = 0.12
	environment.fog_aerial_perspective = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	environment.glow_hdr_threshold = 1.0

	env = WorldEnvironment.new()
	env.environment = environment
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.08
	add_child(sun)

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_update_sky(delta)

func _update_sky(_delta: float) -> void:
	var ang := (time_of_day - 0.25) * TAU
	var elevation := sin(ang)
	var day_factor := clampf(elevation * 1.6 + 0.28, 0.0, 1.0)

	# 太阳始终保持在水平线以上，避免夜间从地面下方打光
	var dir := Vector3(cos(ang), maxf(elevation, 0.12), 0.32).normalized()
	var center := player.global_position
	sun.global_position = center + dir * 120.0
	sun.look_at(center, Vector3.UP)
	sun.light_energy = lerpf(0.10, 1.40, day_factor)
	sun.light_color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.72, 0.45), day_factor)

	if sky_mat == null:
		return
	sky_mat.sky_top_color = SKY_NIGHT_TOP.lerp(SKY_DAY_TOP, day_factor)
	sky_mat.sky_horizon_color = SKY_NIGHT_HORIZON.lerp(SKY_DAY_HORIZON, day_factor)
	sky_mat.ground_bottom_color = SKY_NIGHT_GROUND.lerp(SKY_DAY_GROUND, day_factor)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	var amb := AMBIENT_NIGHT.lerp(AMBIENT_DAY, day_factor)
	env.environment.ambient_light_color = amb
	env.environment.fog_light_color = sky_mat.sky_horizon_color

# ---------------------------------------------------------------- 输入映射

func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("sprint", KEY_SHIFT)
	_add_key("crouch", KEY_CTRL)
	_add_mouse("break_block", MOUSE_BUTTON_LEFT)
	_add_mouse("place_block", MOUSE_BUTTON_RIGHT)

func _add_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _add_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
