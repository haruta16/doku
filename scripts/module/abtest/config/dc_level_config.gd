# 每日挑战题池实验：按关卡进度决定题池尺寸与难度档；0=对照组（原规则） 1=10/12 分档 2=12 格偏易 3=12 格偏难 4=按日期奇偶随机
extends AbConfigBase
class_name DcLevelConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，沿用原有题池规则
const VALUE_TIERED_10: int = 1 # 10 格起步，200 关后换 12 格
const VALUE_TIERED_12_EASY: int = 2 # 全程 12 格，难度整体偏易
const VALUE_TIERED_12_HARD: int = 3 # 全程 12 格，难度整体偏难
const VALUE_RANDOM: int = 4 # 按当天日期的奇偶在 10/12 格之间随机


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "dc_level"
	default_value = VALUE_CONTROL # 默认档：对照组
	timing = ABTestManager.TIMING_GAME_START_DC # 染色时机：每日挑战开局时


# 是否启用了实验题池（对照组返回 false，走原规则）
func is_override_enabled() -> bool:
	return value() != VALUE_CONTROL


# 取题池棋盘尺寸：10 或 12
func get_pool_size(current_level: int, day_seed: int) -> int:
	match value():
		VALUE_TIERED_10:
			if current_level <= 200:
				return 10
			return 12
		VALUE_TIERED_12_EASY:
			return 12
		VALUE_TIERED_12_HARD:
			return 12
		VALUE_RANDOM:
			return 10 if (day_seed % 2 == 0) else 12
		_:
			return 10


# 取题池难度档：3 易 / 4 中 / 5 难
func get_pool_rank(current_level: int, day_seed: int) -> int:
	match value():
		VALUE_TIERED_10:
			if current_level <= 50:
				return 3
			elif current_level <= 100:
				return 4
			else:
				return 5
		VALUE_TIERED_12_EASY:
			if current_level <= 100:
				return 3
			else:
				return 4
		VALUE_TIERED_12_HARD:
			if current_level <= 50:
				return 3
			elif current_level <= 100:
				return 4
			else:
				return 5
		VALUE_RANDOM:
			var r := (day_seed + 1) % 10
			if r < 4:
				return 3
			elif r < 8:
				return 4
			else:
				return 5
		_:
			return 3


# 是否从 gc 题库取题：10 格恒用，12 格按 day_offset 奇偶隔天用
func use_gc_bank(sz: int, day_offset: int) -> bool:
	if sz == 10:
		return true
	else:
		return day_offset % 2 != 0
