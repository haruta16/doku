## 实验配置 privacy_pop：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PrivacyPopConfig

const VALUE_V1_UI: int = 0
const VALUE_V2_UI: int = 1
const VALUE_V3_UI: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "privacy_pop"
	default_value = VALUE_V1_UI
