## 实验配置 splash_slogan：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SplashSloganConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原标语

const VALUE_CAT_RANDOM: int = 1 # 猫标语，每次随机

const VALUE_CAT_DAILY_FIXED: int = 2 # 猫标语，当天固定

const VALUE_RICH_POOL: int = 3

const VALUE_RICH_TIME_BASED: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "splash_slogan"
	default_value = VALUE_CONTROL


static func uses_rich_pool_for(group: int) -> bool:
	return group == VALUE_RICH_POOL or group == VALUE_RICH_TIME_BASED


static func is_time_based_for(group: int) -> bool:
	return group == VALUE_RICH_TIME_BASED


func uses_rich_pool() -> bool:
	return uses_rich_pool_for(int(peek_value()))


func is_time_based() -> bool:
	return is_time_based_for(int(peek_value()))
