## 实验配置 dc_endgame_save：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DcEndgameSaveConfig

const VALUE_OFF: int = 0
const VALUE_SAME_SESSION: int = 1
const VALUE_ALL_DAY: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dc_endgame_save"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	return value() == VALUE_SAME_SESSION or value() == VALUE_ALL_DAY


func requires_same_session() -> bool:
	return value() == VALUE_SAME_SESSION
