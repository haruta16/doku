## 实验配置 fail_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FailUiConfig

const VALUE_CONTROL: int = 0
const VALUE_REPLACE: int = 1
const VALUE_ADD: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "fail_ui"
	default_value = VALUE_CONTROL


func shows_progress_bar() -> bool:
	var v: int = int(value())
	return v == VALUE_REPLACE or v == VALUE_ADD


func hides_count_text() -> bool:
	return int(value()) == VALUE_REPLACE
