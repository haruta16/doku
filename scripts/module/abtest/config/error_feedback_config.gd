# 错误反馈范围实验：标错时有多少只猫参与反馈；0=所有猫都反应 1=只有冲突的猫反应 2=都不反应
extends AbConfigBase
class_name ErrorFeedbackConfig

# ---- 分组取值 ----
const VALUE_ALL: int = 0 # 所有猫都给反馈
const VALUE_CONFLICT_ONLY: int = 1 # 只让冲突的猫反应
const VALUE_NONE: int = 2 # 猫都不反应


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "error_feedback"
	default_value = VALUE_ALL # 默认档：所有猫都反应
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否只让冲突的猫反应
func only_conflicting_cats_react() -> bool:
	return value() == VALUE_CONFLICT_ONLY


# 是否完全不做错误反馈
func no_cats_react() -> bool:
	return value() == VALUE_NONE
