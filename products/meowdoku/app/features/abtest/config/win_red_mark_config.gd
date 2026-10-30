## 实验配置 win_red_mark：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WinRedMarkConfig

const VALUE_KEEP_RED: int = 0
const VALUE_FADE_TO_WHITE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "win_red_mark"
	default_value = VALUE_KEEP_RED


func should_fade_error_marks_to_white_on_win() -> bool:
	return value() == VALUE_FADE_TO_WHITE
