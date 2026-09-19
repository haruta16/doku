# 每日挑战入口实验：0=显示每日挑战入口 1=隐藏（首页不展示每日挑战）
extends AbConfigBase
class_name NoDcConfig

# ---- 分组取值 ----
const VALUE_SHOW: int = 0 # 显示每日挑战入口
const VALUE_HIDE: int = 1 # 隐藏每日挑战入口


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "no_dc"
	default_value = VALUE_SHOW # 默认档：显示入口
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 每日挑战入口是否隐藏
func is_daily_challenge_hidden() -> bool:
	return value() == VALUE_HIDE
