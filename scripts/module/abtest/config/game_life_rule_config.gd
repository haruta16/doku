# 对局内补命实验：0=关闭 1=开启。开启后非每日挑战、仅剩 1 命且踩到「区域内二选一」时有机会补命（每局一次，非首次触发只有 50% 概率）
extends AbConfigBase
class_name GameLifeRuleConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭补命
const VALUE_PLUS_ONE: int = 1 # 允许对局内补命


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "game_life_rule"
	default_value = VALUE_OFF # 默认档：关闭
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否启用对局内补命
func is_life_plus_enabled() -> bool:
	return value() == VALUE_PLUS_ONE
