## 实验配置 rule_normal_rank：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
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


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rule_normal_rank"
	default_value = VALUE_GROUP_H
