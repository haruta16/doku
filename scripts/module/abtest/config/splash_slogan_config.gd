# 启动页标语实验：0=对照组原标语 1=从猫标语池里随机 2=当天首次启动固定第 1 句、当天后续再随机
extends AbConfigBase
class_name SplashSloganConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原标语
const VALUE_CAT_RANDOM: int = 1 # 猫标语，每次随机
const VALUE_CAT_DAILY_FIXED: int = 2 # 猫标语，当天固定

# ---- 猫标语池 ----
const CAT_SLOGAN_COUNT: int = 35 # 标语总条数；随机档取 1~35，当天固定档的后续启动取 2~35

const CAT_DAILY_FIXED_KEY: String = "SPLASH_CAT_01" # 当天首次启动固定用的标语 key


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "splash_slogan"
	default_value = VALUE_CONTROL # 默认档：原标语
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否使用猫标语（档位 1/2）
func is_cat_slogan() -> bool:
	return value() == VALUE_CAT_RANDOM or value() == VALUE_CAT_DAILY_FIXED


# 是否需要「当天固定」逻辑（档位 2）
func has_daily_fixed_slogan() -> bool:
	return value() == VALUE_CAT_DAILY_FIXED
