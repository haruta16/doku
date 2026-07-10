extends AbConfigBase
class_name InterUnlockLevelConfig
















const DEFAULT_UNLOCK_LEVEL: int = 11

func _init() -> void :
    key = "inter_unlock_level"
    default_value = DEFAULT_UNLOCK_LEVEL
    timing = ABTestManager.TIMING_GAME_START



func is_unlocked_at(level: int) -> bool:
    return level >= value()
