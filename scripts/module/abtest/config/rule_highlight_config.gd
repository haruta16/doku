# 规则条高亮实验：0=对照组（不高亮） 1=违反哪条规则就高亮哪条 2=所有关卡都高亮
extends AbConfigBase
class_name RuleHighlightConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不高亮
const VALUE_HIGHLIGHT_VIOLATED: int = 1 # 违反哪条就高亮哪条
const VALUE_HIGHLIGHT_ALL_LEVELS: int = 2 # 所有关卡都高亮


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "rule_highlight"
	default_value = VALUE_CONTROL # 默认档：不高亮

	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用高亮（非对照组）
func is_highlight_violated() -> bool:
	return value() != VALUE_CONTROL


# 是否所有关卡都高亮（档位 2；每日挑战另有判断）
func is_all_levels() -> bool:
	return value() == VALUE_HIGHLIGHT_ALL_LEVELS
