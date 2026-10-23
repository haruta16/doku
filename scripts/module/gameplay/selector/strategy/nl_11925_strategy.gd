## 普通关卡策略 normal_level_11925：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL11925Strategy
extends LevelSelectionStrategy

const HARD_MIN_GAP: int = 6

const MIN_REC_LEVEL: int = 21

var _ctx: LevelSelectContext
var _fallback_reason: String

var _base: NL12100Strategy

var _local_delivery_pending: bool = false

var _preview: Dictionary = {}

var _special_rank_cache: Dictionary = {}

var _hard_log_seen: Dictionary = {}


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_11925"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func is_hard_level(level_num: int) -> bool:
	if level_num < MIN_REC_LEVEL:
		var below_gate: bool = super.is_hard_level(level_num)
		_log_hard(level_num, "前20关·本地逢十规则", "lv<%d" % MIN_REC_LEVEL, below_gate, "")
		return below_gate

	var cached: Dictionary = GameState.get_retry_puzzle(level_num)
	if not cached.is_empty():
		var cached_rank: int = int(cached.get("bank_rank", 0))
		var result_cached: bool = _apply_hard_gap(level_num, cached_rank >= 4)
		_log_hard(level_num, "已取题·锁题缓存", "bank_rank=%d" % cached_rank, result_cached, "")
		return result_cached

	var result: bool = _apply_hard_gap(level_num, _base_hard_level(level_num))
	_log_hard(
		level_num,
		_preview_branch_name(level_num),
		_preview_detail(level_num),
		result,
		_legacy_verdict_note(level_num, result)
	)
	return result


func _log_hard(level_num: int, branch: String, detail: String, result: bool, note: String) -> void:
	if OS.has_feature("rel"):
		return
	var sig: String = "%s|%s|%s|%s" % [branch, detail, str(result), note]
	if str(_hard_log_seen.get(level_num, "")) == sig:
		return
	_hard_log_seen[level_num] = sig
	print(
		(
			"[AlgoLevel.11925.hard] lv=%d Hard=%s | %s | %s | last_hard=%d%s"
			% [level_num, str(result), branch, detail, GameState.get_last_hard_level(), note]
		)
	)


func _preview_branch_name(level_num: int) -> String:
	if SpecialProvider.SPECIAL_LEVELS.has(level_num):
		return "未取题·特殊关固定题"
	if not LevelRecManager.is_queue_available():
		return "未取题·队列空→本地逢十"
	return "未取题·预选交付题"


func _preview_detail(level_num: int) -> String:
	if SpecialProvider.SPECIAL_LEVELS.has(level_num):
		var spec: Dictionary = SpecialProvider.SPECIAL_LEVELS[level_num]
		return (
			"src=%s idx=%d rank=%d"
			% [
				str(spec.get("source", "")),
				int(spec.get("index", 0)),
				_special_level_rank(level_num)
			]
		)
	if not LevelRecManager.is_queue_available():
		return "lv%%10==%d" % (level_num % 10)
	var pick: Dictionary = _preview_delivery(level_num)
	if pick.is_empty():
		return "队列 %d 道全被跳过→按逢十判" % LevelRecManager.queue_remaining()
	return (
		"skip=%d rank=%d queue=%d"
		% [int(pick.get("skip", -1)), int(pick.get("rank", 0)), LevelRecManager.queue_remaining()]
	)


func _legacy_verdict_note(level_num: int, actual: bool) -> String:
	if OS.has_feature("rel"):
		return ""
	if not LevelRecManager.is_queue_available():
		return ""
	var raw: Dictionary = LevelRecManager.peek_queue()
	if raw.is_empty():
		return ""
	var rank_value: Variant = raw.get("rank", 0)
	if not FinalLevelValidator.is_integer_value(rank_value):
		return ""
	var legacy_rank: int = int(rank_value)
	var legacy: bool = _apply_hard_gap(level_num, legacy_rank >= 4)
	if legacy == actual:
		return ""
	return "  ⚠️ 旧实现(peek队首 raw.rank=%d)会判 Hard=%s ← 这就是不一致的来源" % [legacy_rank, str(legacy)]


func _apply_hard_gap(level_num: int, base_hard: bool) -> bool:
	if not base_hard:
		return false
	var last_hard: int = GameState.get_last_hard_level()
	if last_hard > 0 and level_num > last_hard and level_num - last_hard < HARD_MIN_GAP:
		return false
	return true


func _base_hard_level(level_num: int) -> bool:
	if SpecialProvider.SPECIAL_LEVELS.has(level_num):
		return _special_level_rank(level_num) >= 4

	var pick: Dictionary = _preview_delivery(level_num)
	if pick.is_empty():
		return level_num >= 21 and level_num % 10 == 0
	return int(pick.get("rank", 0)) >= 4


func _special_level_rank(level_num: int) -> int:
	if _special_rank_cache.has(level_num):
		return int(_special_rank_cache[level_num])
	var ctx := LevelSelectContext.new()
	ctx.level_num = level_num
	var entry: Dictionary = SpecialProvider.new().next_entry(ctx)
	var rank: int = int(entry.get("_bank_rank", 0))
	_special_rank_cache[level_num] = rank
	return rank


func _preview_delivery(level_num: int) -> Dictionary:
	if not LevelRecManager.is_queue_available():
		return {}
	var sig: String = LevelRecManager.queue_state_signature()
	var cached: Dictionary = _preview.get(level_num, {})
	if str(cached.get("sig", "")) == sig:
		return {} if int(cached.get("skip", -1)) < 0 else cached
	for off: int in range(LevelRecManager.queue_remaining()):
		var raw: Dictionary = LevelRecManager.peek_queue_at(off)
		if raw.is_empty():
			break

		var entry: Dictionary = ServerProvider.build_entry(raw)
		var validation: Dictionary = FinalLevelValidator.validate(entry, level_num)
		if not bool(validation.valid):
			continue
		var checked: Dictionary = validation.entry
		if bool(PuzzleDeduplicator.inspect(checked, level_num).duplicate):
			continue
		var pick: Dictionary = {
			"skip": off,
			"rank": int(checked.get("_bank_rank", 0)),
			"sig": sig,
		}
		_preview[level_num] = pick
		return pick

	_preview[level_num] = {"skip": -1, "rank": 0, "sig": sig}
	return {}


func select(request: LevelSelectRequest) -> Dictionary:
	var lv: int = request.level_num
	_local_delivery_pending = false

	if SpecialProvider.SPECIAL_LEVELS.has(lv):
		_ctx = LevelSelectContext.new()
		_ctx.level_num = lv
		_ctx.rank_override = request.rank_override
		_ctx.sz = SizeModifier.get_size(lv)
		if _ctx.sz == 0:
			return {"failed_reason": "no_size"}
		HardLevelModifier.apply(_ctx)
		if request.rank_override > 0:
			StrategyModifier.apply_override(_ctx)
		elif not _ctx.is_hard:
			StrategyModifier.apply_normal(_ctx)
		DailyFirstEasyModifier.apply(_ctx)
		TierFallbackModifier.apply(_ctx)
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _mark_if_hard(lv, _deliver_special(sp_entry, lv))

	if lv < MIN_REC_LEVEL:
		print("[AlgoLevel.11925] lv=%d < %d, 前20关强制本地兜底(12100出题)" % [lv, MIN_REC_LEVEL])
		_fallback_reason = "below_min_level"
		return _mark_if_hard(lv, _local_fallback(request))

	if request.rank_override > 0:
		print("[AlgoLevel.11925] rank_override=%d, 退化本地兜底" % request.rank_override)
		_fallback_reason = "rank_override"
		return _mark_if_hard(lv, _local_fallback(request))

	if GameState.is_daily_first_easy_available():
		print("[AlgoLevel.11925] dfld 可用, 退化本地兜底")
		_fallback_reason = "daily_first_easy"
		return _mark_if_hard(lv, _local_fallback(request))

	_fallback_reason = ""
	if ServerProvider.new().is_available(null):
		print("[AlgoLevel.11925] 推荐路径: queue=%d, 尝试取题..." % LevelRecManager.queue_remaining())
		var result: Dictionary = _try_server(lv)
		if not result.is_empty():
			var e: Dictionary = result.get("entry", {})
			print(
				(
					"[AlgoLevel.11925] ✓ 推荐题交付: qid=%s size=%d rank=%d queue_left=%d"
					% [
						str(e.get("_rec_qid", "")),
						int(e.get("size", 0)),
						int(e.get("_bank_rank", 0)),
						LevelRecManager.queue_remaining()
					]
				)
			)
			return _mark_if_hard(lv, result)
		print("[AlgoLevel.11925] 推荐路径取空, 落入本地兜底")
		_fallback_reason = "queue_exhausted"

	else:
		print(
			(
				"[AlgoLevel.11925] ServerProvider 不可用: queue=%d (队列空，预取可能未完成)"
				% LevelRecManager.queue_remaining()
			)
		)
		_fallback_reason = "queue_empty"

	print("[AlgoLevel.11925] 本地兜底路径: lv=%d fallback_reason=%s" % [lv, _fallback_reason])
	return _mark_if_hard(lv, _local_fallback(request))


func _mark_if_hard(lv: int, result: Dictionary) -> Dictionary:
	if not result.has("entry"):
		return result

	if lv < MIN_REC_LEVEL:
		return result
	var rank: int = int((result["entry"] as Dictionary).get("_bank_rank", 0))
	var hard: bool = _apply_hard_gap(lv, rank >= 4)
	print(
		(
			"[AlgoLevel.11925] Hard 判定: lv=%d rank=%d hard=%s (上次 Hard 关=%d)"
			% [lv, rank, str(hard), GameState.get_last_hard_level()]
		)
	)
	if hard:
		GameState.mark_hard_level(lv)
	return result


func _try_server(lv: int) -> Dictionary:
	var provider := ServerProvider.new()

	var pick: Dictionary = _preview.get(lv, {})
	var skip: int = int(pick.get("skip", -1))
	if skip > 0 and str(pick.get("sig", "")) == LevelRecManager.queue_state_signature():
		print("[AlgoLevel.11925] 预选命中: 跳过前 %d 道(预览已判定会被跳过), 直接取第 %d 道" % [skip, skip])
		for _i: int in range(skip):
			var skipped_entry: Dictionary = provider.next_entry(null)
			if skipped_entry.is_empty():
				break

			var skipped_validation: Dictionary = FinalLevelValidator.validate(skipped_entry, lv)
			if not bool(skipped_validation.valid):
				LevelRecManager.report_invalid_entry(skipped_entry, str(skipped_validation.reason))
	while provider.is_available(null):
		var entry: Dictionary = provider.next_entry(null)
		if entry.is_empty():
			break

		var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
		if not bool(validation.valid):
			LevelRecManager.report_invalid_entry(entry, str(validation.reason))
			print("[AlgoLevel.11925]   跳过: 完整性校验不通过 qid=%s" % str(entry.get("_rec_qid", "")))
			continue
		entry = validation.entry

		var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, lv)
		if bool(dedup.duplicate):
			print("[AlgoLevel.11925]   跳过: 撞重 qid=%s" % str(entry.get("_rec_qid", "")))
			continue

		return _delivered(entry, str(dedup.puzzle_id), &"selected")

	return {}


func _local_fallback(request: LevelSelectRequest) -> Dictionary:
	if _base == null:
		_base = NL12100Strategy.new()
	var result: Dictionary = _base.select(request)
	_local_delivery_pending = result.has("entry")
	if _local_delivery_pending:
		(result["entry"] as Dictionary)["_rec_fallback_reason"] = _fallback_reason
	return result


func on_delivery(entry: Dictionary) -> void:
	if not _local_delivery_pending or _base == null:
		return
	_local_delivery_pending = false
	_base.on_delivery(entry)


func _deliver_special(entry: Dictionary, lv: int) -> Dictionary:
	var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
	if not bool(validation.valid):
		return {}
	var final_entry: Dictionary = validation.entry
	var dedup: Dictionary = PuzzleDeduplicator.inspect(final_entry, lv)
	if bool(dedup.duplicate):
		PuzzleDeduplicator.log_duplicate(dedup.previous, final_entry, lv, dedup.puzzle_id)
		return _delivered(final_entry, str(dedup.puzzle_id), &"duplicate_fallback")
	return _delivered(final_entry, str(dedup.puzzle_id), &"selected")


## 把题目、去重标识与交付状态装进统一结果，交给选题入口完成后续提交。
static func _delivered(entry: Dictionary, puzzle_id: String, status: StringName) -> Dictionary:
	return {"entry": entry, "puzzle_id": puzzle_id, "status": status}
