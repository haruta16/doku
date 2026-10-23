## 实验配置 daily_streak_page：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailyStreakPageConfig

const VALUE_LEGACY_HOME_PAGE: int = 0

const VALUE_HISTORY_HOME_PAGE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "daily_streak_page"
	default_value = VALUE_LEGACY_HOME_PAGE


func is_history_page_enabled() -> bool:
	return value() == VALUE_HISTORY_HOME_PAGE
