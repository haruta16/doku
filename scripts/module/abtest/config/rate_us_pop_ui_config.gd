# 评分弹窗 UI 版本实验：0=旧版界面资源 1=新版界面资源
extends AbConfigBase
class_name RateUsPopUiConfig

# ---- 分组取值 ----
const VALUE_OLD_UI: int = 0 # 旧版评分界面
const VALUE_NEW_UI: int = 1 # 新版评分界面


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "rate_us_pop_ui"
	default_value = VALUE_OLD_UI # 默认档：旧版界面
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否用新版评分界面
func is_new_ui() -> bool:
	return value() == VALUE_NEW_UI
