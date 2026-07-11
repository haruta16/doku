extends AbConfigBase
class_name DraftModeConfig

const VALUE_CONTROL: int = 0
const VALUE_APPLY_INPLACE: int = 1
const VALUE_APPLY_INDEPENDENT: int = 2
const VALUE_AUTO_WIN: int = 3
const VALUE_AUTO_WIN_PERSIST: int = 4


func _init() -> void:
	key = "draft_mode"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START_NORMAL_21


func is_enabled() -> bool:
	return value() != VALUE_CONTROL


func has_apply_button() -> bool:
	var v: int = value()
	return v == VALUE_APPLY_INPLACE or v == VALUE_APPLY_INDEPENDENT


func has_independent_apply_button() -> bool:
	return value() == VALUE_APPLY_INDEPENDENT


func auto_win_on_complete() -> bool:
	var v: int = value()
	return v == VALUE_AUTO_WIN or v == VALUE_AUTO_WIN_PERSIST


func keep_marks_on_manual_exit() -> bool:
	return value() == VALUE_AUTO_WIN_PERSIST


func persist_draft_marks() -> bool:
	return value() == VALUE_AUTO_WIN_PERSIST
