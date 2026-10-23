## 集中输出选题诊断日志，用于核对题目来源、难度、链式策略、快速开局和同构去重结果。
class_name LevelSelectionLog
extends RefCounted


## 计算区域分布指标，并按阈值输出密度分类。
static func log_density_unconditional(entry: Dictionary) -> void:
	if not entry.has("regionMap"):
		return
	var density: float = QueendokuCore.compute_avg_region_bbox_fill_ratio(entry["regionMap"])
	var is_high: bool = density < QueendokuCore.DISPERSION_DENSITY_THRESHOLD
	var color: String = "red" if is_high else "green"
	var label: String = "高" if is_high else "低"
	var msg: String = "[LEVEL.sparse] 分散度=%.2f，属于%s分散度" % [density, label]
	var source: String = entry.get("_bank_source", "")
	if source == "sp" or source == "lk" or source == "lk_mod":
		msg += "（该题属于 %s 题库，不适用分散度逻辑）" % source
	elif is_high:
		var sz: int = (entry["regionMap"] as Array).size()
		var rank: int = int(entry.get("_bank_rank", 0))
		msg += "（无可行低分散%d*%d,R%d题目，兜底返回高分散度题）" % [sz, sz, rank]
	print_rich("[color=%s]%s[/color]" % [color, msg])


## 记录最终交付题的来源、难度范围、评级与单格区域数等诊断信息。
static func log_delivered(level_num: int, entry: Dictionary, puzzle_id: String) -> void:
	var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "?")))
	if source == "":
		source = str(entry.get("_bank_source", "?"))
	var rank: int = int(entry.get("_delivery_rank", entry.get("_bank_rank", 0)))
	var difficulty: String = "R%d" % rank
	if rank >= 4:
		difficulty += "H" if str(entry.get("_bank_tier", "")) == "H" else "N"
	var label: String = "HARD " if LevelSelector.is_hard_level(level_num) else ""
	var current_strategy: int = GameState.get_current_strategy()
	var msg: String = (
		"[LEVEL.select] %sLv%d 题库=%s 难度=%s current_strategy=%d 指纹=%s"
		% [label, level_num, source, difficulty, current_strategy, puzzle_id]
	)

	if entry.has("rating"):
		msg += " rating=%.1f" % float(entry["rating"])
	if source == "sp_tt":
		msg += (
			" shapeCategory=%d transform=%d"
			% [int(entry.get("_sp_tt_category", 0)), int(entry.get("_bank_transform", 0))]
		)
	if entry.get("isChainedStrategy", false):
		msg += " isChainedStrategy=%s" % entry["isChainedStrategy"]

	if entry.has("_bank_single_count"):
		msg += "，卡点后置关卡" if int(entry["_bank_single_count"]) == 1 else "，卡点前置关卡"
	if bool(entry.get("_chain_forced", false)):
		msg += " ✅"
	var region_sizes: Dictionary = {}
	for row: Array in entry.get("regionMap", []):
		for region: Variant in row:
			region_sizes[region] = int(region_sizes.get(region, 0)) + 1
	var single_region_count: int = 0
	for size: int in region_sizes.values():
		if size == 1:
			single_region_count += 1
	msg += " 单格区域数量=%d" % single_region_count
	if bool(entry.get("_chain_forced", false)):
		print_rich("[color=green]%s[/color]" % msg)
	else:
		print(msg)


## 记录链式策略是否触发、命中或回退，以及最近的链式关卡锚点。
static func log_chain_strategy(
	level_num: int, entry: Dictionary, group_label: String, trigger_active: bool
) -> void:
	var hit: bool = bool(entry.get("isChainedStrategy", false))
	var status: String
	if not trigger_active:
		status = "未触发"
	elif hit:
		status = "命中，已置换为连锁关卡"
	else:
		status = "触发但池内无候选，已按降级阶梯放行普通题"
	print(
		(
			"[LEVEL.chain_strategy] Lv%d [%s] %s（冷却锚点=Lv%d）"
			% [level_num, group_label, status, GameState.get_chain_last_replaced_level()]
		)
	)


## 记录快速开局的匹配结果、回退情况与预填类型。
static func log_quick_start(
	level_num: int,
	group_label: String,
	match_desc: String,
	matched: bool,
	pre_type: String,
	fallback_reason: String = ""
) -> void:
	var status: String
	if matched:
		status = "命中，已换成%s的关卡" % match_desc
	elif fallback_reason != "":
		status = "命中但%s，不换关" % fallback_reason
	else:
		status = "命中但池内无符合候选，已按降级阶梯放行普通题"
	print(
		"[LEVEL.quick_start] Lv%d [%s] %s（pre_type=%s）" % [level_num, group_label, status, pre_type]
	)


## 记录同构去重结果、拒绝次数和耗时；输入微秒会换算为秒输出。
static func log_isomorphic_dedup(
	level_num: int,
	entry: Dictionary,
	iso_filter_active: bool,
	reject_count: int = 0,
	elapsed_usec: int = 0
) -> void:
	var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	var status: String
	if source == "sp":
		status = "SP 题库不受影响，未做同构检测"
	elif iso_filter_active:
		status = "已确认与近 30 关不同构"
	else:
		status = "同构过滤已被降级阶梯放宽，交付候选可能与近 30 关同构"
	print(
		(
			"[LEVEL.isomorphic_dedup] Lv%d %s 耗时%.3fs，失败%d次"
			% [level_num, status, elapsed_usec / 1000000.0, reject_count]
		)
	)
