## 推荐关卡缓存协调器；记录关卡历史、消费队列、在队列不足时异步预取，并保存 rec_state.cfg。
## 本地排队中的关卡仍可继续使用；请求失败不会把原有队列清空。

extends Node

const SAVE_PATH := "user://save_store/rec_state.cfg"

const PREFETCH_THRESHOLD: int = 10

const MIN_PREFETCH_LEVEL_V2: int = 20

var _history: RecHistoryStore
var _queue: RecLevelQueue
var _store: SaveStore
var _fetching: bool = false

var _invalid_reported_batches: Dictionary = {}


func _ready() -> void:
	_history = RecHistoryStore.new()
	_queue = RecLevelQueue.new()
	_store = SaveStore.new(GameState.SAVE_PASSWORD, GameState.SAVE_DIR, false, SAVE_PATH)
	_load()
	print(
		(
			"[AlgoLevel] _ready: 从盘加载完毕, queue=%d history=%d"
			% [_queue.remaining(), _history.get_history().size()]
		)
	)
	SessionManager.session_changed.connect(_on_session_changed)

	ABTestManager.values_reloaded.connect(_on_ab_values_reloaded)

	AuthManager.session_ready.connect(_on_auth_session_ready)
	AuthManager.account_switched.connect(_on_auth_account_switched)


func _on_ab_values_reloaded(_timing: String, keys: Array[String]) -> void:
	if not keys.has(ABTestManager.normal_level.key):
		return
	print("[AlgoLevel] AB 真值落定(normal_level), 补触发冷启动预取")
	_try_prefetch()


func _on_auth_session_ready(_user_profile: AccountProfile) -> void:
	print("[AlgoLevel] auth 会话就绪, 补触发预取")
	_try_prefetch()


func _on_auth_account_switched(_user_profile: AccountProfile, _is_new_user: bool) -> void:
	print("[AlgoLevel] auth 换号完成, 补触发预取")
	_try_prefetch()


## 记录本局用于推荐的结果与会话顺序，并持久化，供下一次推荐请求使用。
func record_level_history(params: Dictionary) -> void:
	print(
		(
			"[AlgoLevel] record_level_history: progress=%s result=%s level=%d"
			% [
				str(params.get("progress_state", "")),
				str(params.get("result", "")),
				int(params.get("level", 0)),
			]
		)
	)
	_history.record(params)
	_save()
	_try_prefetch()


func mark_delivered(qid: String) -> void:
	_queue.mark_delivered(qid)
	_save()


## 消费当前队首并保存游标，再延迟检查是否需要预取；与只读 peek_queue 区分。
func dequeue() -> Dictionary:
	var entry: Dictionary = _queue.dequeue()
	if not entry.is_empty():
		print("[AlgoLevel] dequeue: 取出一道, 剩余=%d" % _queue.remaining())
		_save()
	else:
		print("[AlgoLevel] dequeue: 队列空")
	call_deferred("_try_prefetch")
	return entry


func queue_remaining() -> int:
	return _queue.remaining()


func is_queue_available() -> bool:
	return not _queue.is_empty()


func peek_queue() -> Dictionary:
	return _queue.peek()


func peek_queue_at(offset: int) -> Dictionary:
	return _queue.peek_at(offset)


func queue_state_signature() -> String:
	return _queue.state_signature()


func get_current_request_id() -> String:
	return _queue.get_request_id()


func force_prefetch() -> void:
	_prefetch()


func clear_queue() -> void:
	_queue.clear()
	_save()


func reset_all() -> void:
	_queue.clear()
	_history.load_from([], 0)
	_store.remove()
	print("[AlgoLevel] reset_all: 队列+历史已清空, rec_state.cfg 已删除")


func get_history_count() -> int:
	return _history.get_history().size()


## 检查实验开关、关卡门槛、剩余队列和在途标记，只在需要时启动一次请求。
func _try_prefetch() -> void:
	if not ABTestManager.normal_level.is_server_rec_active():
		print("[AlgoLevel] _try_prefetch: 跳过(非推荐组, D6 对照组零网络)")
		return

	var current_level: int = GameState.get_current_level()
	if current_level < MIN_PREFETCH_LEVEL_V2:
		print(
			(
				"[AlgoLevel] _try_prefetch: 跳过(推荐组前20关零网络, lv=%d < %d)"
				% [current_level, MIN_PREFETCH_LEVEL_V2]
			)
		)
		return

	if _fetching:
		print("[AlgoLevel] _try_prefetch: 跳过(已有请求在飞)")
		return

	if _queue.remaining() > PREFETCH_THRESHOLD:
		return

	print(
		"[AlgoLevel] _try_prefetch: queue=%d <= %d, 触发预取" % [_queue.remaining(), PREFETCH_THRESHOLD]
	)
	_prefetch()


## 携带历史与仍有效的队首分配请求后续关卡；失败保留旧队列，成功后合并并保存新的推荐上下文。
func _prefetch() -> void:
	if _fetching:
		return

	if ApiConfig.device_id().is_empty() and not OS.has_feature("editor"):
		print("[AlgoLevel] _prefetch: auth 未就绪(device-id 空)，跳过本次预取")
		return
	var _hist: Array[Dictionary] = _history.get_history()
	print(
		(
			"[AlgoLevel] _prefetch: 开始请求 (history=%d, last=%s)"
			% [_hist.size(), JSON.stringify(_hist.back()) if not _hist.is_empty() else "empty"]
		)
	)

	var retained_head: Dictionary = _validate_current_head()
	var retained: Array = _queue.build_retained_assignments(str(retained_head.get("qid", "")))
	_fetching = true
	var ab_test_group_id: int = int(ABTestManager.normal_level.value())
	var result: Dictionary = await RecApi.request_next(
		self,
		_history.get_history(),
		_queue.get_extra_values(),
		ab_test_group_id,
		"treatment",
		ABTestManager.normal_level.get_rec_model_name(),
		retained
	)
	_fetching = false

	if not bool(result.get("ok", false)):
		print("[AlgoLevel] 预取失败: %s" % str(result.get("fallback_reason", "")))
		return

	var levels: Array = result.get("levels", [])
	if levels.is_empty():
		print(
			(
				"[AlgoLevel] 预取返回 0 道 (status=%s reason=%s)"
				% [str(result.get("dispatch_status", "")), str(result.get("fallback_reason", ""))]
			)
		)
		return

	var validated_head: Dictionary = _validate_current_head(true)
	_queue.enqueue(
		levels, result.get("extra_values", {}), str(result.get("request_id", "")), validated_head
	)
	_save()
	print(
		(
			"[AlgoLevel] 预取成功: +%d 道, 保留旧队首=%s, 队列=%d"
			% [levels.size(), "yes" if not validated_head.is_empty() else "no", _queue.remaining()]
		)
	)


func _save() -> void:
	var cfg := ConfigFile.new()
	var hist_data: Dictionary = _history.to_save_data()
	cfg.set_value("history", "records", hist_data.get("records", []))
	cfg.set_value("history", "session_pos", hist_data.get("session_pos", 0))
	var queue_data: Dictionary = _queue.to_save_data()
	cfg.set_value("queue", "levels", queue_data.get("levels", []))
	cfg.set_value("queue", "cursor", queue_data.get("cursor", 0))
	cfg.set_value("queue", "extra_values", queue_data.get("extra_values", {}))
	cfg.set_value("queue", "request_id", queue_data.get("request_id", ""))
	_store.save_config(cfg)


func _load() -> void:
	var cfg: ConfigFile = _store.load_config()
	if cfg == null:
		return
	_history.load_from(
		cfg.get_value("history", "records", []), int(cfg.get_value("history", "session_pos", 0))
	)
	(
		_queue
		. load_from(
			{
				"levels": cfg.get_value("queue", "levels", []),
				"cursor": int(cfg.get_value("queue", "cursor", 0)),
				"extra_values": cfg.get_value("queue", "extra_values", {}),
				"request_id": str(cfg.get_value("queue", "request_id", "")),
			}
		)
	)


func _on_session_changed(_new_session_id: String) -> void:
	_history.reset_session_position()


## 核对当前队首是否仍能交付；无效项不会作为保留分配继续传给服务器。
func _validate_current_head(report_invalid: bool = false) -> Dictionary:
	var raw: Dictionary = _queue.peek()
	if raw.is_empty():
		return {}
	var entry: Dictionary = ServerProvider.build_entry(raw)
	var lv: int = GameState.get_current_level()
	var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
	if not bool(validation.valid):
		if report_invalid:
			report_invalid_entry(entry, str(validation.reason))
		print("[AlgoLevel] 旧队首校验失败(FinalLevelValidator), 丢弃")
		return {}
	var dedup: Dictionary = PuzzleDeduplicator.inspect(validation.entry, lv)
	if bool(dedup.duplicate):
		print("[AlgoLevel] 旧队首撞重, 丢弃 qid=%s" % str(raw.get("qid", "")))
		return {}
	return raw


## 将发现的无效推荐项交给现有队列处理逻辑，避免反复命中同一条坏数据。
func report_invalid_entry(entry: Dictionary, reason: String) -> void:
	var request_id: String = str(entry.get("_rec_decision_id", ""))
	if request_id.is_empty():
		request_id = _queue.get_request_id()
	if _invalid_reported_batches.has(request_id):
		return
	if _invalid_reported_batches.size() >= 64:
		var reported_ids: Array = _invalid_reported_batches.keys()
		_invalid_reported_batches.erase(reported_ids[0])
	_invalid_reported_batches[request_id] = true
	var regions_value: Variant = entry.get("regionMap")
	var row_type: String = ""
	if regions_value is Array:
		var rows: Array = regions_value
		for row_value: Variant in rows:
			if not row_value is Array:
				row_type = type_string(typeof(row_value))
				break
	push_error(
		(
			"INVALID_REC_PUZZLE model=%s request_id=%s qid=%s reason=%s region_type=%s row_type=%s solution_type=%s size_type=%s"
			% [
				ABTestManager.normal_level.get_rec_model_name(),
				request_id,
				str(entry.get("_rec_qid", "")),
				reason,
				type_string(typeof(regions_value)),
				row_type,
				type_string(typeof(entry.get("solution"))),
				type_string(typeof(entry.get("size"))),
			]
		)
	)
