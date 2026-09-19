# 撤销/高亮按钮实验：0=对照组（没有这个按钮） 1=撤销（要消耗） 2=只高亮（要消耗） 3=撤销（免费） 4=只高亮（免费）
extends AbConfigBase
class_name UndoBtnConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不显示按钮
const VALUE_UNDO_PAID: int = 1 # 撤销上一步，需要消耗道具/广告
const VALUE_HIGHLIGHT_PAID: int = 2 # 只做高亮提示，需要消耗
const VALUE_UNDO_FREE: int = 3 # 撤销上一步，免费
const VALUE_HIGHLIGHT_FREE: int = 4 # 只做高亮提示，免费


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "undo_btn"
	default_value = VALUE_CONTROL # 默认档：无按钮
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否显示该按钮
func is_enabled() -> bool:
	return value() != VALUE_CONTROL


# 是否是「撤销上一步」模式（档位 1/3）
func is_undo_mode() -> bool:
	var v: int = value()
	return v == VALUE_UNDO_PAID or v == VALUE_UNDO_FREE


# 是否只是高亮模式（档位 2/4）
func is_highlight_only() -> bool:
	var v: int = value()
	return v == VALUE_HIGHLIGHT_PAID or v == VALUE_HIGHLIGHT_FREE


# 是否免费（档位 3/4），免费时不走消耗流程
func is_free() -> bool:
	var v: int = value()
	return v == VALUE_UNDO_FREE or v == VALUE_HIGHLIGHT_FREE


# 高亮持续秒数，当前固定 10 秒（格子数参数未使用）
func get_highlight_duration(_cell_count: int) -> float:
	return 10.0
