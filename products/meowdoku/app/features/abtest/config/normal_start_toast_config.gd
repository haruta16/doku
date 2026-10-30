## 实验配置 normal_start_toast：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
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

const VALUE_V2_UP_BOARD: int = 7
const VALUE_V2_UP_GOLDEN: int = 8
const VALUE_V2_SHORT_HOLD: int = 9
const VALUE_V2_DYNAMIC_HOLD: int = 10
const VALUE_V2_NEW_FORM: int = 11

const CARD_BASELINE: String = "Card6"

const HOLD_DEFAULT: float = 1.4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_start_toast"
	default_value = VALUE_GROUP4
