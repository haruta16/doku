## 实验配置 text_highlight：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name TextHighlightConfig

const VALUE_CONTROL: int = 0
const VALUE_ALWAYS: int = 1
const VALUE_SESSION_RANDOM: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "text_highlight"
	default_value = VALUE_CONTROL


func should_always_highlight() -> bool:
	return value() == VALUE_ALWAYS


func should_randomize_per_key() -> bool:
	return value() == VALUE_SESSION_RANDOM
