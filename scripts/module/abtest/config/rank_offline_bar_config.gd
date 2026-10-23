## 实验配置 rank_offline_bar：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RankOfflineBarConfig

const VALUE_CONTROL: int = 0
const VALUE_BAR: int = 1
const VALUE_BAR_AND_COUNTDOWN: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_offline_bar"
	default_value = VALUE_CONTROL


func has_offline_bar() -> bool:
	return value() != VALUE_CONTROL


func has_offline_countdown() -> bool:
	return value() == VALUE_BAR_AND_COUNTDOWN
