## 单次选择/结算的显式依赖。候选状态、实验值、随机源和推荐队列均在入口冻结。
## 策略不得访问真实 GameState、实时 AB 或出队网络队列；提交后副作用由调用者处理。
class_name DokuSelectionRuntime
extends RefCounted

var state: DokuSelectionState # 本次尝试的可变候选；失败时随 runtime 丢弃。
var normal_level: RefCounted # 使用冻结 normal_level 值的配置解释器，不重新查询 AB。
var single_region_num: RefCounted # 使用冻结单格区域实验值的配置解释器。
var rng: RandomNumberGenerator # 由请求种子初始化；构造 state 时注入同一个随机源对象。
var policy: Dictionary = {} # 选题规则快照；会随重试参数保存，保证重试和结算沿用交付规则。
var configs: Dictionary = {} # 配置名 → 只解释内存值的配置实例。
var effects: Array[Dictionary] = [] # 待提交后执行的请求描述；收集时不调用服务、不发信号。
var _queue: RecLevelQueue = RecLevelQueue.new() # 从推荐快照复制的本地队列；试选出队不会消耗真实队列。
var _queue_changed: bool = false # 只有本地队列发生消费/交付标记时，才把它合入导出候选。
var recommendation_generation: String = "" # 入口提供的推荐快照代次标识；不是 ContentContext 的内容代次。
var app_version: String = "" # 入口冻结的版本名，写入最近出题记录。
var assist_user: bool = false # 入口确认的辅助用户身份，策略内不发起身份查询。
var now_unix: int = 0 # 入口冻结的 Unix 时间，单位秒。
var today: String = "" # 入口冻结的日期字符串；本次操作跨越午夜也使用同一日期。


## 复制候选、规则和推荐队列，并用同一个随机源连接状态与策略。
## context 可显式提供推荐快照；未提供时从候选的 features.recommendation.queue 读取。
func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	policy = (context.get("policy", {}) as Dictionary).duplicate(true)
	rng = RandomNumberGenerator.new()
	rng.seed = int(context.get("seed", 0))
	now_unix = int(context.get("now_unix", 0))
	today = str(context.get("today", ""))
	app_version = str(context.get("app_version", ""))
	assist_user = bool(context.get("assist_user", false))
	var state_context: Dictionary = context.duplicate()
	# 复用随机源对象，让状态内部洗牌也遵循同一请求种子；不能在中途重新随机播种。
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


## 判断冻结队列是否还有可尝试条目；不查询网络或当前全局队列。
func has_recommendation() -> bool:
	return not _queue.is_empty()


## 从本地队列取走一项并返回深拷贝；空队列返回空字典，不标记队列变化。
func take_recommendation() -> Dictionary:
	var value: Dictionary = _queue.dequeue()
	_queue_changed = _queue_changed or not value.is_empty()
	return value.duplicate(true)


## 把非空推荐 ID 记入本地已交付集合；实际队列状态要等候选提交才生效。
func mark_recommendation_delivered(qid: String) -> void:
	if not qid.is_empty():
		_queue.mark_delivered(qid)
		_queue_changed = true


## 暂存辅助用户身份刷新请求；由成功提交后的 effects 发布阶段调用服务。
func request_assist_refresh() -> void:
	effects.append({"kind": "refresh_assist_user"})


## 合并策略候选与本地推荐队列，返回可提交的新快照；此处不落盘。
func export_candidate() -> Dictionary:
	var candidate: Dictionary = state.export_candidate()
	# state 不拥有出队过程，因此必须由 runtime 补回队列结果，避免导出旧快照覆盖消费记录。
	if _queue_changed:
		var features: Dictionary = candidate.get("features", {})
		var recommendation: Dictionary = features.get("recommendation", {})
		recommendation["queue"] = _queue.to_save_data().duplicate(true)
		features["recommendation"] = recommendation
		candidate["features"] = features
	return candidate


## 为推荐策略提供兼容的队列可用性接口，检查的仍是本次快照。
func is_queue_available() -> bool:
	return has_recommendation()


## 兼容推荐策略的出队入口；委托本地消费逻辑，同时保留队列变化标记。
func dequeue() -> Dictionary:
	return take_recommendation()


## 返回本地队列剩余条目数，不包含已从本次候选取走的条目。
func queue_remaining() -> int:
	return _queue.remaining()


## 返回本地队首的深拷贝；查看不会推进队列游标。
func peek_queue() -> Dictionary:
	return _queue.peek().duplicate(true)


## 按相对偏移查看本地队列条目的深拷贝，不消耗推荐。
func peek_queue_at(offset: int) -> Dictionary:
	return _queue.peek_at(offset).duplicate(true)


## 返回推荐请求 ID 与消费游标组成的签名；用于辨别出队进展，不涵盖所有队列载荷变化。
func queue_state_signature() -> String:
	return _queue.state_signature()


## 兼容策略的交付标记入口；推荐 ID 只写入本次 runtime 的队列。
func mark_delivered(qid: String) -> void:
	mark_recommendation_delivered(qid)


## 复制无效推荐及原因，排入待发布事件；试选失败时可整体丢弃这些事件。
func report_invalid_entry(entry: Dictionary, reason: String) -> void:
	effects.append({"kind": "invalid_recommendation", "entry": entry.duplicate(true), "reason": reason})


## 深拷贝并合并 runtime 请求与候选状态事件；调用方成功提交后再发布。
func export_effects() -> Array:
	var result: Array = effects.duplicate(true)
	result.append_array(state.events.duplicate(true))
	return result


## 按名称返回冻结配置解释器；入口没有提供该配置时返回 null。
func config(name: String) -> RefCounted:
	return configs.get(name, null)
