## 实验配置 prop_mouse：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PropMouseConfig

const VALUE_CONTROL: int = 0
const VALUE_ENABLED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "prop_mouse"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return enabled_for(int(value()))


static func enabled_for(v: int) -> bool:
	return v == VALUE_ENABLED
