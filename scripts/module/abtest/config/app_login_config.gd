## 实验配置 app_login：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AppLoginConfig

const VALUE_DEFAULT: int = 0

const VALUE_LOGIN_ONLY: int = 1

const VALUE_LOGIN_WITH_SELECT: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "app_login"
	default_value = VALUE_DEFAULT


func is_login_enabled() -> bool:
	return value() != VALUE_DEFAULT


func is_progress_select_enabled() -> bool:
	return int(peek_value()) == VALUE_LOGIN_WITH_SELECT
