# 普通关难度与规则分组实验（A~K 共 11 组）：决定关卡尺寸曲线、难度上限与随机方式。取值在 LevelData 里被当数字分支使用，不只是布尔判断
extends AbConfigBase
class_name RuleNormalRankConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，走原难度曲线
const VALUE_EXPERIMENT_A: int = 1 # A 组：难度只按关卡封顶，不做随机
const VALUE_EXPERIMENT_B: int = 2 # B 组（默认）：封顶后在 [2, 上限] 内随机
const VALUE_EXPERIMENT_C: int = 3 # C 组：只在 [上限-1, 上限] 内小幅随机
const VALUE_EXPERIMENT_D: int = 4 # D 组：封顶更紧，且 51 关起下限抬到 2；难关固定 rank5
const VALUE_EXPERIMENT_E: int = 5 # E 组：同 D，但只在 101 关后随机
const VALUE_GROUP_F: int = 6 # F 组：51 关起每逢末位 1 的关卡强制简单，其余随机
const VALUE_GROUP_G: int = 7 # G 组：同 F，并记录上一段是否拉满，拉满则本次降 1
const VALUE_GROUP_H: int = 8 # H 组：上限收得更紧（51 关起封 4）；难关 rank5/N
const VALUE_GROUP_I: int = 9 # I 组：上限最紧（21 关起封 3）；难关 rank4/N
const VALUE_GROUP_J: int = 10 # J 组：分档最细（21/51/101/201），自带尺寸曲线与难关判定，201 关后难关可进 H 档
const VALUE_GROUP_K: int = 11 # K 组：同 J 的封顶，但 201 关后的难关有一半概率不走 H 档


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "rule_normal_rank"
	default_value = VALUE_EXPERIMENT_B # 默认档：B 组
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 是否 A 组
func is_experiment_a() -> bool:
	return value() == VALUE_EXPERIMENT_A


# 是否 B 组（默认档）
func is_experiment_b() -> bool:
	return value() == VALUE_EXPERIMENT_B


# 是否 C 组
func is_experiment_c() -> bool:
	return value() == VALUE_EXPERIMENT_C


# 是否 D 组
func is_experiment_d() -> bool:
	return value() == VALUE_EXPERIMENT_D


# 是否 E 组
func is_experiment_e() -> bool:
	return value() == VALUE_EXPERIMENT_E


# 是否 F 组
func is_group_f() -> bool:
	return value() == VALUE_GROUP_F


# 是否 G 组
func is_group_g() -> bool:
	return value() == VALUE_GROUP_G


# 是否 H 组
func is_group_h() -> bool:
	return value() == VALUE_GROUP_H


# 是否 I 组
func is_group_i() -> bool:
	return value() == VALUE_GROUP_I


# 是否 J 组（多个页面据此切换尺寸/难关口径）
func is_group_j() -> bool:
	return value() == VALUE_GROUP_J


# 是否 K 组
func is_group_k() -> bool:
	return value() == VALUE_GROUP_K
