## 实验配置 dda_rank：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DdaRankConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，失败不降档
const VALUE_RETRY_ONCE: int = 1 # 本关重试过或复活过才降档
const VALUE_TOOL_REVIVE: int = 2 # 用过道具或复活才降档
const VALUE_ANY_ACTION: int = 3 # 任何一次失败收场就降档


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dda_rank"
	default_value = VALUE_RETRY_ONCE
