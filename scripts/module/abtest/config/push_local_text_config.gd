# 本地推送文案实验：0=老文案池 1=新文案池
extends AbConfigBase
class_name PushLocalTextConfig

# ---- 分组取值 ----
const VALUE_LEGACY: int = 0 # 老文案池
const VALUE_NEW_POOL: int = 1 # 新文案池


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "push_local_text"
	default_value = VALUE_LEGACY # 默认档：老文案池
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否用新文案池
func is_new_pool() -> bool:
	return value() == VALUE_NEW_POOL
