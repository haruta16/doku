# 自动打叉实验：0=对照组（全手动） 1=放猫后自动补叉+开局预填 2=格子上加「点」按钮 3=自动补叉但只在前 6 关 4=叉锁定不可改 5=每日挑战看广告换自动打叉
extends AbConfigBase
class_name GameAutoMarkConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，纯手动
const VALUE_AUTO_CROSS: int = 1 # 放猫后自动补叉，开局也预填已定的叉
const VALUE_DOT_TOGGLE: int = 2 # 棋盘格子加「点」按钮辅助打叉
const VALUE_AUTO_CROSS_LV6: int = 3 # 同自动补叉，但只在前 6 关生效
const VALUE_LOCK_X: int = 4 # 打上的叉锁定为不可修改
const VALUE_PROP_AD: int = 5 # 每日挑战看广告换自动打叉


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "game_auto_mark"
	default_value = VALUE_CONTROL # 默认档：纯手动
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用「放猫后自动补叉」（档位 1/3）
func is_auto_cross_after_cat() -> bool:
	return value() == VALUE_AUTO_CROSS or value() == VALUE_AUTO_CROSS_LV6


# 该关卡是否启用放猫补叉：档位 1 全程，档位 3 只到第 6 关
func after_cat_enabled_at(level: int) -> bool:
	match value():
		VALUE_AUTO_CROSS:
			return true
		VALUE_AUTO_CROSS_LV6:
			return level <= 6
		_:
			return false


# 该关卡是否启用开局预填叉：档位 1 到第 10 关，档位 3 到第 6 关
func prefill_auto_cross_enabled_at(level: int) -> bool:
	match value():
		VALUE_AUTO_CROSS:
			return level <= 10
		VALUE_AUTO_CROSS_LV6:
			return level <= 6
		_:
			return false


# 是否「点」按钮模式（档位 2）
func is_dot_toggle_mode() -> bool:
	return value() == VALUE_DOT_TOGGLE


# 该关卡是否显示格子上的「点」按钮（仅档位 2 且关卡 > 30）
func is_dot_toggle_enabled_at(level: int) -> bool:
	return value() == VALUE_DOT_TOGGLE and level > 30


# 是否锁叉模式（档位 4）
func is_lock_x_mode() -> bool:
	return value() == VALUE_LOCK_X


# 锁叉在该关卡是否生效（档位 4 全关卡生效，关卡参数未使用）
func is_lock_x_enabled_at(_level: int) -> bool:
	return is_lock_x_mode()


# 是否广告道具模式（档位 5）
func is_prop_ad_mode() -> bool:
	return value() == VALUE_PROP_AD


# 档位 5 且今天已通过广告解锁自动打叉（读 GameState 的当日标记）
func is_prop_ad_active_for_daily() -> bool:
	return is_prop_ad_mode() and GameState.is_daily_auto_mark_enabled_for_today()
