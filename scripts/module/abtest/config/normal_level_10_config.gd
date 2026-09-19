# 普通第 10 关特殊题实验：0=用 sp 第 44 题 1=换成 sp 第 57 题
extends AbConfigBase
class_name NormalLevel10Config

# ---- 分组取值 ----
const VALUE_SP44: int = 0 # 第 10 关用 sp44
const VALUE_SP57: int = 1 # 第 10 关换成 sp57


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "normal_level_10"
	default_value = VALUE_SP44 # 默认档：sp44
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 第 10 关是否换成 sp57
func is_sp57_at_level10() -> bool:
	return value() == VALUE_SP57
