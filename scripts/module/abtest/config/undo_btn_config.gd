extends AbConfigBase
class_name UndoBtnConfig

const VALUE_CONTROL: int = 0
const VALUE_UNDO_PAID: int = 1
const VALUE_HIGHLIGHT_PAID: int = 2
const VALUE_UNDO_FREE: int = 3
const VALUE_HIGHLIGHT_FREE: int = 4


func _init() -> void:
	key = "undo_btn"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
	return value() != VALUE_CONTROL


func is_undo_mode() -> bool:
	var v: int = value()
	return v == VALUE_UNDO_PAID or v == VALUE_UNDO_FREE


func is_highlight_only() -> bool:
	var v: int = value()
	return v == VALUE_HIGHLIGHT_PAID or v == VALUE_HIGHLIGHT_FREE


func is_free() -> bool:
	var v: int = value()
	return v == VALUE_UNDO_FREE or v == VALUE_HIGHLIGHT_FREE


func get_highlight_duration(_cell_count: int) -> float:
	return 10.0
