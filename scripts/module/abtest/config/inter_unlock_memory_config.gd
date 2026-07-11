extends AbConfigBase
class_name InterUnlockMemoryConfig

const DEFAULT_UNLOCK_MEMORY_MB: int = 300


func _init() -> void:
	key = "inter_unlock_memory"
	default_value = DEFAULT_UNLOCK_MEMORY_MB
	timing = ABTestManager.TIMING_GAME_START


func is_unlocked_for_device() -> bool:
	var physical_bytes: int = int(OS.get_memory_info().get("physical", -1))
	if physical_bytes <= 0:
		return true
	var ram_mb: int = physical_bytes / (1024 * 1024)
	return ram_mb >= value()
