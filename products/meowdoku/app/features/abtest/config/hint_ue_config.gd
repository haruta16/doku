## 实验配置 hint_ue：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HintUeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，原提示流程
const VALUE_NEW_FLOW: int = 1 # 新版提示流程
const VALUE_CLOSE_BTN: int = 2 # 新版流程，末尾用关闭按钮


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "hint_ue"
	default_value = VALUE_CONTROL
