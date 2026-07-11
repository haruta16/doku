extends AbConfigBase
class_name RuleNormalRankConfig

const VALUE_CONTROL: int = 0
const VALUE_EXPERIMENT_A: int = 1
const VALUE_EXPERIMENT_B: int = 2
const VALUE_EXPERIMENT_C: int = 3
const VALUE_EXPERIMENT_D: int = 4
const VALUE_EXPERIMENT_E: int = 5
const VALUE_GROUP_F: int = 6
const VALUE_GROUP_G: int = 7
const VALUE_GROUP_H: int = 8
const VALUE_GROUP_I: int = 9
const VALUE_GROUP_J: int = 10
const VALUE_GROUP_K: int = 11


func _init() -> void:
	key = "rule_normal_rank"
	default_value = VALUE_EXPERIMENT_B
	timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_experiment_a() -> bool:
	return value() == VALUE_EXPERIMENT_A


func is_experiment_b() -> bool:
	return value() == VALUE_EXPERIMENT_B


func is_experiment_c() -> bool:
	return value() == VALUE_EXPERIMENT_C


func is_experiment_d() -> bool:
	return value() == VALUE_EXPERIMENT_D


func is_experiment_e() -> bool:
	return value() == VALUE_EXPERIMENT_E


func is_group_f() -> bool:
	return value() == VALUE_GROUP_F


func is_group_g() -> bool:
	return value() == VALUE_GROUP_G


func is_group_h() -> bool:
	return value() == VALUE_GROUP_H


func is_group_i() -> bool:
	return value() == VALUE_GROUP_I


func is_group_j() -> bool:
	return value() == VALUE_GROUP_J


func is_group_k() -> bool:
	return value() == VALUE_GROUP_K
