## 单次选题轨迹：保存策略身份、顺序事件与最终状态，导出时深拷贝防止外部修改。
class_name LevelSelectionTrace
extends RefCounted

var _strategy_id: StringName
var _strategy_version: int
var _level_num: int
var _status: StringName = &"selecting"
var _events: Array[Dictionary] = []
var _summary: Dictionary = {}


## 记录本次选题的策略标识、版本和关号。
func _init(strategy_id: StringName, strategy_version: int, level_num: int) -> void:
	_strategy_id = strategy_id
	_strategy_version = strategy_version
	_level_num = level_num


## 深拷贝事件数据，附加类型与递增序号。
func add_event(kind: StringName, data: Dictionary = {}) -> void:
	var event: Dictionary = data.duplicate(true)
	event["kind"] = String(kind)
	event["seq"] = _events.size()
	_events.append(event)


## 更新最终状态并深拷贝摘要数据。
func set_status(value: StringName, data: Dictionary = {}) -> void:
	_status = value
	_summary = data.duplicate(true)


## 导出策略、关号、状态、事件和摘要的独立快照。
func to_dict() -> Dictionary:
	return {
		"strategy_id": String(_strategy_id),
		"strategy_version": _strategy_version,
		"level_num": _level_num,
		"status": String(_status),
		"events": _events.duplicate(true),
		"summary": _summary.duplicate(true),
	}
