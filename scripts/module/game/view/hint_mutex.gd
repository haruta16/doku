extends RefCounted
class_name HintMutex

var _active_id: String = ""


func try_acquire(hint_id: String) -> bool:
	if _active_id != "":
		print("[HintMutex] '%s' blocked by active '%s'" % [hint_id, _active_id])
		return false
	_active_id = hint_id
	return true


func release(hint_id: String) -> void:
	if _active_id == hint_id:
		_active_id = ""


func is_active() -> bool:
	return _active_id != ""


func get_active_id() -> String:
	return _active_id
