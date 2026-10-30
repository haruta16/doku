## 单次选择/结算的显式依赖。候选状态、实验值、随机源和推荐队列均在入口冻结。
## 策略不得访问真实 GameState、实时 AB 或出队网络队列；提交后副作用由调用者处理。
class_name DokuSelectionRuntime
extends RefCounted

var state: DokuSelectionState
var normal_level: RefCounted
var single_region_num: RefCounted
var rng: RandomNumberGenerator
var policy: Dictionary = {}
var configs: Dictionary = {}
var effects: Array[Dictionary] = []
var _queue: RecLevelQueue = RecLevelQueue.new()
var _queue_changed: bool = false
var recommendation_generation: String = ""
var app_version: String = ""
var assist_user: bool = false
var now_unix: int = 0
var today: String = ""


func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	policy = (context.get("policy", {}) as Dictionary).duplicate(true)
	rng = RandomNumberGenerator.new()
	rng.seed = int(context.get("seed", 0))
	now_unix = int(context.get("now_unix", 0))
	today = str(context.get("today", ""))
	app_version = str(context.get("app_version", ""))
	assist_user = bool(context.get("assist_user", false))
	var state_context: Dictionary = context.duplicate()
	state_context["rng"] = rng
	state = DokuSelectionState.new(candidate, state_context)
	var queue_snapshot: Dictionary = context.get("recommendations", candidate.get("features", {}).get("recommendation", {}).get("queue", {}))
	_queue.load_from(queue_snapshot.duplicate(true))
	recommendation_generation = str(context.get("recommendation_generation", ""))
	for name: String in context.get("config_scripts", {}):
		configs[name] = frozen_config(context.config_scripts[name], policy.get(name, 0))
	if context.get("normal_level_config") is Script:
		normal_level = frozen_config(context.normal_level_config, policy.get("normal_level", 0))
	if context.get("single_region_config") is Script:
		single_region_num = frozen_config(context.single_region_config, policy.get("single_region_num", 0))


## 只构造原配置的纯解释器，不调用 init_default/load_value，不读取调试文件或远端。
static func frozen_config(script: Script, value: Variant) -> RefCounted:
	var config: RefCounted = script.new()
	config.set("default_value", value)
	config.set("_value", value)
	config.set("_value_loaded", true)
	# peek_value 也先返回该内存值，避免纯解释器回到远端或存档。
	config.set("_has_debug_override", true)
	config.set("_debug_override", value)
	return config


func has_recommendation() -> bool:
	return not _queue.is_empty()


func take_recommendation() -> Dictionary:
	var value: Dictionary = _queue.dequeue()
	_queue_changed = _queue_changed or not value.is_empty()
	return value.duplicate(true)


func mark_recommendation_delivered(qid: String) -> void:
	if not qid.is_empty():
		_queue.mark_delivered(qid)
		_queue_changed = true


func request_assist_refresh() -> void:
	effects.append({"kind": "refresh_assist_user"})


func export_candidate() -> Dictionary:
	var candidate: Dictionary = state.export_candidate()
	if _queue_changed:
		var features: Dictionary = candidate.get("features", {})
		var recommendation: Dictionary = features.get("recommendation", {})
		recommendation["queue"] = _queue.to_save_data().duplicate(true)
		features["recommendation"] = recommendation
		candidate["features"] = features
	return candidate


func is_queue_available() -> bool:
	return has_recommendation()


func dequeue() -> Dictionary:
	return take_recommendation()


func queue_remaining() -> int:
	return _queue.remaining()


func peek_queue() -> Dictionary:
	return _queue.peek().duplicate(true)


func peek_queue_at(offset: int) -> Dictionary:
	return _queue.peek_at(offset).duplicate(true)


func queue_state_signature() -> String:
	return _queue.state_signature()


func mark_delivered(qid: String) -> void:
	mark_recommendation_delivered(qid)


func report_invalid_entry(entry: Dictionary, reason: String) -> void:
	effects.append({"kind": "invalid_recommendation", "entry": entry.duplicate(true), "reason": reason})


func export_effects() -> Array:
	var result: Array = effects.duplicate(true)
	result.append_array(state.events.duplicate(true))
	return result


func config(name: String) -> RefCounted:
	return configs.get(name, null)
