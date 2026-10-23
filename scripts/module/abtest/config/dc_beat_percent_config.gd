## 实验配置 dc_beat_percent：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DcBeatPercentConfig

const VALUE_CONTROL: int = 0

const VALUE_ANCHOR_CURVE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dc_beat_percent"
	default_value = VALUE_CONTROL


func is_anchor_curve() -> bool:
	return value() == VALUE_ANCHOR_CURVE
