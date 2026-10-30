## 推荐系统的本地关卡历史；只保留最近一段记录，并单独计算当前会话内的顺序位置。

class_name RecHistoryStore
extends RefCounted

const MAX_RECORDS: int = 100

var _records: Array[Dictionary] = []
var _session_position: int = 0


## 追加最近一局历史并裁剪到容量上限，同时推进当前会话顺序。
func record(params: Dictionary) -> void:
	_session_position += 1
	params["session_position"] = _session_position
	_records.append(params)
	if _records.size() > MAX_RECORDS:
		_records.pop_front()


func get_history() -> Array[Dictionary]:
	return _records


func get_session_position() -> int:
	return _session_position


## 新会话只重置会话内位置；跨会话保留的历史仍可用于推荐。
func reset_session_position() -> void:
	_session_position = 0


func load_from(records: Array, session_pos: int) -> void:
	_records.clear()
	for r: Variant in records:
		if r is Dictionary:
			_records.append(r as Dictionary)
	if _records.size() > MAX_RECORDS:
		_records = _records.slice(_records.size() - MAX_RECORDS)
	_session_position = session_pos


func to_save_data() -> Dictionary:
	return {
		"records": _records,
		"session_pos": _session_position,
	}
