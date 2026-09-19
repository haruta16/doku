# 生命告警实验：生命快用完时是否弹提醒；0=不提醒 1=提醒
extends AbConfigBase
class_name WarnLifeConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 不提醒
const VALUE_SHOW: int = 1 # 弹生命告警


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "warn_life"
	default_value = VALUE_HIDE # 默认档：不提醒
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否显示生命告警
func should_show_life_warning() -> bool:
	return value() == VALUE_SHOW
