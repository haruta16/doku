## 推荐服务诊断器：构造请求与历史数据，检查返回题目并对照本地题库。
class_name RecProbe
extends RefCounted

const _HISTORY_MAX: int = 50

const _RETAINED_MAX: int = 13

const _SAMPLE_QIDS: Array[String] = [
	"4_regular_1_1_0",
	"4_regular_1_2_0",
	"6_regular_1_1_0",
	"6_regular_1_2_0",
	"4_regular_1_3_0",
	"6_regular_1_3_0",
	"6_regular_1_4_0",
	"4_regular_1_4_0",
	"6_regular_1_5_0",
	"6_regular_1_6_0",
	"4_regular_1_5_0",
	"6_regular_1_7_0",
	"6_regular_1_8_0",
	"6_regular_2_1_0",
]


## 根据参数构造诊断请求，实际调用推荐接口；收到结果后释放临时 HTTP 节点并输出分析。
static func run(host_node: Node, args: Array[String]) -> void:
	var hist_n: int = clampi(int(args[0]) if args.size() > 0 else 15, 0, _HISTORY_MAX)
	var ab_group: String = str(args[1]) if args.size() > 1 else "treatment"
	var retained_n: int = clampi(int(args[2]) if args.size() > 2 else 4, 0, _RETAINED_MAX)

	var body: Dictionary = _build_body(hist_n, ab_group, retained_n)

	var http := RecHttp.new()
	host_node.add_child(http)
	var resp: Dictionary = await http.post(ApiConfig.PATH_REC_QUESTION_NEXT, body)
	http.queue_free()

	_dump(resp)


static func _build_body(hist_n: int, ab_group: String, retained_n: int) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var lv: int = GameState.get_current_level()

	var sz: int = SizeModifier.get_size(lv)
	var body: Dictionary = {
		"request_id": _gen_request_id(now),
		"user_id": _user_id(),
		"decision_size": sz if sz > 0 else 8,
		"ab_group": ab_group,
		"decision_ts_s": now,
		"recent_history_normalized_raw_facts": _synth_history(hist_n, now, lv),
		"extra_values": {},
	}

	if retained_n > 0:
		body[RecApi.KEY_RETAINED_ASSIGNMENTS] = _synth_retained_assignments(retained_n)
	return body


static func _gen_request_id(now: int) -> String:
	return "probe-%d-%d" % [now, randi()]


const _SAMPLE_USER_ID: String = "7228f1e2a2e24ba9a5aec44796975e1f"


static func _user_id() -> String:
	var luid: String = ApiConfig.luid()
	if not luid.is_empty():
		return luid
	var lid: String = UniKitManager.get_learnings_id()
	if not lid.is_empty():
		return lid
	return _SAMPLE_USER_ID


static func _synth_history(n: int, now: int, current_level: int) -> Array:
	var out: Array = []
	for i: int in range(n):
		var back: int = n - i
		var end_ts: int = now - back * 120
		var is_fail: bool = i % 7 == 5
		var is_quit: bool = i % 11 == 9
		var result: String = "win"
		if is_quit:
			result = "quit"
		elif is_fail:
			result = "fail"
		(
			out
			. append(
				{
					"exact_qid": _SAMPLE_QIDS[i % _SAMPLE_QIDS.size()],
					"level": maxi(1, current_level - back),
					"end_ts_s": end_ts,
					"is_win": 0 if result != "win" else 1,
					"result": result,
					"duration_seconds": 30.0 + float(i % 9) * 12.0,
					"fail_times": 1 if is_fail else 0,
					"restart_times": 1 if is_quit else 0,
					"hint_used_total": i % 3,
					"locate_used_total": i % 2,
					"interval_seconds": float(now - end_ts),
					"session_position": i + 1,
				}
			)
		)
	return out


static func _synth_retained_assignments(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		var play_state: int
		if i == n - 1:
			play_state = RecLevelQueue.RecPlayState.PENDING
		elif i % 3 == 1:
			play_state = RecLevelQueue.RecPlayState.DISCARDED
		else:
			play_state = RecLevelQueue.RecPlayState.PLAYED
		(
			out
			. append(
				{
					"qid": _SAMPLE_QIDS[i % _SAMPLE_QIDS.size()],
					"play_state": play_state,
				}
			)
		)
	return out


static func _dump(resp: Dictionary) -> void:
	print("========== [RecProbe] 响应 ==========")
	if not bool(resp.get("ok", false)):
		print("传输层失败: %s（离线 / DNS / 超时，业务码无意义）" % str(resp.get("message", "")))
		print("=====================================\n")
		return

	var code: int = int(resp.get("code", -1))
	print(
		(
			"http=%d code=%d msg=%s"
			% [int(resp.get("http_status", 0)), code, str(resp.get("message", ""))]
		)
	)
	if code != ApiConfig.CODE_OK:
		print("业务码非 0。若 http=400，先核对公共头 app 取值（客户端=%s，文档样本=meowdoku）" % ApiConfig.APP_ID)
		print("=====================================\n")
		return

	var data: Dictionary = resp.get("data", {})
	print(
		(
			"dispatch_status=%s recommend_source=%s"
			% [str(data.get("dispatch_status", "")), str(data.get("recommend_source", ""))]
		)
	)
	print(
		(
			"reason=%s fallback_reason=%s"
			% [str(data.get("reason", "")), str(data.get("fallback_reason", ""))]
		)
	)
	print("extra_values=%s" % JSON.stringify(data.get("extra_values", {})))

	var levels: Array = data.get("levels", []) if data.get("levels", []) is Array else []
	print("levels=%d 道（额定 12）" % levels.size())
	if levels.is_empty():
		print("=====================================\n")
		return

	_dump_first_level(levels[0])
	_dump_sequence(levels)
	_cross_check_bank(levels)
	print("=====================================\n")


static func _dump_first_level(lv0_raw: Variant) -> void:
	if not (lv0_raw is Dictionary):
		print("[levels[0]] 不是 object，实际类型=%s" % type_string(typeof(lv0_raw)))
		return
	var lv0: Dictionary = lv0_raw
	var keys: Array = lv0.keys()
	keys.sort()
	var key_names := PackedStringArray()
	for k: Variant in keys:
		key_names.append(str(k))
	print("\n-- levels[0] 全部 key（%d 个）--\n%s" % [keys.size(), ", ".join(key_names)])

	var rm: Variant = lv0.get("region_map", null)
	var sol: Variant = lv0.get("solution", null)
	var sz: int = int(lv0.get("size", 0))
	print("\n-- 题面字段是否下发（探针头号问题）--")
	print("size=%d" % sz)
	print("region_map: %s" % _describe_matrix(rm, sz))
	print("solution:   %s" % _describe_array(sol, sz))
	print(
		(
			"seed=%s steps=%s r=%s r1..r5=%s/%s/%s/%s/%s"
			% [
				str(lv0.get("seed", "<缺>")),
				str(lv0.get("steps", "<缺>")),
				str(lv0.get("r", "<缺>")),
				str(lv0.get("r1", "<缺>")),
				str(lv0.get("r2", "<缺>")),
				str(lv0.get("r3", "<缺>")),
				str(lv0.get("r4", "<缺>")),
				str(lv0.get("r5", "<缺>"))
			]
		)
	)
	var playable: bool = rm is Array and (rm as Array).size() == sz and sz > 0
	print(
		(
			"→ 结论：题面%s（%s）"
			% [
				"可直接开局" if playable else "未下发，需本地题库反查",
				"region_map 行数与 size 一致" if playable else "region_map 为 null 或行数不符"
			]
		)
	)

	print("\n-- qid 分段自洽 --")
	var parsed: Dictionary = parse_qid(str(lv0.get("qid", "")))
	if parsed.is_empty():
		print("qid=%s 无法按 size_source_strategy_idx_transform 解析" % str(lv0.get("qid", "")))
	else:
		print(
			(
				"qid=%s → size=%d source=%s strategy=%d idx=%d transform=%d"
				% [
					str(lv0.get("qid", "")),
					int(parsed.size_),
					str(parsed.source),
					int(parsed.strategy),
					int(parsed.idx),
					int(parsed.transform)
				]
			)
		)
		print(
			(
				"响应字段 → size=%d source=%s strategy=%s rank=%s tier=%s"
				% [
					sz,
					str(lv0.get("source", "")),
					str(lv0.get("strategy", "")),
					str(lv0.get("rank", "")),
					str(lv0.get("tier", ""))
				]
			)
		)
		var size_ok: bool = int(parsed.size_) == sz
		var src_ok: bool = str(parsed.source) == str(lv0.get("source", ""))
		var stg_ok: bool = int(parsed.strategy) == int(lv0.get("strategy", -1))
		print("→ 自洽: size %s / source %s / strategy %s" % [_yn(size_ok), _yn(src_ok), _yn(stg_ok)])
	print("\n-- impression_id 约定 {request_id}_{slot} --")
	print("levels[0].impression_id=%s" % str(lv0.get("impression_id", "<缺>")))


static func _dump_sequence(levels: Array) -> void:
	print("\n-- 12 道序列 --")
	print(
		(
			"%-4s %-22s %-5s %-9s %-5s %-5s %-10s %-9s %s"
			% ["slot", "qid", "size", "source", "rank", "tier", "rhythm", "selection", "explore"]
		)
	)
	for i: int in range(levels.size()):
		if not (levels[i] is Dictionary):
			continue
		var e: Dictionary = levels[i]
		print(
			(
				"%-4d %-22s %-5s %-9s %-5s %-5s %-10s %-9s %s"
				% [
					i,
					str(e.get("qid", "")),
					str(e.get("size", "")),
					str(e.get("source", "")),
					str(e.get("rank", "")),
					"'" + str(e.get("tier", "")) + "'",
					str(e.get("rhythm_state", "")),
					str(e.get("selection_status", "")),
					str(e.get("is_explore", ""))
				]
			)
		)


static func _cross_check_bank(levels: Array) -> void:
	print("\n-- 与本地题库交叉验证（同时反推 idx 基准）--")
	var tier_hits: int = 0
	var plain_hits: int = 0
	var checked: int = 0
	for lv_raw: Variant in levels:
		if not (lv_raw is Dictionary):
			continue
		var e: Dictionary = lv_raw
		var p: Dictionary = parse_qid(str(e.get("qid", "")))
		if p.is_empty():
			continue
		var server_rm_raw: Variant = e.get("region_map", null)
		if not (server_rm_raw is Array):
			continue
		var server_rm: Array = server_rm_raw
		if server_rm.is_empty():
			continue
		checked += 1
		var sz: int = int(p.size_)
		var rank: int = int(e.get("rank", 0))
		var tier: String = str(e.get("tier", ""))
		var idx: int = int(p.idx)
		var t: int = int(p.transform)

		if _matches_local(sz, rank, tier, str(p.source), idx, t, server_rm):
			tier_hits += 1
		if not tier.is_empty() and _matches_local(sz, rank, "", str(p.source), idx, t, server_rm):
			plain_hits += 1

	if checked == 0:
		print("题面未下发或无可解析 qid，跳过（这本身就是结论：必须本地反查）")
		return
	print("可比对 %d 道 → tier 过滤基准命中 %d 道，全量基准命中 %d 道" % [checked, tier_hits, plain_hits])
	if tier_hits == checked:
		print("→ idx 基准 = tier 过滤后池内下标+1（与客户端 _bank_idx 口径一致）")
	elif plain_hits > tier_hits:
		print("→ idx 基准 = 全量数组下标+1（与客户端 _bank_idx **不一致**，反查需换算）")
	else:
		print("→ 两种基准都没全中：服务端题面可能与本地题库版本不同，需与服务端核对题库版本")


static func _matches_local(
	sz: int, rank: int, tier: String, source: String, idx: int, transform: int, server_rm: Array
) -> bool:
	var arr: Array = _local_pool(sz, rank, tier, source)

	var entry_index: int = idx - 1
	if entry_index < 0 or entry_index >= arr.size():
		return false
	var entry: Dictionary = arr[entry_index]
	var rm: Array = BankData.get_region_map(entry)
	if rm.is_empty():
		return false
	if transform > 0 and source != "lk_mod":
		var sol: Array = BankData.get_solution(entry)
		var transformed: Array = LevelData.apply_transform(rm, sol, sz, transform)
		rm = transformed[0]
	return _matrix_equal(rm, server_rm)


static func _local_pool(sz: int, rank: int, tier: String, source: String) -> Array:
	match source:
		"regular":
			return (
				BankData.get_levels_by_tier(sz, rank, tier)
				if tier != ""
				else BankData.get_levels(sz, rank)
			)
		"lkstyle":
			return (
				BankData.get_lk_style_levels_by_tier(sz, rank, tier)
				if tier != ""
				else BankData.get_lk_style_levels(sz, rank)
			)
		"gc":
			return (
				BankData.get_gc_levels_by_tier(sz, rank, tier)
				if tier != ""
				else BankData.get_gc_levels(sz, rank)
			)
		"lk_mod":
			return BankData.get_lk_modified_levels()
		_:
			return []


static func parse_qid(qid: String) -> Dictionary:
	var parts: PackedStringArray = qid.split("_")
	if parts.size() != 5:
		return {}
	if not (
		parts[0].is_valid_int()
		and parts[2].is_valid_int()
		and parts[3].is_valid_int()
		and parts[4].is_valid_int()
	):
		return {}
	return {
		"size_": int(parts[0]),
		"source": parts[1],
		"strategy": int(parts[2]),
		"idx": int(parts[3]),
		"transform": int(parts[4]),
	}


static func _matrix_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for r: int in range(a.size()):
		if not (a[r] is Array and b[r] is Array):
			return false
		var ra: Array = a[r]
		var rb: Array = b[r]
		if ra.size() != rb.size():
			return false
		for c: int in range(ra.size()):
			if int(ra[c]) != int(rb[c]):
				return false
	return true


static func _describe_matrix(v: Variant, expect_sz: int) -> String:
	if v == null:
		return "null（未下发）"
	if not (v is Array):
		return "非数组，类型=%s" % type_string(typeof(v))
	var arr: Array = v
	if arr.is_empty():
		return "空数组（未下发）"
	var first_len: int = (arr[0] as Array).size() if arr[0] is Array else -1
	return (
		"%d 行 × %d 列（期望 %d×%d）%s"
		% [
			arr.size(),
			first_len,
			expect_sz,
			expect_sz,
			"" if arr.size() == expect_sz and first_len == expect_sz else "  ⚠ 与 size 不符"
		]
	)


static func _describe_array(v: Variant, expect_sz: int) -> String:
	if v == null:
		return "null（未下发）"
	if not (v is Array):
		return "非数组，类型=%s" % type_string(typeof(v))
	var arr: Array = v
	if arr.is_empty():
		return "空数组（未下发）"
	return (
		"长度 %d（期望 %d）%s"
		% [arr.size(), expect_sz, "" if arr.size() == expect_sz else "  ⚠ 与 size 不符"]
	)


static func _yn(ok: bool) -> String:
	return "✓" if ok else "✗"
