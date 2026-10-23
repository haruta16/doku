## 实验配置 font_test_en：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FontTestEnConfig

const VALUE_ROBOTO: int = 0
const VALUE_BALOO2: int = 1
const VALUE_ALIMAMA: int = 2
const VALUE_GEOM_EN: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "font_test_en"
	default_value = VALUE_ROBOTO


func is_baloo2() -> bool:
	return value() == VALUE_BALOO2


func is_alimama() -> bool:
	return value() == VALUE_ALIMAMA


func is_geom_en() -> bool:
	return value() == VALUE_GEOM_EN
