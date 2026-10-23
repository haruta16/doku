## 实验配置 dc_tag_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DcTagUiConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原角标
const VALUE_PAW: int = 1 # 用猫爪角标


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dc_tag_ui"
	default_value = VALUE_CONTROL
