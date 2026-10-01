## 游戏内界面：准星、方块快捷栏、调试信息。
class_name Hud
extends CanvasLayer

var player: Player
var world: VoxelWorld

var _styles: Array[StyleBoxFlat] = []
var _debug: Label
var _last_selected := -1
var _acc := 0.0

func _ready() -> void:
	_build_crosshair()
	_build_hotbar()
	_build_debug()
	_build_help()

func _build_crosshair() -> void:
	var outer := Color(0.0, 0.0, 0.0, 0.55)
	var inner := Color(1.0, 1.0, 1.0, 0.9)
	_cross(outer, Vector2(22, 4))
	_cross(outer, Vector2(4, 22))
	_cross(inner, Vector2(20, 2))
	_cross(inner, Vector2(2, 20))

func _cross(c: Color, s: Vector2) -> void:
	var r := ColorRect.new()
	r.color = c
	r.size = s
	r.set_anchors_preset(Control.PRESET_CENTER)
	r.position = Vector2(-s.x * 0.5, -s.y * 0.5)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)

func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 锚点与偏移必须在进入场景树之前设置：
	# 入树后再设置 position 会被解释为“父坐标位置”，锚点会失效。
	var slot_size := 58
	var width := 9 * slot_size + 8 * 6
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -float(width) * 0.5
	bar.offset_right = float(width) * 0.5
	bar.offset_top = -92.0
	bar.offset_bottom = -34.0

	for i in 9:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.10, 0.12, 0.62)
		style.border_color = Color(0.55, 0.55, 0.60, 0.85)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", style)
		bar.add_child(slot)
		_styles.append(style)

		var swatch := ColorRect.new()
		swatch.color = BlockTypes.color_of(player.hotbar[i])
		swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		swatch.offset_left = 5
		swatch.offset_top = 5
		swatch.offset_right = -5
		swatch.offset_bottom = -18
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(swatch)

		var label := Label.new()
		label.text = BlockTypes.name_of(player.hotbar[i])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_top = 34
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)

	add_child(bar)

func _build_debug() -> void:
	_debug = Label.new()
	_debug.name = "Debug"
	_debug.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug.position = Vector2(12, 10)
	_debug.add_theme_font_size_override("font_size", 13)
	_debug.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_debug.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_debug.add_theme_constant_override("shadow_offset_y", 1)
	_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_debug)

func _build_help() -> void:
	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.size = Vector2(260, 210)
	help.position = Vector2(-272.0, 12.0)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	help.add_theme_constant_override("shadow_offset_y", 1)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.text = (
		"WASD 移动   空格 跳跃\n"
		+ "Shift 疾跑   F 飞行\n"
		+ "左键 挖掘    右键 放置\n"
		+ "1-9 / 滚轮 选择方块\n"
		+ "Esc 释放鼠标"
	)
	add_child(help)

func _process(delta: float) -> void:
	if player.selected != _last_selected:
		_last_selected = player.selected
		for i in _styles.size():
			_styles[i].border_color = (
				Color(1.0, 0.85, 0.25, 1.0) if i == _last_selected
				else Color(0.55, 0.55, 0.60, 0.85))
			_styles[i].set_border_width_all(4 if i == _last_selected else 2)

	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0

	var p := player.global_position
	var fps := int(Engine.get_frames_per_second())
	var t := _target_text()
	_debug.text = (
		"FPS: %d\n" % fps
		+ "坐标: %.1f / %.1f / %.1f\n" % [p.x, p.y, p.z]
		+ "区块: %d\n" % world.chunks.size()
		+ "模式: %s\n" % ("飞行" if player.flying else "行走")
		+ "目标: %s" % t
	)

func _target_text() -> String:
	var hit := player.get_target()
	if hit.is_empty():
		return "无"
	return "%s @ (%d, %d, %d)" % [
		BlockTypes.name_of(hit.block), hit.pos.x, hit.pos.y, hit.pos.z]
