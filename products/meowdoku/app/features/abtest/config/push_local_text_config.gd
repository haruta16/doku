## 实验配置 push_local_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PushLocalTextConfig

# ---- 分组取值 ----
const VALUE_LEGACY: int = 0 # 老文案池
const VALUE_NEW_POOL: int = 1 # 新文案池
const VALUE_NEW_POOL_2: int = 2
const VALUE_CLR_G1: int = 3
const VALUE_CLR_G2: int = 4
const VALUE_CLR_G3: int = 5
const VALUE_CLR_G4: int = 6


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "push_local_text"
	default_value = VALUE_LEGACY


func clr_pool_group() -> int:
	var v: int = value()
	if v >= VALUE_CLR_G1 and v <= VALUE_CLR_G4:
		return v - VALUE_CLR_G1 + 1
	return 0
