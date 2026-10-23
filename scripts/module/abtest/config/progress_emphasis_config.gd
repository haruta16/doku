## 实验配置 progress_emphasis：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ProgressEmphasisConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 沿用文字进度
const VALUE_PROGRESS_BAR: int = 1 # 换成进度条


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "progress_emphasis"
	default_value = VALUE_DEFAULT
