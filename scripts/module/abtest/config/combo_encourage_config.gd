## 实验配置 combo_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ComboEncourageConfig

# ---- 分组取值 ----
const VALUE_DISABLED: int = 0 # 关闭连击鼓励
const VALUE_ENCOURAGE_FIXED: int = 1 # 只出固定鼓励文案
const VALUE_ENCOURAGE_VOICE: int = 2 # 文案 + 语音
const VALUE_ENCOURAGE_SCORE: int = 3 # 额外显示连击得分
const VALUE_ENCOURAGE_IQ: int = 4 # 分数以 IQ 形式展示
const VALUE_ENCOURAGE_FOLLOW: int = 5 # 分数 + 跟着连击位置跑的猫
const VALUE_ENCOURAGE_VOICE_FEMALE: int = 6 # 语音换女声


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "combo_encourage"
	default_value = VALUE_ENCOURAGE_SCORE
