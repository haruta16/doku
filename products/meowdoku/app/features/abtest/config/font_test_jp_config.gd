## 实验配置 font_test_jp：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FontTestJpConfig

const VALUE_NONE: int = 0
const VALUE_NOTO_WEIGHTED: int = 1
const VALUE_YUAN_QUAN_YUAN_2TW: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "font_test_jp"
	default_value = VALUE_NONE


func is_noto_weighted() -> bool:
	return value() == VALUE_NOTO_WEIGHTED


func is_yuan_quan_yuan_2tw() -> bool:
	return value() == VALUE_YUAN_QUAN_YUAN_2TW
