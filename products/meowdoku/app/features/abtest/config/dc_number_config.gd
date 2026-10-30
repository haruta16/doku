## 实验配置 dc_number：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DcNumberConfig

const VALUE_CONTROL: int = 0
const VALUE_COUNT: int = 1
const VALUE_COUNT_AVATAR: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dc_number"
	default_value = VALUE_CONTROL


func is_count_visible() -> bool:
	var v: int = int(value())
	return v == VALUE_COUNT or v == VALUE_COUNT_AVATAR


func has_avatars() -> bool:
	return int(value()) == VALUE_COUNT_AVATAR
