## 实验配置 error_catface：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ErrorCatfaceConfig

# ---- 分组取值 ----
const VALUE_FRUSTRATED: int = 0 # 懊恼
const VALUE_SURPRISED: int = 1 # 惊讶
const VALUE_TEARFUL: int = 2 # 流泪
const VALUE_SHAKE_ONLY: int = 3 # 只摇头，不换脸


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "error_catface"
	default_value = VALUE_FRUSTRATED
