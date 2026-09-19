# 规则展示形态实验：0=纯文字 1=第三条用图 2=全部用图 3=图标+文字 4=第 10 关起折叠 5=信息弹窗 6=设置页入口 7=单页滑动
extends AbConfigBase
class_name RuleTextConfig

# ---- 分组取值 ----
const VALUE_TEXT: int = 0 # 纯文字展示
const VALUE_THIRD_IMG: int = 1 # 第三条规则用图
const VALUE_ALL_IMG: int = 2 # 全部规则用图
const VALUE_ICON_TEXT: int = 3 # 图标 + 文字
const VALUE_COLLAPSE_10: int = 4 # 第 10 关起折叠规则条
const VALUE_INFO_POPUP: int = 5 # 规则放进信息弹窗
const VALUE_SETTING_ENTRY: int = 6 # 规则挪到设置页入口
const VALUE_SINGLE_SWIPE: int = 7 # 单页滑动查看规则


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "rule_text"
	default_value = VALUE_TEXT # 默认档：纯文字
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否第三条规则用图
func is_third_img() -> bool:
	return value() == VALUE_THIRD_IMG


# 是否全部规则用图
func is_all_img() -> bool:
	return value() == VALUE_ALL_IMG


# 是否图标 + 文字
func is_icon_text() -> bool:
	return value() == VALUE_ICON_TEXT


# 是否第 10 关起折叠
func is_collapse_10() -> bool:
	return value() == VALUE_COLLAPSE_10


# 是否放进信息弹窗
func is_info_popup() -> bool:
	return value() == VALUE_INFO_POPUP


# 是否挪到设置页入口
func is_setting_entry() -> bool:
	return value() == VALUE_SETTING_ENTRY


# 是否单页滑动
func is_single_swipe() -> bool:
	return value() == VALUE_SINGLE_SWIPE


# 取整型档位，供需要 switch 的调用点使用
func value_i() -> int:
	return int(value())
