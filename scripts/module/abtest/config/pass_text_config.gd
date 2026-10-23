## 实验配置 pass_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PassTextConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组原文案
const VALUE_BEAT_PERCENT: int = 1 # 显示击败百分比
const VALUE_V2: int = 2 # 第二版文案

const VALUE_V3_G1: int = 3
const VALUE_V3_G2: int = 4
const VALUE_V3_G3: int = 5

const VALUE_V4_G1: int = 6
const VALUE_V4_G2: int = 7
const VALUE_V4_G3: int = 8


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "pass_text"
	default_value = VALUE_V3_G1
