## 实验配置 goal_emphasis：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GoalEmphasisConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不做强调
const VALUE_SPLIT_BY_LEVEL: int = 1 # 按关卡区分是否强调

## 分界关卡：关卡号 > 10 才强调
const LEVEL_THRESHOLD: int = 10


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "goal_emphasis"
	default_value = VALUE_CONTROL
