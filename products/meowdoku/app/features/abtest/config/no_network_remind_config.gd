## 实验配置 no_network_remind：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NoNetworkRemindConfig

const VALUE_OFF: int = 0

const VALUE_NO_NET_ONLY: int = 1

const VALUE_NO_NET_OR_NO_FILL: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "no_network_remind"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	return value() != VALUE_OFF


func covers_no_fill() -> bool:
	return value() == VALUE_NO_NET_OR_NO_FILL
