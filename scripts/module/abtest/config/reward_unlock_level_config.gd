extends AbConfigBase
class_name RewardUnlockLevelConfig
















const DEFAULT_UNLOCK_LEVEL: int = 0

func _init() -> void :
    key = "reward_unlock_level"
    default_value = DEFAULT_UNLOCK_LEVEL
    timing = ABTestManager.TIMING_GAME_START




func is_reward_required_at(level: int) -> bool:
    return level >= value()
