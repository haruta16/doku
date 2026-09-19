# 草稿模式实验（第 21 关起生效）：0=对照组（无草稿） 1=草稿就地应用（全对时才出「应用」按钮） 2=草稿独立成层（进草稿模式就有「应用」按钮） 3=草稿全对自动提交 4=自动提交且退出保留草稿
extends AbConfigBase
class_name DraftModeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不开启草稿模式
const VALUE_APPLY_INPLACE: int = 1 # 草稿就地应用，全对时才显示「应用」按钮
const VALUE_APPLY_INDEPENDENT: int = 2 # 草稿独立成层，进入草稿模式即显示「应用」按钮
const VALUE_AUTO_WIN: int = 3 # 草稿全对即自动提交，不用点应用
const VALUE_AUTO_WIN_PERSIST: int = 4 # 自动提交，且中途退出保留草稿


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "draft_mode"
	default_value = VALUE_CONTROL # 默认档：无草稿模式
	timing = ABTestManager.TIMING_GAME_START_NORMAL_21 # 染色时机：普通模式第 21 关起


# 是否开启草稿模式
func is_enabled() -> bool:
	return value() != VALUE_CONTROL


# 是否走「应用草稿」按钮流程（档位 1/2）
func has_apply_button() -> bool:
	var v: int = value()
	return v == VALUE_APPLY_INPLACE or v == VALUE_APPLY_INDEPENDENT


# 是否一进草稿模式就有独立「应用」按钮（档位 2）
func has_independent_apply_button() -> bool:
	return value() == VALUE_APPLY_INDEPENDENT


# 草稿全部正确时是否自动提交、不用玩家点应用（档位 3/4）
func auto_win_on_complete() -> bool:
	var v: int = value()
	return v == VALUE_AUTO_WIN or v == VALUE_AUTO_WIN_PERSIST


# 手动退出关卡时是否保留草稿（档位 4）
func keep_marks_on_manual_exit() -> bool:
	return value() == VALUE_AUTO_WIN_PERSIST


# 草稿是否长期保留（同档位 4）
func persist_draft_marks() -> bool:
	return value() == VALUE_AUTO_WIN_PERSIST
