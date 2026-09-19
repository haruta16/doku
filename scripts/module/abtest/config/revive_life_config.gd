# 复活补命实验：复活后补几条命、按钮长什么样；0=对照组（补 1 条） 1~3=补满 3 条（2=两行按钮，3=备用按钮文案）
extends AbConfigBase
class_name ReviveLifeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，只补 1 条命
const VALUE_GROUP_1: int = 1 # 补 3 条命
const VALUE_GROUP_2: int = 2 # 补 3 条命，按钮用两行文案
const VALUE_GROUP_3: int = 3 # 补 3 条命，按钮用备用文案


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "revive_life"
	default_value = VALUE_CONTROL # 默认档：补 1 条命
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 复活补的命数：对照组 1，其余档位 3
func get_lives_to_restore() -> int:
	return 1 if value() == VALUE_CONTROL else 3


# 复活按钮是否用两行文案（档位 2）
func is_two_line_button() -> bool:
	return value() == VALUE_GROUP_2


# 是否用备用按钮文案（档位 3）
func is_alt_button_text() -> bool:
	return value() == VALUE_GROUP_3
