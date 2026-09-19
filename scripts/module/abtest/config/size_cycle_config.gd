# 普通关尺寸循环实验：0/1 未使用，2=对照组（原尺寸曲线） 3~8=六套棋盘尺寸表；GamePage 按该值决定查哪张尺寸表
extends AbConfigBase
class_name SizeCycleConfig

# ---- 分组取值（从 2 起，0/1 未使用） ----
const VALUE_CONTROL: int = 2 # 对照组，原尺寸曲线
const VALUE_CYCLE_V3_A: int = 3 # 尺寸循环方案 A
const VALUE_CYCLE_V3_B: int = 4 # 尺寸循环方案 B
const VALUE_CYCLE_V3_C: int = 5 # 尺寸循环方案 C
const VALUE_CYCLE_V3_D: int = 6 # 尺寸循环方案 D
const VALUE_CYCLE_V3_E: int = 7 # 尺寸循环方案 E
const VALUE_CYCLE_V3_F: int = 8 # 尺寸循环方案 F


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "size_cycle"
	default_value = VALUE_CONTROL # 默认档：对照组
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 是否启用实验尺寸循环（非对照组）
func is_cycle_enabled() -> bool:
	return value() != VALUE_CONTROL
