# 道具高亮引导实验：开局高亮哪个道具；0=对照组 1=只高亮一次「定位」 2=只高亮一次「提示」 3=不做高亮 4=随机道具且可重复高亮
extends AbConfigBase
class_name PropHighlightConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组（走原高亮逻辑）
const VALUE_LOCATE_ONCE: int = 1 # 只高亮「定位」道具一次
const VALUE_HINT_ONCE: int = 2 # 只高亮「提示」道具一次
const VALUE_NONE: int = 3 # 不做高亮
const VALUE_CONTROL_REPEATABLE: int = 4 # 对照组逻辑，但允许重复高亮


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "prop_highlight"
	default_value = VALUE_CONTROL # 默认档：对照组

	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 该档位要引导的道具名：locate / hint / none / random / control
func target_prop() -> String:
	match value():
		VALUE_LOCATE_ONCE:
			return "locate"
		VALUE_HINT_ONCE:
			return "hint"
		VALUE_NONE:
			return "none"
		VALUE_CONTROL_REPEATABLE:
			return "random"
		_:
			return "control"


# 是否一辈子只高亮一次（档位 1/2）
func is_once_per_lifetime() -> bool:
	return value() == VALUE_LOCATE_ONCE or value() == VALUE_HINT_ONCE


# 是否可重复高亮（档位 4）
func is_repeatable() -> bool:
	return value() == VALUE_CONTROL_REPEATABLE
