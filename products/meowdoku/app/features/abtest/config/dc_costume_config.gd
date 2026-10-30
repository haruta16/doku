## 实验配置 dc_costume：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DcCostumeConfig

const VALUE_OFF: int = 0
const VALUE_ON: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dc_costume"
	default_value = VALUE_OFF


func has_costume() -> bool:
	return int(peek_value()) == VALUE_ON


func can_replay() -> bool:
	return int(peek_value()) == VALUE_ON
