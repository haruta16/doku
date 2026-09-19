# 挂机引导实验：玩家卡住时怎么提示；0=关闭 1=按空闲时间触发 2=按步数触发
extends AbConfigBase
class_name IdleGuideConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭挂机引导
const VALUE_ON: int = 1 # 空闲超时触发引导
const VALUE_STEP_TRIGGER: int = 2 # 按步数触发引导


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "idle_guide"
	default_value = VALUE_OFF # 默认档：关闭
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 作弊面板显示名，带上各档含义（基类只显示 key，这里可读性更好）
func cheat_label() -> String:
	return "idle_guide (0=off 1=idle 2=step)"


# 是否按空闲时间触发引导
func is_idle_guide_enabled() -> bool:
	return value() == VALUE_ON


# 是否按步数触发引导
func is_step_trigger_enabled() -> bool:
	return value() == VALUE_STEP_TRIGGER


# 第 1 关是否因此不再显示道具提示（非 0 档都抑制）
func suppresses_tool_hint_at_level1() -> bool:
	return value() != VALUE_OFF
