extends UIFrameWindow

@onready var _count_input: LineEdit = $CenterPanel/Margin/VBox/CountRow/CountInput
@onready var _rnr_input: LineEdit = $CenterPanel/Margin/VBox/RnrRow/RnrInput
@onready var _sc_input: LineEdit = $CenterPanel/Margin/VBox/ScRow/ScInput
@onready var _error_label: Label = $CenterPanel/Margin/VBox/ErrorLabel
@onready var _result_label: Label = $CenterPanel/Margin/VBox/ResultLabel
@onready var _start_btn: Button = $CenterPanel/Margin/VBox/ButtonRow/StartBtn

const _SIZE_CYCLE_CTRL_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_CTRL_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_CTRL_21_50: Array[int] = [8, 9, 10, 9, 10, 8, 9, 10, 9, 10]
const _SIZE_CYCLE_CTRL_51_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_A_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_A_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_A_21_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_B_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_B_11_20: Array[int] = [6, 6, 8, 8, 9, 8, 9, 8, 9, 8]
const _SIZE_CYCLE_B_21_50: Array[int] = [8, 9, 9, 8, 9, 9, 8, 9, 9, 10]
const _SIZE_CYCLE_B_51_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_C_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_C_11_20: Array[int] = [6, 6, 8, 8, 9, 8, 9, 8, 9, 8]
const _SIZE_CYCLE_C_21_100: Array[int] = [8, 9, 9, 8, 9, 9, 8, 9, 9, 10]
const _SIZE_CYCLE_C_101_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_D_1_10: Array[int] = [4, 5, 6, 6, 8, 6, 7, 8, 9, 7]
const _SIZE_CYCLE_D_11_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_E_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_E_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_E_21_50: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_E_51_PLUS: Array[int] = [8, 10, 11, 9, 10, 11, 9, 10, 11, 10]
const _SIZE_CYCLE_F_1_10: Array[int] = [4, 5, 6, 6, 8, 6, 7, 8, 9, 7]
const _SIZE_CYCLE_F_11_50: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_F_51_PLUS: Array[int] = [8, 10, 11, 9, 10, 11, 9, 10, 11, 10]


func _compute_ab_size(level_num: int, sc: int) -> int:
	match sc:
		3:
			if level_num <= 10:
				return _SIZE_CYCLE_A_1_10[level_num - 1]
			if level_num <= 20:
				return _SIZE_CYCLE_A_11_20[level_num - 11]
			return _SIZE_CYCLE_A_21_PLUS[(level_num - 21) % 10]
		4:
			if level_num <= 10:
				return _SIZE_CYCLE_B_1_10[level_num - 1]
			if level_num <= 20:
				return _SIZE_CYCLE_B_11_20[level_num - 11]
			if level_num <= 50:
				return _SIZE_CYCLE_B_21_50[(level_num - 21) % 10]
			return _SIZE_CYCLE_B_51_PLUS[(level_num - 51) % 10]
		5:
			if level_num <= 10:
				return _SIZE_CYCLE_C_1_10[level_num - 1]
			if level_num <= 20:
				return _SIZE_CYCLE_C_11_20[level_num - 11]
			if level_num <= 100:
				return _SIZE_CYCLE_C_21_100[(level_num - 21) % 10]
			return _SIZE_CYCLE_C_101_PLUS[(level_num - 101) % 10]
		6:
			if level_num <= 10:
				return _SIZE_CYCLE_D_1_10[level_num - 1]
			return _SIZE_CYCLE_D_11_PLUS[(level_num - 11) % 10]
		7:
			if level_num <= 10:
				return _SIZE_CYCLE_E_1_10[level_num - 1]
			if level_num <= 20:
				return _SIZE_CYCLE_E_11_20[level_num - 11]
			if level_num <= 50:
				return _SIZE_CYCLE_E_21_50[(level_num - 21) % 10]
			return _SIZE_CYCLE_E_51_PLUS[(level_num - 51) % 10]
		8:
			if level_num <= 10:
				return _SIZE_CYCLE_F_1_10[level_num - 1]
			if level_num <= 50:
				return _SIZE_CYCLE_F_11_50[(level_num - 11) % 10]
			return _SIZE_CYCLE_F_51_PLUS[(level_num - 51) % 10]
		_:
			if level_num <= 10:
				return _SIZE_CYCLE_CTRL_1_10[level_num - 1]
			if level_num <= 20:
				return _SIZE_CYCLE_CTRL_11_20[level_num - 11]
			if level_num <= 50:
				return _SIZE_CYCLE_CTRL_21_50[(level_num - 21) % 10]
			return _SIZE_CYCLE_CTRL_51_PLUS[(level_num - 51) % 10]


func on_show(_params: Dictionary = {}) -> void:
	_error_label.text = ""
	_error_label.visible = false
	_result_label.text = ""
	_result_label.visible = false
	_count_input.text = "100"
	_rnr_input.text = ""
	_sc_input.text = ""
	_start_btn.disabled = false


func _on_close_pressed() -> void:
	UIManager.hide_ui(UiName.PLAYTEST_SIMULATOR)


func _on_start_pressed() -> void:
	var raw: String = _count_input.text.strip_edges()
	if not raw.is_valid_int():
		_show_error("次数必须是整数")
		return
	var count: int = raw.to_int()
	if count <= 0 or count > 100000:
		_show_error("次数应在 1..100000 之间")
		return

	_error_label.visible = false
	_result_label.visible = false
	_start_btn.disabled = true

	await get_tree().process_frame

	var summary: Dictionary = _run_simulation(count)
	if summary.get("ok", false):
		_result_label.text = (
			"完成:%d 局\n唯一 pid 前缀:%d\n跨 level 重复组:%d\ndedup 上报合计:%d\n  ├─ 已知池小(噪声):%d\n  └─ **未知根因(focus):%d**\n报告:%s"
			% [
				count,
				summary["unique_count"],
				summary["cross_lv_dup_groups"],
				summary["dedup_report_count"],
				summary["dedup_known_count"],
				summary["dedup_unknown_count"],
				summary["report_path"]
			]
		)
		_result_label.visible = true
	else:
		_show_error("模拟失败:%s" % summary.get("error", "unknown"))

	_start_btn.disabled = false


func _on_preset_100_pressed() -> void:
	_count_input.text = "100"
	_on_start_pressed()


func _on_preset_1000_pressed() -> void:
	_count_input.text = "1000"
	_on_start_pressed()


func _on_preset_10000_pressed() -> void:
	_count_input.text = "10000"
	_on_start_pressed()


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	push_warning("[playtest] " + msg)


static func _rm_sha256(rm: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row in rm:
		for v in row:
			parts.append(str(int(v)))
	return ",".join(parts).sha256_text().substr(0, 16)


func _build_record_meta(
	iter_idx: int,
	lv: int,
	sz: int,
	source: String,
	pid: String,
	entry: Dictionary,
	rm: Array,
	actions: PackedStringArray
) -> Dictionary:
	return {
		"iter": iter_idx,
		"lv": lv,
		"sz": sz,
		"source": source,
		"pid": pid,
		"region_map_sha256": _rm_sha256(rm),
		"bank_source": entry.get("_bank_source", ""),
		"bank_source_main": entry.get("_bank_source_main", ""),
		"bank_idx": int(entry.get("_bank_idx", 0)),
		"rank": int(entry.get("_bank_rank", 1)),
		"tier": String(entry.get("_bank_tier", "")),
		"strategy": GameState.get_current_strategy(),
		"rnr": ABTestManager.rule_normal_rank.value(),
		"is_dfe": GameState.is_current_level_daily_first_easy(),
		"is_hard": LevelData.is_hard_level(lv),
		"actions": ",".join(actions),
	}


const POOL_SMALL_THRESHOLD: int = 30


static func _bucket_pool_size(side: String, r: Dictionary, pool_sizes: Dictionary) -> int:
	var sz: int = int(r.get("%s_sz" % side, 0))
	var rank: int = int(r.get("%s_rank" % side, 0))
	var tier: String = String(r.get("%s_tier" % side, ""))
	var main: String = String(r.get("%s_bank_source_main" % side, ""))
	if sz <= 0 or rank <= 0:
		return -1
	var key: String
	if main == "lk_mod":
		key = "lkmod_%d_%d" % [sz, rank]
	else:
		key = "main_%d_%d_%s" % [sz, rank, tier]
	return int(pool_sizes.get(key, -1))


static func _is_known_pool_small_dup(r: Dictionary, pool_sizes: Dictionary) -> bool:
	if int(r.get("prev_sz", 0)) != int(r.get("curr_sz", 0)):
		return false
	if int(r.get("prev_rank", 0)) != int(r.get("curr_rank", 0)):
		return false
	if String(r.get("prev_tier", "")) != String(r.get("curr_tier", "")):
		return false
	if String(r.get("prev_bank_source_main", "")) != String(r.get("curr_bank_source_main", "")):
		return false
	var pool: int = _bucket_pool_size("curr", r, pool_sizes)
	return pool > 0 and pool <= POOL_SMALL_THRESHOLD


static func _compute_pool_sizes() -> Dictionary:
	var sizes: Dictionary = {}

	for sz in [4, 5, 6, 7, 8, 9, 10, 11, 12]:
		for rank in [1, 2, 3, 4, 5]:
			var r_all: int = (BankData.get_levels(sz, rank) as Array).size()
			var l_all: int = (BankData.get_lk_style_levels(sz, rank) as Array).size()
			if r_all + l_all > 0:
				sizes["main_%d_%d_" % [sz, rank]] = r_all + l_all

			for tier in ["H", "N"]:
				var rt: int = (BankData.get_levels_by_tier(sz, rank, tier) as Array).size()
				var lt: int = (BankData.get_lk_style_levels_by_tier(sz, rank, tier) as Array).size()
				if rt + lt > 0:
					sizes["main_%d_%d_%s" % [sz, rank, tier]] = rt + lt

	var lkmod_buckets: Dictionary = {}
	for e in BankData.get_lk_modified_levels():
		var sz: int = int(e.get("size", 0))
		var mr: int = int(e.get("maxR", 0))
		if sz <= 0 or mr <= 0:
			continue
		var k: String = "lkmod_%d_%d" % [sz, mr]
		lkmod_buckets[k] = int(lkmod_buckets.get(k, 0)) + 1
	for k in lkmod_buckets.keys():
		sizes[k] = lkmod_buckets[k]
	return sizes


func _run_simulation(count: int) -> Dictionary:
	var orig_lv: int = GameState.get_current_level()
	GameState.reset_all()

	var pool_sizes: Dictionary = _compute_pool_sizes()
	print("[playtest] 扫描题库桶完成,共 %d 个桶,小池阈值=%d" % [pool_sizes.size(), POOL_SMALL_THRESHOLD])

	var rnr_overridden: bool = false
	var rnr_raw: String = _rnr_input.text.strip_edges()
	if rnr_raw.is_valid_int():
		var rnr_val: int = rnr_raw.to_int()
		ABTestManager.rule_normal_rank.set_debug_override(rnr_val)
		rnr_overridden = true
		print("[playtest] rnr override = %d" % rnr_val)

	var sc_raw: String = _sc_input.text.strip_edges()
	var sc_value: int
	if sc_raw.is_valid_int():
		sc_value = sc_raw.to_int()
		print("[playtest] size_cycle override = %d" % sc_value)
	else:
		sc_value = ABTestManager.size_cycle.value()
		print("[playtest] size_cycle = %d (SDK 真值)" % sc_value)

	var log_lines: Array = []
	var by_prefix: Dictionary = {}

	var by_pid_full_record: Dictionary = {}

	var dedup_reports: Array = []

	for i in range(count):
		var lv: int = GameState.get_current_level()

		var entry: Dictionary
		var source: String
		var cached: Dictionary = GameState.get_retry_puzzle(lv)
		if not cached.is_empty():
			entry = {
				"size": cached.get("bank_size", 0),
				"regionMap": cached.get("prebuilt_regions", []),
				"solution": cached.get("prebuilt_solution", []),
				"_bank_rank": cached.get("bank_rank", 1),
				"_bank_idx": cached.get("bank_index", 0),
				"_bank_tier": cached.get("bank_tier", ""),
				"_bank_source_main": cached.get("bank_source_main", ""),
				"_bank_source": cached.get("bank_source", "regular"),
			}
			source = "cached"
		else:
			entry = LevelData.get_level_entry(lv, _compute_ab_size(lv, sc_value))
			source = "fresh"

		if entry.is_empty() or not entry.has("regionMap"):
			GameState.cheat_jump_to_level(orig_lv)
			return {"ok": false, "error": "get_level_entry(%d) 返回空 entry" % lv}

		var sz: int = int(entry.get("size", 0))
		if sz == 0:
			sz = (entry["regionMap"] as Array).size()
		var rm: Array = entry["regionMap"]
		var full_pid: String = LevelData.compute_puzzle_id(sz, rm)

		var actions: PackedStringArray = PackedStringArray()
		if randf() < 1.0 / 3.0:
			actions.append("locate")
			GameState.mark_current_level_dirty()
		if randf() < 1.0 / 3.0:
			actions.append("hint")
			GameState.mark_current_level_dirty()

		var curr_meta: Dictionary = _build_record_meta(
			i + 1, lv, sz, source, full_pid, entry, rm, actions
		)
		var dup_prev: Dictionary = GameState.record_puzzle(full_pid, lv)
		var dedup_triggered: bool = false
		if not dup_prev.is_empty() and int(dup_prev.get("level", -1)) != lv:
			LevelData.advance_for_entry(entry, sz)
			var retry_entry: Dictionary = LevelData.get_level_entry(lv, 0)
			if not retry_entry.is_empty() and retry_entry.has("regionMap"):
				var retry_sz: int = int(retry_entry.get("size", 0))
				if retry_sz == 0:
					retry_sz = (retry_entry["regionMap"] as Array).size()
				var retry_rm: Array = retry_entry["regionMap"]
				var retry_pid: String = LevelData.compute_puzzle_id(retry_sz, retry_rm)
				var retry_meta: Dictionary = _build_record_meta(
					i + 1,
					lv,
					retry_sz,
					source + "/retry",
					retry_pid,
					retry_entry,
					retry_rm,
					actions
				)
				var retry_dup: Dictionary = GameState.record_puzzle(retry_pid, lv)
				if not retry_dup.is_empty() and int(retry_dup.get("level", -1)) != lv:
					dedup_triggered = true
					var prev_meta: Dictionary = (
						by_pid_full_record
						. get(
							retry_pid,
							{
								"iter": -1,
								"lv": int(retry_dup.get("level", -1)),
								"source": "?",
								"region_map_sha256": "?",
								"bank_source": "?",
								"bank_source_main": "?",
								"bank_idx": -1,
								"rank": -1,
								"tier": "?",
								"strategy": -1,
								"rnr": -1,
								"is_dfe": false,
								"is_hard": false,
								"actions": "?",
							}
						)
					)
					var dedup_entry: Dictionary = {
						"iter_prev": int(prev_meta.get("iter", -1)),
						"iter_curr": i + 1,
						"iter_distance": (i + 1) - int(prev_meta.get("iter", 0)),
						"lv_prev": int(prev_meta.get("lv", -1)),
						"lv_curr": lv,
						"prev_sz": int(prev_meta.get("sz", -1)),
						"curr_sz": int(retry_meta["sz"]),
						"pid": retry_pid,
						"sha_prev": String(prev_meta.get("region_map_sha256", "?")),
						"sha_curr": _rm_sha256(retry_rm),
						"prev_source": String(prev_meta.get("source", "?")),
						"curr_source": String(retry_meta["source"]),
						"prev_bank_source": String(prev_meta.get("bank_source", "?")),
						"curr_bank_source": String(retry_meta["bank_source"]),
						"prev_bank_source_main": String(prev_meta.get("bank_source_main", "?")),
						"curr_bank_source_main": String(retry_meta["bank_source_main"]),
						"prev_bank_idx": int(prev_meta.get("bank_idx", -1)),
						"curr_bank_idx": int(retry_meta["bank_idx"]),
						"prev_rank": int(prev_meta.get("rank", -1)),
						"curr_rank": int(retry_meta["rank"]),
						"prev_tier": String(prev_meta.get("tier", "?")),
						"curr_tier": String(retry_meta["tier"]),
						"strategy_at_curr": int(retry_meta["strategy"]),
						"rnr": int(retry_meta["rnr"]),
						"is_dfe_at_curr": bool(retry_meta["is_dfe"]),
						"is_hard_at_curr": bool(retry_meta["is_hard"]),
						"prev_actions": String(prev_meta.get("actions", "?")),
						"curr_actions": String(retry_meta["actions"]),
					}
					dedup_entry["bucket_pool_size_curr"] = _bucket_pool_size(
						"curr", dedup_entry, pool_sizes
					)
					dedup_entry["bucket_pool_size_prev"] = _bucket_pool_size(
						"prev", dedup_entry, pool_sizes
					)
					dedup_entry["is_known_pool"] = _is_known_pool_small_dup(dedup_entry, pool_sizes)
					dedup_reports.append(dedup_entry)

				entry = retry_entry
				sz = retry_sz
				rm = retry_rm
				full_pid = retry_pid
				curr_meta = retry_meta

		by_pid_full_record[full_pid] = curr_meta

		var prefix: String = _strip_suffix(full_pid)

		var outcome: String
		if randf() < 1.0 / 10.0:
			outcome = "restart"
			GameState.on_level_failed(lv)

			(
				GameState
				. set_retry_puzzle(
					lv,
					{
						"bank_mode": true,
						"bank_size": sz,
						"bank_rank": int(entry.get("_bank_rank", 1)),
						"bank_index": int(entry.get("_bank_idx", 0)),
						"bank_source_main": entry.get("_bank_source_main", ""),
						"bank_source": entry.get("_bank_source", ""),
						"bank_tier": entry.get("_bank_tier", ""),
						"prebuilt_regions": rm,
						"prebuilt_solution": entry.get("solution", []),
					}
				)
			)
		else:
			outcome = "win"

			GameState.on_level_won(lv)
		actions.append(outcome)

		var dedup_mark: String = "  [DEDUP]" if dedup_triggered else ""
		log_lines.append(
			(
				"[%05d] lv=%-4d pid=%-37s source=%-13s actions=%s%s"
				% [i + 1, lv, full_pid, source, ",".join(actions), dedup_mark]
			)
		)
		if not by_prefix.has(prefix):
			by_prefix[prefix] = []
		(
			by_prefix[prefix]
			. append(
				{
					"iter": i + 1,
					"lv": lv,
					"source": source,
					"actions": ",".join(actions),
				}
			)
		)

	var cross_lv_dups: Array = []
	for p in by_prefix.keys():
		var hits: Array = by_prefix[p]
		var unique_lvs: Array = []
		for h in hits:
			if not h["lv"] in unique_lvs:
				unique_lvs.append(h["lv"])
		if unique_lvs.size() >= 2:
			cross_lv_dups.append({"prefix": p, "hits": hits, "unique_lvs": unique_lvs})

	var window_dups: Array = []
	for p in by_prefix.keys():
		var hits: Array = by_prefix[p]

		hits.sort_custom(func(a, b): return a["iter"] < b["iter"])
		for idx in range(hits.size() - 1):
			var a: Dictionary = hits[idx]
			var b: Dictionary = hits[idx + 1]
			if a["lv"] != b["lv"] and absi(b["lv"] - a["lv"]) <= 10:
				window_dups.append({"prefix": p, "a": a, "b": b})

	var report_path: String = _write_report(
		count, log_lines, by_prefix, cross_lv_dups, window_dups, dedup_reports
	)

	GameState.cheat_jump_to_level(orig_lv)

	if rnr_overridden:
		ABTestManager.rule_normal_rank.clear_debug_override()
		print("[playtest] rnr override cleared")

	var dedup_known_count: int = 0
	for r in dedup_reports:
		if bool(r.get("is_known_pool", false)):
			dedup_known_count += 1
	var dedup_unknown_count: int = dedup_reports.size() - dedup_known_count

	return {
		"ok": true,
		"unique_count": by_prefix.size(),
		"cross_lv_dup_groups": cross_lv_dups.size(),
		"window_dup_count": window_dups.size(),
		"dedup_report_count": dedup_reports.size(),
		"dedup_known_count": dedup_known_count,
		"dedup_unknown_count": dedup_unknown_count,
		"report_path": report_path,
	}


static func _append_dedup_detail(out: PackedStringArray, r: Dictionary) -> void:
	out.append(
		(
			"### [%05d → %05d] iter_distance=%d  pid=`%s`"
			% [r["iter_prev"], r["iter_curr"], r["iter_distance"], r["pid"]]
		)
	)
	out.append("")
	out.append("| 字段 | PREV | CURR |")
	out.append("|---|---|---|")
	out.append("| iter | %d | %d |" % [r["iter_prev"], r["iter_curr"]])
	out.append("| lv | %d | %d |" % [r["lv_prev"], r["lv_curr"]])
	out.append("| sz | %d | %d |" % [int(r.get("prev_sz", -1)), int(r.get("curr_sz", -1))])
	out.append("| region_map sha256 | `%s` | `%s` |" % [r["sha_prev"], r["sha_curr"]])
	out.append("| source | %s | %s |" % [r["prev_source"], r["curr_source"]])
	out.append("| bank_source | %s | %s |" % [r["prev_bank_source"], r["curr_bank_source"]])
	out.append(
		"| bank_source_main | %s | %s |" % [r["prev_bank_source_main"], r["curr_bank_source_main"]]
	)
	out.append("| bank_idx | %d | %d |" % [r["prev_bank_idx"], r["curr_bank_idx"]])
	out.append("| rank | %d | %d |" % [r["prev_rank"], r["curr_rank"]])
	out.append("| tier | `%s` | `%s` |" % [r["prev_tier"], r["curr_tier"]])
	out.append(
		(
			"| bucket pool size | %d | %d |"
			% [int(r.get("bucket_pool_size_prev", -1)), int(r.get("bucket_pool_size_curr", -1))]
		)
	)
	out.append("| actions | %s | %s |" % [r["prev_actions"], r["curr_actions"]])
	out.append("")
	out.append(
		(
			"CURR 时上下文:strategy=%d, rnr=%d, is_dfe=%s, is_hard=%s"
			% [r["strategy_at_curr"], r["rnr"], str(r["is_dfe_at_curr"]), str(r["is_hard_at_curr"])]
		)
	)
	out.append("")


func _strip_suffix(full_id: String) -> String:
	var parts: PackedStringArray = full_id.split("_", false, 2)
	return parts[0] + "_" + parts[1] if parts.size() >= 2 else full_id


func _write_report(
	count: int,
	log_lines: Array,
	by_prefix: Dictionary,
	cross_lv_dups: Array,
	window_dups: Array,
	dedup_reports: Array
) -> String:
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = "res://docs/level-bank/playtest-simulation-%s.md" % ts

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/level-bank"))

	var out: PackedStringArray = PackedStringArray()
	out.append("# Playtest 模拟报告")
	out.append("")
	out.append("生成时间: %s  " % ts)
	out.append("模拟参数: count=%d, locate=1/3, hint=1/3, restart=1/10, size_cycle=0" % count)
	out.append("")
	out.append("## 统计摘要")
	out.append("")
	out.append("- 总局数: %d" % count)
	out.append("- 唯一 puzzle_id 前缀数: %d" % by_prefix.size())
	out.append("- 跨 level 重复组(同 prefix 出现在 ≥2 个 level): **%d**" % cross_lv_dups.size())
	out.append("- 短窗口重复对(相邻 ≤10 关内同 prefix): **%d**" % window_dups.size())

	var dedup_known: Array = []
	var dedup_unknown: Array = []
	for r in dedup_reports:
		if bool(r.get("is_known_pool", false)):
			dedup_known.append(r)
		else:
			dedup_unknown.append(r)

	out.append("- **模拟 dedup 上报合计(对齐线上 LogUtil.error): %d**" % dedup_reports.size())
	out.append("  - 已知池小(同桶且池 ≤ %d,噪声折叠): %d" % [POOL_SMALL_THRESHOLD, dedup_known.size()])
	out.append("  - **未知根因(focus,对应线上 session 3/4/5 同类): %d**" % dedup_unknown.size())
	out.append("")

	out.append("## 未知根因 dedup 上报(focus)")
	out.append("")
	(
		out
		. append(
			(
				"已剔除「PREV / CURR 同桶且该桶池 ≤ %d」的案例(那些都属已定位的池小循环根因)。**剩余即与线上 session 3/4/5 同类的待查问题**:跨桶撞重 / 大桶撞重 / idx 推进异常等。"
				% POOL_SMALL_THRESHOLD
			)
		)
	)
	out.append("")
	if dedup_unknown.is_empty():
		out.append("**无**(本轮模拟未触发任何「非池小」路径的 dedup 上报)")
		out.append("")
	else:
		dedup_unknown.sort_custom(
			func(a, b): return int(a["iter_distance"]) < int(b["iter_distance"])
		)
		out.append("(按 iter_distance 升序,小跨度优先)")
		out.append("")
		for r in dedup_unknown:
			_append_dedup_detail(out, r)

	out.append("## 已知池小 dedup 上报(噪声折叠)")
	out.append("")
	(
		out
		. append(
			(
				"PREV / CURR 同桶且桶内题数 ≤ %d → 必然池小循环,根因已定位(LKModified 各桶 ≤ 38 / 主线 sz=10 R1=14 / sz=4-5 / sz=11 等小桶)。"
				% POOL_SMALL_THRESHOLD
			)
		)
	)
	out.append("**修复方向**:扩 LKModified 题库 / lk_mod 独立 transform / `get_next_entry` 接 transform 救援。")
	out.append("")
	if dedup_known.is_empty():
		out.append("无")
		out.append("")
	else:
		var by_bucket: Dictionary = {}
		for r in dedup_known:
			var key: String
			var main: String = String(r.get("curr_bank_source_main", ""))
			if main == "lk_mod":
				key = (
					"lkmod_%d_R%d (池=%d)"
					% [int(r["curr_sz"]), int(r["curr_rank"]), int(r["bucket_pool_size_curr"])]
				)
			else:
				key = (
					"main_%d_R%d_%s (池=%d)"
					% [
						int(r["curr_sz"]),
						int(r["curr_rank"]),
						(
							String(r.get("curr_tier", ""))
							if String(r.get("curr_tier", "")) != ""
							else "noT"
						),
						int(r["bucket_pool_size_curr"])
					]
				)
			by_bucket[key] = int(by_bucket.get(key, 0)) + 1
		out.append("按桶聚合:")
		out.append("")
		var keys: Array = by_bucket.keys()
		keys.sort()
		for k in keys:
			out.append("- %s : %d 条" % [k, by_bucket[k]])
		out.append("")
		out.append("采样(按 iter_distance 升序前 3 条):")
		out.append("")
		dedup_known.sort_custom(
			func(a, b): return int(a["iter_distance"]) < int(b["iter_distance"])
		)
		var sample_n: int = min(3, dedup_known.size())
		for i in range(sample_n):
			_append_dedup_detail(out, dedup_known[i])

	out.append("## 跨 level 重复组(prefix 维度,canonical 等价类)")
	out.append("")
	if cross_lv_dups.is_empty():
		out.append("无")
	else:
		cross_lv_dups.sort_custom(
			func(a, b): return (a["hits"] as Array).size() > (b["hits"] as Array).size()
		)
		var n: int = min(50, cross_lv_dups.size())
		for i in range(n):
			var g: Dictionary = cross_lv_dups[i]
			out.append(
				(
					"### prefix=`%s`  unique_lvs=%s  total_hits=%d"
					% [g["prefix"], str(g["unique_lvs"]), (g["hits"] as Array).size()]
				)
			)
			for h in g["hits"]:
				out.append(
					(
						"  - [%05d] lv=%d source=%s actions=%s"
						% [h["iter"], h["lv"], h["source"], h["actions"]]
					)
				)
			out.append("")
		if cross_lv_dups.size() > n:
			out.append("...(还有 %d 组未列出)" % (cross_lv_dups.size() - n))
			out.append("")

	out.append("## 短窗口重复(相邻 ≤10 关,prefix 维度)")
	out.append("")
	if window_dups.is_empty():
		out.append("无")
	else:
		var nw: int = min(50, window_dups.size())
		for i in range(nw):
			var d: Dictionary = window_dups[i]
			(
				out
				. append(
					(
						"- prefix=`%s` [%05d]lv=%d → [%05d]lv=%d (间隔 %d 关)"
						% [
							d["prefix"],
							d["a"]["iter"],
							d["a"]["lv"],
							d["b"]["iter"],
							d["b"]["lv"],
							absi(d["b"]["lv"] - d["a"]["lv"]),
						]
					)
				)
			)
		if window_dups.size() > nw:
			out.append("...(还有 %d 对未列出)" % (window_dups.size() - nw))
		out.append("")

	out.append("## 全量日志")
	out.append("")
	out.append("```")
	for line in log_lines:
		out.append(line)
	out.append("```")

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "(写文件失败:%s)" % path
	f.store_string("\n".join(out))
	f.close()
	return path
