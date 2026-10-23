## 实验配置 warn_life：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WarnLifeConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 不提醒
const VALUE_SHOW: int = 1 # 弹生命告警


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "warn_life"
	default_value = VALUE_HIDE
