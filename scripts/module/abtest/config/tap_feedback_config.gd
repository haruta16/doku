# 点击反馈实验：0=对照组（按下即生效） 1=按下/抬起分离处理 2=允许从错标格起手继续打叉 3=两者都开
extends AbConfigBase
class_name TapFeedbackConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组
const VALUE_PRESS_RELEASE_SPLIT: int = 1 # 按下与抬起分开处理
const VALUE_ERROR_START_MARK: int = 2 # 从错误格起手也允许打叉
const VALUE_BOTH: int = 3 # 两者都启用


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "tap_feedback"
	default_value = VALUE_CONTROL # 默认档：对照组
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否按下/抬起分离（档位 1/3）
func is_press_release_split() -> bool:
	return value() == VALUE_PRESS_RELEASE_SPLIT or value() == VALUE_BOTH


# 是否允许从错误格起手（档位 2/3，草稿模式下不适用）
func allows_mark_from_error_start() -> bool:
	return value() == VALUE_ERROR_START_MARK or value() == VALUE_BOTH
