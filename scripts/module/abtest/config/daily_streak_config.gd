extends AbConfigBase
class_name DailyStreakConfig









const VALUE_CONTROL: int = 0
const VALUE_BASIC: int = 1
const VALUE_CHALLENGE_ONLY: int = 2
const VALUE_NO_REWARD: int = 3
const VALUE_NO_LIT: int = 4

func _init() -> void :
    key = "daily_streak"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_APP_START

func is_enabled() -> bool:
    return value() != VALUE_CONTROL

func is_challenge_only() -> bool:
    return value() == VALUE_CHALLENGE_ONLY

func has_reward() -> bool:
    var v: int = value()
    return v == VALUE_BASIC or v == VALUE_CHALLENGE_ONLY or v == VALUE_NO_LIT


func is_skip_lit() -> bool:
    return value() == VALUE_NO_LIT
