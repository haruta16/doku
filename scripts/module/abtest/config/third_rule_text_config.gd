# 第三条规则文案实验：0=对照组 1~3=三种改写文案
extends AbConfigBase
class_name ThirdRuleTextConfig

# ---- 分组取值（即文案变体号） ----
const VALUE_CONTROL: int = 0 # 原文案
const VALUE_VARIANT_A: int = 1 # 改写文案 A
const VALUE_VARIANT_B: int = 2 # 改写文案 B
const VALUE_VARIANT_C: int = 3 # 改写文案 C


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "third_rule_text"
	default_value = VALUE_CONTROL # 默认档：原文案
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 取文案变体号（0~3），调用方按它选文案
func get_rule_text_variant() -> int:
	return value()
