# 开屏 banner 的启动次数门槛：第几次启动 App 之后才展示 banner
extends AbConfigBase
class_name BannerUnlockSessionConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_SESSION: int = 2 # 默认门槛：第 2 次启动


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "banner_unlock_session"
	default_value = DEFAULT_UNLOCK_SESSION # 默认档：第 2 次启动解锁
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 当前启动次数是否已达门槛
func is_unlocked() -> bool:
	return GameState.get_session_count() >= value()
