## 实验配置 vibrate_combo：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name VibrateComboConfig

const VALUE_CONTROL: int = 0
const VALUE_STRONG: int = 1
const VALUE_STRONGER: int = 2
const VALUE_WEAK_TO_STRONG: int = 3
const VALUE_WEAKER_TO_STRONG: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "vibrate_combo"
	default_value = VALUE_CONTROL
