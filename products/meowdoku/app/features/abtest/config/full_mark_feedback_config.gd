## 实验配置 full_mark_feedback：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FullMarkFeedbackConfig

const VALUE_NONE: int = 0
const VALUE_FULL_MARK_WITH_TEXT: int = 1
const VALUE_FULL_MARK_ANIM_ONLY: int = 2
const VALUE_UNIT_CLEAR_WITH_TEXT: int = 3
const VALUE_UNIT_CLEAR_NO_TEXT: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "full_mark_feedback"
	default_value = VALUE_NONE


func has_full_mark_feedback() -> bool:
	return int(value()) != VALUE_NONE


func has_full_mark_text() -> bool:
	var v: int = int(value())
	return (
		v == VALUE_FULL_MARK_WITH_TEXT
		or v == VALUE_UNIT_CLEAR_WITH_TEXT
		or v == VALUE_UNIT_CLEAR_NO_TEXT
	)


func has_unit_clear_feedback() -> bool:
	var v: int = int(value())
	return v == VALUE_UNIT_CLEAR_WITH_TEXT or v == VALUE_UNIT_CLEAR_NO_TEXT


func has_unit_clear_text() -> bool:
	return int(value()) == VALUE_UNIT_CLEAR_WITH_TEXT
