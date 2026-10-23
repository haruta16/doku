## 实验配置 daily_streak_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailyStreakEncourageConfig

const VALUE_DISABLED: int = 0
const VALUE_TAG_WITH_CAT: int = 1
const VALUE_TAG_ONLY: int = 2
const VALUE_TOP_ONLY: int = 3
const VALUE_TOP_WITH_CAT: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "daily_streak_encourage"
	default_value = VALUE_DISABLED


static func enabled_for(v: int) -> bool:
	return v != VALUE_DISABLED


static func has_cat_for(v: int) -> bool:
	return v == VALUE_TAG_WITH_CAT or v == VALUE_TOP_WITH_CAT


static func uses_top_percent_for(v: int) -> bool:
	return v == VALUE_TOP_ONLY or v == VALUE_TOP_WITH_CAT


func is_enabled() -> bool:
	return enabled_for(value())


func has_cat() -> bool:
	return has_cat_for(value())


func uses_top_percent() -> bool:
	return uses_top_percent_for(value())
