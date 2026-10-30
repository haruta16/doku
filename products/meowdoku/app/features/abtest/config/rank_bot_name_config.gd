## 实验配置 rank_bot_name：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
class_name RankBotNameConfig
extends AbConfigBase

const VALUE_CONTROL: int = 0
const VALUE_ORIGINAL_WEIGHTED: int = 1
const VALUE_LOCALIZED_WEIGHTED: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_bot_name"
	default_value = VALUE_CONTROL
