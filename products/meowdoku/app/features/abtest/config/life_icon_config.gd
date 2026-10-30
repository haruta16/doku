## 实验配置 life_icon：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LifeIconConfig

# ---- 分组取值 ----
const VALUE_HEART: int = 0 # 爱心
const VALUE_FISH: int = 1 # 小鱼
const VALUE_LIGHTNING: int = 2 # 闪电
const VALUE_FISH_C1: int = 3
const VALUE_FISH_C2: int = 4
const VALUE_FISH_C3: int = 5


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "life_icon"
	default_value = VALUE_FISH
