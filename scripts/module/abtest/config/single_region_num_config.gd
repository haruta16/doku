## 实验配置 single_region_num：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SingleRegionNumConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 不限制
const VALUE_LIMITED: int = 1 # 单格区域超过 2 个就换题
const VALUE_STRICT: int = 2 # 基础限制 + 21 关起超过 1 个就换题（lk/sp 题库除外）
const VALUE_ALL_ONE: int = 3
const VALUE_ZERO_51: int = 4
const VALUE_ZERO_101: int = 5

const SINGLE_LIMIT_BASELINE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "single_region_num"

	default_value = VALUE_ALL_ONE


func single_limit_at(_level_num: int, _rank: int) -> int:
	return SINGLE_LIMIT_BASELINE
