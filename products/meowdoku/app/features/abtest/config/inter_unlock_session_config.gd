## 实验配置 inter_unlock_session：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name InterUnlockSessionConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_SESSION: int = 2 # 默认门槛：第 2 次启动


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "inter_unlock_session"
	default_value = DEFAULT_UNLOCK_SESSION


## 当前启动次数是否已达门槛
func is_unlocked() -> bool:
	return GameState.get_session_count() >= value()
