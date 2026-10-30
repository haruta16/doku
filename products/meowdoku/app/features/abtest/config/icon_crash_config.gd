## 实验配置 icon_crash：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name IconCrashConfig

# ---- 分组取值 ----
const VALUE_HEART_CRASH: int = 0 # 心形碎裂
const VALUE_NO_CRASH: int = 1 # 不碎裂
const VALUE_FISH_CRASH: int = 2 # 鱼形碎裂


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "icon_crash"
	default_value = VALUE_HEART_CRASH
