# 普通关开局提示条实验：0=不显示 1=文案变体 A 2=文案变体 B（带 IQ 文案） 3~6=四种卡片分组变体
extends AbConfigBase
class_name NormalStartToastConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 不显示开局提示条
const VALUE_TEXT_VARIANT_A: int = 1 # 文案变体 A
const VALUE_TEXT_VARIANT_B: int = 2 # 文案变体 B（显示 IQ 文案）

const VALUE_GROUP1: int = 3 # 卡片分组 1（配 Card2）
const VALUE_GROUP2: int = 4 # 卡片分组 2（配 Card4）
const VALUE_GROUP3: int = 5 # 卡片分组 3（配 Card5）
const VALUE_GROUP4: int = 6 # 卡片分组 4（配 Card6）


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "normal_start_toast"
	default_value = VALUE_HIDE # 默认档：不显示
	timing = ABTestManager.TIMING_GAME_START_NORMAL_11 # 染色时机：普通模式第 11 关起


# 是否显示开局提示条（非 0 档）
func should_show_toast() -> bool:
	return value() != VALUE_HIDE


# 是否显示 IQ 文案（档位 >=2）
func should_show_iq_text() -> bool:
	return value() >= VALUE_TEXT_VARIANT_B


# 取该分组用的卡片名：组 2/3/4 对应 Card4/5/6，其余落回 Card2
func get_variant_card() -> String:
	match value():
		VALUE_GROUP2:
			return "Card4"
		VALUE_GROUP3:
			return "Card5"
		VALUE_GROUP4:
			return "Card6"
		_:
			return "Card2"
