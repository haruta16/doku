extends AbConfigBase
class_name InterUnlockSessionConfig

const DEFAULT_UNLOCK_SESSION: int = 2


func _init() -> void:
	key = "inter_unlock_session"
	default_value = DEFAULT_UNLOCK_SESSION
	timing = ABTestManager.TIMING_GAME_START


func is_unlocked() -> bool:
	return GameState.get_session_count() >= value()
