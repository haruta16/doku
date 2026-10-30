## 实验配置 unfinished_game_open：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name UnfinishedGameOpenConfig

const VALUE_CONTROL: int = 0
const VALUE_ALL_SESSION: int = 1
const VALUE_NON_FIRST_SESSION: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "unfinished_game_open"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return value() >= VALUE_ALL_SESSION


func requires_non_first_session() -> bool:
	return value() == VALUE_NON_FIRST_SESSION
