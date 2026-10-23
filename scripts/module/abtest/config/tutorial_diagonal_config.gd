## 实验配置 tutorial_diagonal：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name TutorialDiagonalConfig

# ---- 分组取值（1 未使用） ----
const VALUE_ADJACENT: int = 0 # 相邻格复制
const VALUE_DIAGONAL: int = 2 # 对角线复制


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "tutorial_diagonal"
	default_value = VALUE_ADJACENT
