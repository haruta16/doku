extends AbConfigBase
class_name SplashSloganConfig







const VALUE_CONTROL: int = 0
const VALUE_CAT_RANDOM: int = 1
const VALUE_CAT_DAILY_FIXED: int = 2


const CAT_SLOGAN_COUNT: int = 35

const CAT_DAILY_FIXED_KEY: String = "SPLASH_CAT_01"

func _init() -> void :
    key = "splash_slogan"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_APP_START


func is_cat_slogan() -> bool:
    return value() == VALUE_CAT_RANDOM or value() == VALUE_CAT_DAILY_FIXED


func has_daily_fixed_slogan() -> bool:
    return value() == VALUE_CAT_DAILY_FIXED
