## 实验配置 blind_mod_color：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BlindModColorConfig

const VALUE_CONTROL: int = 0
const VALUE_DARK_1: int = 1
const VALUE_DARK_2: int = 2
const VALUE_DARK_3: int = 3
const VALUE_LIGHT_1: int = 4
const VALUE_LIGHT_2: int = 5


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "blind_mod_color"
	default_value = VALUE_CONTROL


func pattern_color_for(background_color: Color) -> Color:
	return ColorblindPatternVariants.color_for(background_color, int(value()))
