# 提示交互实验：0=对照组（原提示流程） 1=新版提示流程 2=新版流程 + 关闭按钮收尾
extends AbConfigBase
class_name HintUeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，原提示流程
const VALUE_NEW_FLOW: int = 1 # 新版提示流程

const VALUE_CLOSE_BTN: int = 2 # 新版流程，末尾用关闭按钮


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "hint_ue"
	default_value = VALUE_CONTROL # 默认档：原流程
	timing = ABTestManager.TIMING_HINT_USE # 染色时机：玩家使用提示道具时


# 是否新版提示流程（档位 1）
func is_new_hint_flow() -> bool:
	return value() == VALUE_NEW_FLOW


# 是否关闭按钮收尾流程（档位 2）
func is_close_btn_flow() -> bool:
	return value() == VALUE_CLOSE_BTN


# 是否新版流程之一（档位 1/2），用于共用逻辑分支
func is_any_new_flow() -> bool:
	return value() == VALUE_NEW_FLOW or value() == VALUE_CLOSE_BTN
