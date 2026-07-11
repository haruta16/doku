extends Node

signal count_changed(dot_id: String, count: int)

var _counts: Dictionary = {}


func set_count(dot_id: String, count: int) -> void:
	if dot_id == "":
		return
	var old: int = _counts.get(dot_id, 0)
	if old == count:
		return
	_counts[dot_id] = count
	count_changed.emit(dot_id, count)


func get_count(dot_id: String) -> int:
	return _counts.get(dot_id, 0)
