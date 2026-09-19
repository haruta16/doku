# 错标图标形态实验：错标瞬间的图标表现；0=心碎 1=不碎 2=鱼碎
extends AbConfigBase
class_name IconCrashConfig

# ---- 分组取值 ----
const VALUE_HEART_CRASH: int = 0 # 心形碎裂
const VALUE_NO_CRASH: int = 1 # 不碎裂
const VALUE_FISH_CRASH: int = 2 # 鱼形碎裂


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "icon_crash"
	default_value = VALUE_HEART_CRASH # 默认档：心碎
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否不碎裂
func is_no_crash() -> bool:
	return value() == VALUE_NO_CRASH


# 是否用鱼形碎裂
func is_fish_crash() -> bool:
	return value() == VALUE_FISH_CRASH
