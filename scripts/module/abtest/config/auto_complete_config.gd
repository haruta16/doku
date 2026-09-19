# 自动完成实验：棋局只差最后一只猫时是否给出「自动完成」按钮（点一下自动补齐并通关）；0=关 1=开启且连叉一起补 2=开启但只补猫不打叉
extends AbConfigBase
class_name AutoCompleteConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭自动完成
const VALUE_ON: int = 1 # 开启，自动完成时连叉一起补
const VALUE_LAST_CAT_ONLY: int = 2 # 开启，但只补猫、不补叉


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "auto_complete"
	default_value = VALUE_OFF # 默认档：关闭
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否提供「自动完成」按钮（档位 2 也算启用）
func is_enabled() -> bool:
	return value() != VALUE_OFF


# 自动完成时是否连叉一起补（仅档位 1；否则只补猫）
func should_auto_mark_crosses() -> bool:
	return value() == VALUE_ON
