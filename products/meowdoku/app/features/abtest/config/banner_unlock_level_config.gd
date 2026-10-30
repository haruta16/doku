## 实验配置 banner_unlock_level：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BannerUnlockLevelConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_LEVEL: int = 11 # 默认门槛：第 11 关


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "banner_unlock_level"
	default_value = DEFAULT_UNLOCK_LEVEL


## 给定关卡是否已达门槛
func is_unlocked_at(level: int) -> bool:
	return level >= value()
