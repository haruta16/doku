extends Node

signal anchor_changed(y: float)

const UNSET: float = -1.0

var _y: float = UNSET


func set_settingbtn_y(y: float) -> void:
	if y < 0.0 or is_equal_approx(_y, y):
		return
	_y = y
	anchor_changed.emit(_y)


func get_settingbtn_y() -> float:
	return _y


func has_value() -> bool:
	return _y >= 0.0
