extends AbConfigBase
class_name CommonRewardadLogicConfig

const VALUE_NO_RESTORE: int = 0
const VALUE_RESTORE: int = 1


func _init() -> void:
	key = "common_rewardad_logic"
	default_value = VALUE_NO_RESTORE
	timing = ABTestManager.TIMING_GAME_START


func should_grant_reward_restore() -> bool:
	return value() == VALUE_RESTORE
