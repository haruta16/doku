# 新手教学复制方向实验：0=相邻（上下左右）复制 2=对角线复制（1 未使用）
extends AbConfigBase
class_name TutorialDiagonalConfig

# ---- 分组取值（1 未使用） ----
const VALUE_ADJACENT: int = 0 # 相邻格复制
const VALUE_DIAGONAL: int = 2 # 对角线复制


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "tutorial_diagonal"
	default_value = VALUE_ADJACENT # 默认档：相邻复制
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 教学是否用对角线复制
func is_diagonal_copy() -> bool:
	return value() == VALUE_DIAGONAL
