## 实验配置 normal_start_toast_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NormalStartToastTextConfig

const VALUE_CONTROL: int = 0
const VALUE_G1_CAT_COMPANION: int = 1
const VALUE_G2_SOCIAL_PROOF: int = 2
const VALUE_G3_HYBRID: int = 3
const VALUE_G4_CAT_IMMERSION: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_start_toast_text"
	default_value = VALUE_G2_SOCIAL_PROOF
