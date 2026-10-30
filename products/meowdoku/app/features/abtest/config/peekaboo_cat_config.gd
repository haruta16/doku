## 实验配置 peekaboo_cat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PeekabooCatConfig

const VALUE_OFF: int = 0
const VALUE_FISH_1: int = 1
const VALUE_AD_POPUP: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "peekaboo_cat"
	default_value = VALUE_OFF


func has_peekaboo() -> bool:
	return int(peek_value()) != VALUE_OFF


func needs_ad_popup() -> bool:
	return int(peek_value()) == VALUE_AD_POPUP
