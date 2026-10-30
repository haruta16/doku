## 实验配置 level_btn_continue：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LevelBtnContinueConfig

const VALUE_OFF: int = 0
const VALUE_PROGRESS: int = 1
const VALUE_TIME: int = 2
const VALUE_LEVEL_WITH_CONTINUE: int = 3
const VALUE_CONTINUE_ONLY: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "level_btn_continue"

	default_value = VALUE_OFF


func is_enabled() -> bool:
	return value() != VALUE_OFF


func shows_progress() -> bool:
	return value() == VALUE_PROGRESS


func shows_time() -> bool:
	return value() == VALUE_TIME


func shows_level_with_continue() -> bool:
	return value() == VALUE_LEVEL_WITH_CONTINUE


func is_continue_only() -> bool:
	return value() == VALUE_CONTINUE_ONLY
