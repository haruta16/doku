# 插屏概率实验：本 session 看够 N 次激励后，按百分比概率决定是否真的展示插屏；0=对照组（不拦截） 1=3 次/50% 2=2 次/70% 3=1 次/80%
extends AbConfigBase
class_name InterProbConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不做概率拦截
const VALUE_PROB_50_AT_3: int = 1 # 看过 3 次激励后，50% 概率放行
const VALUE_PROB_70_AT_2: int = 2 # 看过 2 次激励后，70% 概率放行
const VALUE_PROB_80_AT_1: int = 3 # 看过 1 次激励后，80% 概率放行


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "inter_prob"
	default_value = VALUE_CONTROL # 默认档：不拦截
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用概率拦截（对照组返回 false）
func is_enabled() -> bool:
	return value() != VALUE_CONTROL


# 取触发概率判定的观看次数门槛；对照组为 0
func get_threshold() -> int:
	match value():
		VALUE_PROB_50_AT_3:
			return 3
		VALUE_PROB_70_AT_2:
			return 2
		VALUE_PROB_80_AT_1:
			return 1
		_:
			return 0


# 取放行概率百分比；对照组为 100（必放行）
func get_show_percent() -> int:
	match value():
		VALUE_PROB_50_AT_3:
			return 50
		VALUE_PROB_70_AT_2:
			return 70
		VALUE_PROB_80_AT_1:
			return 80
		_:
			return 100
