## 实验配置 pre_cat_fx：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PreCatFxConfig

const VALUE_OFF: int = 0

const VALUE_WAVE: int = 1

const VALUE_SPOTLIGHT: int = 2

const VALUE_CAT_APPEAR: int = 3

const VALUE_ROW_SWEEP: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "pre_cat_fx"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	var v: int = value()
	return v == VALUE_WAVE or v == VALUE_SPOTLIGHT or v == VALUE_CAT_APPEAR or v == VALUE_ROW_SWEEP
