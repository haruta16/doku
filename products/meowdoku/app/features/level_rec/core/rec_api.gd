## 远端推荐关卡接口的协议层；封装历史、保留的队列分配、设备/用户标识与请求编号。

class_name RecApi
extends RefCounted

const KEY_RETAINED_ASSIGNMENTS: String = "rtained_assignments"


## 组装推荐请求并补齐历史间隔与用户标识；协议字段名须与服务端保持一致，包括现有拼写。
static func request_next(
	host_node: Node,
	history: Array[Dictionary],
	extra_values: Dictionary,
	ab_test_group_id: int,
	ab_group: String = "treatment",
	model_name: String = NormalLevelConfig.REC_MODEL_ACTIVE,
	retained_assignments: Array = []
) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var request_id: String = _gen_request_id(now)

	var filled_history: Array = _fill_interval(history, now)
	var body: Dictionary = {
		"request_id": request_id,
		"user_id": _user_id(),
		"decision_size": 0,
		"ab_group": ab_group,
		"ab_test_group_id": str(ab_test_group_id),
		"next_has_pre_cat": false,
		"model_name": model_name,
		"decision_ts_s": now,
		"recent_history_normalized_raw_facts": filled_history,
		"extra_values": extra_values,
	}

	if not retained_assignments.is_empty():
		body[KEY_RETAINED_ASSIGNMENTS] = retained_assignments

	var log_body: Dictionary = body.duplicate()
	log_body["recent_history_normalized_raw_facts"] = "<%d 条已省略>" % filled_history.size()
	print("[AlgoLevel] 请求 body: %s" % JSON.stringify(log_body, "", false))

	var http := RecHttp.new()
	host_node.add_child(http)
	var resp: Dictionary = await http.post(ApiConfig.PATH_REC_QUESTION_NEXT, body)
	http.queue_free()

	if not bool(resp.get("ok", false)):
		return {
			"ok": false,
			"levels": [],
			"extra_values": {},
			"dispatch_status": "",
			"fallback_reason": resp.get("message", ""),
			"request_id": request_id
		}

	var code: int = int(resp.get("code", -1))
	if code != ApiConfig.CODE_OK:
		return {
			"ok": false,
			"levels": [],
			"extra_values": {},
			"dispatch_status": "",
			"fallback_reason": "code=%d %s" % [code, resp.get("message", "")],
			"request_id": request_id
		}

	var data: Dictionary = resp.get("data", {})
	var levels_raw: Variant = data.get("levels", [])
	var levels: Array = levels_raw if levels_raw is Array else []
	var ev_raw: Variant = data.get("extra_values", {})
	var ev: Dictionary = ev_raw if ev_raw is Dictionary else {}

	return {
		"ok": true,
		"levels": levels,
		"extra_values": ev,
		"dispatch_status": str(data.get("dispatch_status", "")),
		"fallback_reason": str(data.get("fallback_reason", "")),
		"request_id": request_id,
	}


static func _gen_request_id(now: int) -> String:
	return "rec-%d-%d" % [now, randi()]


static func _user_id() -> String:
	var luid: String = ApiConfig.luid()
	if not luid.is_empty():
		return luid
	var lid: String = UniKitManager.get_learnings_id()
	if not lid.is_empty():
		return lid
	return ""


static func _fill_interval(history: Array, now: int) -> Array:
	var out: Array = []
	for record: Variant in history:
		if not (record is Dictionary):
			continue
		var r: Dictionary = (record as Dictionary).duplicate()
		var end_ts: int = int(r.get("end_ts_s", 0))
		r["interval_seconds"] = float(now - end_ts) if end_ts > 0 else 0.0
		out.append(r)
	return out
