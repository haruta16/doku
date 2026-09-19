# 目标(猫数)强调实验：0=对照组 1=第 10 关之后把「还要放几只猫」这个目标单独强调出来
extends AbConfigBase
class_name GoalEmphasisConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不做强调
const VALUE_SPLIT_BY_LEVEL: int = 1 # 按关卡区分是否强调

# 分界关卡：关卡号 > 10 才强调
const LEVEL_THRESHOLD: int = 10


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "goal_emphasis"
	default_value = VALUE_CONTROL # 默认档：不强调

	timing = ABTestManager.TIMING_GAME_START_NORMAL_11 # 染色时机：普通模式第 11 关起


# 该关卡是否强调猫数目标
func should_emphasize_cat_score(level: int) -> bool:
	return value() == VALUE_SPLIT_BY_LEVEL and level > LEVEL_THRESHOLD
