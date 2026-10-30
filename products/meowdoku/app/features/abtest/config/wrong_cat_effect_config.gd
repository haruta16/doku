## 实验配置 wrong_cat_effect：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WrongCatEffectConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，全部保留
const VALUE_NO_SHAKE: int = 1 # 错标时不震动
const VALUE_LOW_WRONG_VOLUME: int = 2 # 错标音效降低音量
const VALUE_NO_RED_FILL: int = 3 # 错标格不填红
const VALUE_LOW_FAIL_VOLUME: int = 4 # 失败音效降低音量
const VALUE_ALL_REDUCED: int = 5 # 以上全部弱化


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "wrong_cat_effect"
	default_value = VALUE_CONTROL
