## 推荐结果队列；用游标区分已消费和待消费项，并保存请求上下文及服务器分配状态。

class_name RecLevelQueue
extends RefCounted


class RecPlayState:
	const PLAYED: int = 1

	const PENDING: int = 2

	const DISCARDED: int = 3


var _levels: Array[Dictionary] = []
var _cursor: int = 0
var _extra_values: Dictionary = {}
var _request_id: String = ""

var _delivered_qids: Dictionary = {}


## 接纳一批推荐结果与请求上下文，并按保留队首规则建立新的队列游标。
func enqueue(
	levels: Array, extra_values: Dictionary, request_id: String, validated_head: Dictionary = {}
) -> void:
	var keep: Array[Dictionary] = []
	if not validated_head.is_empty():
		keep.append(validated_head)
	_levels = keep
	_cursor = 0
	for i: int in range(levels.size()):
		var lv: Variant = levels[i]
		if lv is Dictionary:
			var d: Dictionary = lv as Dictionary
			d["_slot_index"] = i
			d["_request_id"] = request_id
			_levels.append(d)
	_extra_values = extra_values
	_request_id = request_id

	_delivered_qids.clear()


## 记录题目已交付的状态；服务器分配反馈据此区分真正出题与仍在缓存的候选。
func mark_delivered(qid: String) -> void:
	if qid.is_empty():
		return
	_delivered_qids[qid] = true


## 为下一次推荐请求生成已玩、待玩或丢弃的分配信息，减少服务端重复分配。
func build_retained_assignments(retained_head_qid: String) -> Array:
	var out: Array = []
	for i: int in _levels.size():
		var qid: String = str(_levels[i].get("qid", ""))
		if qid.is_empty():
			continue
		var play_state: int
		if i < _cursor:
			play_state = RecPlayState.PLAYED if _delivered_qids.has(qid) else RecPlayState.DISCARDED
		elif not retained_head_qid.is_empty() and qid == retained_head_qid:
			play_state = RecPlayState.PENDING
		else:
			play_state = RecPlayState.DISCARDED
		out.append({"qid": qid, "play_state": play_state})
	return out


## 只查看队首，不移动消费游标；真正开始消费使用 dequeue。
func peek() -> Dictionary:
	if _cursor >= _levels.size():
		return {}
	return _levels[_cursor]


func peek_at(offset: int) -> Dictionary:
	var i: int = _cursor + offset
	if offset < 0 or i >= _levels.size():
		return {}
	return _levels[i]


func state_signature() -> String:
	return "%s#%d" % [_request_id, _cursor]


## 返回当前项并前移游标；队列耗尽时返回空字典，由上层决定回退选题。
func dequeue() -> Dictionary:
	if _cursor >= _levels.size():
		return {}
	var entry: Dictionary = _levels[_cursor]
	_cursor += 1
	return entry


func remaining() -> int:
	return maxi(0, _levels.size() - _cursor)


func is_empty() -> bool:
	return remaining() == 0


func get_extra_values() -> Dictionary:
	return _extra_values


func get_request_id() -> String:
	return _request_id


func clear() -> void:
	_levels.clear()
	_cursor = 0
	_extra_values = {}
	_request_id = ""
	_delivered_qids.clear()


func load_from(data: Dictionary) -> void:
	_levels.clear()
	var raw_levels: Variant = data.get("levels", [])
	if raw_levels is Array:
		for lv: Variant in raw_levels:
			if lv is Dictionary:
				_levels.append(lv as Dictionary)
	_cursor = int(data.get("cursor", 0))
	var ev: Variant = data.get("extra_values", {})
	_extra_values = ev if ev is Dictionary else {}
	_request_id = str(data.get("request_id", ""))

	var delivered: Variant = data.get("delivered_qids", {})
	_delivered_qids = delivered if delivered is Dictionary else {}

	for d: Dictionary in _levels:
		if not d.has("_request_id"):
			d["_request_id"] = _request_id


func to_save_data() -> Dictionary:
	return {
		"levels": _levels,
		"cursor": _cursor,
		"extra_values": _extra_values,
		"request_id": _request_id,
		"delivered_qids": _delivered_qids,
	}
