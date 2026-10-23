## 实验配置 rate_us_pop：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RateUsPopConfig

# ---- 分组取值（字符串型，走 get_ab_string） ----
const VALUE_GATE_LV8: String = "0" # 第 8 关起即可弹
const VALUE_GATE_LV15: String = "1" # 第 15 关起才弹
const VALUE_HOME_AFTER_WIN: String = "2" # 不在过关时弹，改成回首页时弹
const VALUE_WIN_STREAK_5: String = "3" # 第 15 关起且本 session 连赢 5 局

const GATE_LV_BASELINE: int = 8


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rate_us_pop"
	default_value = VALUE_GATE_LV8
