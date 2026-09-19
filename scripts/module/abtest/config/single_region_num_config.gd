# 单格区域数量实验：限制「只含 1 格」的区域个数，超限就换题；0=不限制 1=超过 2 个换题 2=同 1，且 21 关起收紧到超过 1 个就换题
extends AbConfigBase
class_name SingleRegionNumConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 不限制
const VALUE_LIMITED: int = 1 # 单格区域超过 2 个就换题
const VALUE_STRICT: int = 2 # 基础限制 + 21 关起超过 1 个就换题（lk/sp 题库除外）


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "single_region_num"
	default_value = VALUE_DEFAULT # 默认档：不限制
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 是否启用基础限制（档位 1）
func is_single_region_limited() -> bool:
	return value() == VALUE_LIMITED


# 该关卡是否启用严格限制（档位 2 且关卡 >= 21）
func is_strict_limited_at(level_num: int) -> bool:
	return value() == VALUE_STRICT and level_num >= 21
