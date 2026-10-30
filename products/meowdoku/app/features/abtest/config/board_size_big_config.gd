## 实验配置 board_size_big：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BoardSizeBigConfig

const VALUE_NORMAL: int = 0
const VALUE_ENLARGED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "board_size_big"
	default_value = VALUE_ENLARGED
