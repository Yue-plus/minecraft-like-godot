## 方块类型定义。
## 所有方块数据用按 ID 索引的紧凑数组存储，网格生成循环中直接查表。
class_name BlockTypes
extends RefCounted

enum ID {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	WOOD = 5,
	LEAVES = 6,
	WATER = 7,
	SNOW = 8,
	PLANKS = 9,
	GLASS = 10,
	BRICK = 11,
	COBBLE = 12,
	BEDROCK = 13,
}

# --- 贴图图集槽位 (4x4) ---
const T_GRASS_TOP := 0
const T_GRASS_SIDE := 1
const T_DIRT := 2
const T_STONE := 3
const T_SAND := 4
const T_LOG_SIDE := 5
const T_LOG_TOP := 6
const T_LEAVES := 7
const T_WATER := 8
const T_SNOW := 9
const T_PLANKS := 10
const T_GLASS := 11
const T_BRICK := 12
const T_COBBLE := 13
const T_BEDROCK := 14
const T_SNOW_SIDE := 15

# 顶面贴图（按 ID 索引：空气/草/土/石/沙/木/叶/水/雪/板/玻璃/砖/圆石/基岩）
static var TILE_TOP := PackedInt32Array([0, 0, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14])
# 底面贴图
static var TILE_BOTTOM := PackedInt32Array([0, 2, 2, 3, 4, 6, 7, 8, 2, 10, 11, 12, 13, 14])
# 侧面贴图
static var TILE_SIDE := PackedInt32Array([0, 1, 2, 3, 4, 5, 7, 8, 15, 10, 11, 12, 13, 14])

static var SOLID := PackedByteArray([0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1])
# 不透明：用于面剔除与环境光遮蔽采样（玻璃/水/空气不算）
static var OPAQUE := PackedByteArray([0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1])

static var NAMES := PackedStringArray([
	"Air", "Grass", "Dirt", "Stone", "Sand", "Wood", "Leaves",
	"Water", "Snow", "Planks", "Glass", "Brick", "Cobble", "Bedrock",
])

# slot: 0 = 顶面, 1 = 底面, 2 = 侧面
static func tile_for(id: int, slot: int) -> int:
	if slot == 0:
		return TILE_TOP[id]
	if slot == 1:
		return TILE_BOTTOM[id]
	return TILE_SIDE[id]

static func is_solid(id: int) -> bool:
	return SOLID[id] == 1

static func is_opaque(id: int) -> bool:
	return OPAQUE[id] == 1

static func is_liquid(id: int) -> bool:
	return id == ID.WATER

static func name_of(id: int) -> String:
	return NAMES[id]

static func color_of(id: int) -> Color:
	match id:
		1: return Color(0.35, 0.66, 0.24)
		2: return Color(0.52, 0.41, 0.30)
		3: return Color(0.52, 0.52, 0.55)
		4: return Color(0.87, 0.80, 0.55)
		5: return Color(0.44, 0.32, 0.18)
		6: return Color(0.24, 0.55, 0.22)
		7: return Color(0.20, 0.42, 0.78)
		8: return Color(0.94, 0.96, 0.99)
		9: return Color(0.68, 0.50, 0.28)
		10: return Color(0.80, 0.88, 0.95)
		11: return Color(0.62, 0.28, 0.22)
		12: return Color(0.48, 0.48, 0.50)
		13: return Color(0.22, 0.22, 0.24)
	return Color(0.6, 0.6, 0.6)
