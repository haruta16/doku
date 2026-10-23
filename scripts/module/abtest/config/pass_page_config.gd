## 实验配置 pass_page：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PassPageConfig

const VALUE_CONTROL: int = 0
const VALUE_G1: int = 1
const VALUE_G2: int = 2
const VALUE_G4: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "pass_page"
	default_value = VALUE_CONTROL


func is_g1() -> bool:
	return value() == VALUE_G1


func is_g2() -> bool:
	return value() == VALUE_G2


func is_g4() -> bool:
	return value() == VALUE_G4
