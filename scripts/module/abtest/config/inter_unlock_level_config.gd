# 插屏关卡门槛：普通关打到第几关才开始展示插屏
extends AbConfigBase
class_name InterUnlockLevelConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_LEVEL: int = 11 # 默认门槛：第 11 关


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "inter_unlock_level"
	default_value = DEFAULT_UNLOCK_LEVEL # 默认档：第 11 关解锁
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 给定关卡是否已达门槛
func is_unlocked_at(level: int) -> bool:
	return level >= value()
