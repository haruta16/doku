## 实验配置 inter_timing：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name InterTimingConfig

const VALUE_IMMEDIATE: int = 0
const VALUE_DELAYED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "inter_timing"
	default_value = VALUE_IMMEDIATE


func should_delay_start_interstitial() -> bool:
	return value() == VALUE_DELAYED
