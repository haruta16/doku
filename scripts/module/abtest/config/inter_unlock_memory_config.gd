# 插屏内存门槛：设备物理内存低于该值就不展示插屏，避免低端机被广告拖垮
extends AbConfigBase
class_name InterUnlockMemoryConfig

# ---- 门槛值（单位 MB） ----
const DEFAULT_UNLOCK_MEMORY_MB: int = 300 # 默认门槛：300MB


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "inter_unlock_memory"
	default_value = DEFAULT_UNLOCK_MEMORY_MB # 默认档：300MB
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 设备内存是否达标；读不到物理内存时按达标处理（放行）
func is_unlocked_for_device() -> bool:
	var physical_bytes: int = int(OS.get_memory_info().get("physical", -1))
	if physical_bytes <= 0:
		return true
	var ram_mb: int = physical_bytes / (1024 * 1024)
	return ram_mb >= value()
