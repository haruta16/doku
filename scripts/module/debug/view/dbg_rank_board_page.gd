## 排行榜进度调试页：编辑一天内的胜利与打开事件，比较不同实验组的小时分布。
extends UIFrameWindow

const _RANK_CELL: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")
const SIM_SCRIPT := preload("res://scripts/module/robot/simulation/robot_sim.gd")
const HOUR_CELL := preload("res://scripts/module/debug/ui/dbg_sim_hour_cell.tscn")

const WIN_GAIN_MAX: int = 3

const HOURS: int = 24

const STALK_SUFFIX: String = "[陪]"

const STOPPED_SUFFIX: String = "[陪·停]"

const GROUPS: Array = [
	{"name": "0 对照", "args": [false, false, false]},
	{"name": "1 dt回退", "args": [true, false, false]},
	{"name": "2 预设分", "args": [false, true, false]},
	{"name": "3 可超车", "args": [false, false, true]},
	{"name": "4 = 2+3", "args": [false, true, true]},
]

const SCENARIOS: Array = [
	{
		"name": "A 打到破水位后离线 8h",
		"segs":
		[
			{"wins": 26, "from": 15.0, "to": 175.0},
			{"open": 185.0},
			{"open": 600.0},
			{"wins": 8, "from": 615.0, "to": 700.0},
			{"open": 1400.0},
		],
	},
	{
		"name": "B Active 全天 45 局",
		"segs":
		[
			{"wins": 12, "from": 20.0, "to": 160.0},
			{"open": 170.0},
			{"wins": 12, "from": 240.0, "to": 400.0},
			{"open": 410.0},
			{"wins": 12, "from": 500.0, "to": 700.0},
			{"open": 710.0},
			{"wins": 9, "from": 850.0, "to": 1300.0},
			{"open": 1420.0},
		],
	},
	{
		"name": "C Rush 2h 40 局",
		"segs":
		[
			{"wins": 40, "from": 5.0, "to": 120.0},
			{"open": 130.0},
			{"open": 700.0},
			{"open": 1400.0},
		],
	},
	{
		"name": "D Quick 3 局就走",
		"segs":
		[
			{"wins": 3, "from": 40.0, "to": 60.0},
			{"open": 65.0},
			{"open": 700.0},
			{"open": 1400.0},
		],
	},
	{
		"name": "E 破水位后挂机 只看榜不打关",
		"segs":
		[
			{"wins": 35, "from": 10.0, "to": 90.0},
			{"open": 100.0},
			{"open": 200.0},
			{"open": 320.0},
			{"open": 450.0},
			{"open": 600.0},
			{"open": 760.0},
			{"open": 900.0},
			{"open": 1050.0},
			{"open": 1200.0},
			{"open": 1330.0},
			{"open": 1420.0},
		],
	},
	{
		"name": "F 冲上天花板 120 局",
		"segs":
		[
			{"wins": 60, "from": 10.0, "to": 400.0},
			{"open": 410.0},
			{"wins": 60, "from": 420.0, "to": 900.0},
			{"open": 910.0},
			{"open": 1400.0},
		],
	},
	{
		"name": "G 临界 28 局(多半不破水位)",
		"segs":
		[
			{"wins": 14, "from": 30.0, "to": 300.0},
			{"open": 310.0},
			{"wins": 14, "from": 600.0, "to": 1000.0},
			{"open": 1010.0},
			{"open": 1400.0},
		],
	},
	{
		"name": "I 隔夜回来 先看榜再打一局",
		"segs":
		[
			{"wins": 35, "from": 10.0, "to": 90.0},
			{"open": 1200.0},
			{"wins": 1, "from": 1202.0, "to": 1202.0},
			{"open": 1203.0},
			{"wins": 1, "from": 1205.0, "to": 1205.0},
			{"open": 1206.0},
		],
	},
	{
		"name": "H 真人节奏 每4h打6局",
		"segs":
		[
			{"wins": 6, "from": 60.0, "to": 90.0},
			{"wins": 6, "from": 300.0, "to": 340.0},
			{"open": 350.0},
			{"wins": 6, "from": 540.0, "to": 580.0},
			{"wins": 6, "from": 780.0, "to": 820.0},
			{"open": 830.0},
			{"wins": 6, "from": 1020.0, "to": 1060.0},
			{"wins": 6, "from": 1260.0, "to": 1300.0},
			{"open": 1400.0},
		],
	},
]

const PREV_PRESETS: Array = [[60, 5], [200, 1], [120, 20], [30, 45], [0, 0]]

@onready var _scroll: ScrollContainer = $MainVBox/ListGroup/ScrollList
@onready var _row_list: VBoxContainer = $MainVBox/ListGroup/ScrollList/RankMargin/RowList
@onready var _title_label: Label = $MainVBox/TopBar/Countdown/Countdown/CountdownText
@onready var _header: BackAndSettingHeader = $MainVBox/TopBar/Header
@onready var _list_group: Control = $MainVBox/ListGroup
@onready var _podium_area: Control = $MainVBox/PodiumArea
@onready var _float_row: Control = $FloatRow
@onready var _anim: AnimationPlayer = $AnimationPlayer

@onready var _case_btn: Button = $MainVBox/SimPanel/SimBox/ParamRow/CaseBtn
@onready var _prev_btn: Button = $MainVBox/SimPanel/SimBox/ParamRow/PrevBtn
@onready var _seed_btn: Button = $MainVBox/SimPanel/SimBox/ParamRow/SeedBtn
@onready var _status: Label = $MainVBox/SimPanel/SimBox/Status
@onready var _node_row: HFlowContainer = $MainVBox/SimPanel/SimBox/NodeRow
@onready var _time_edit: LineEdit = $MainVBox/SimPanel/SimBox/CustomRow/TimeEdit
@onready var _group_btns: Array[Button] = [
	$MainVBox/SimPanel/SimBox/GroupBox/G0,
	$MainVBox/SimPanel/SimBox/GroupBox/G1,
	$MainVBox/SimPanel/SimBox/GroupBox/G2,
	$MainVBox/SimPanel/SimBox/GroupBox/G3,
	$MainVBox/SimPanel/SimBox/GroupBox/G4,
]

var _scenario_idx: int = 0

var _work_segs: Array = []

var _custom_n: int = 0
var _prev_idx: int = 0
var _rng_seed: int = 20260825
var _node_idx: int = -1
var _group_idx: int = 3

var _sims: Array = []
var _keys: Array = []
var _ops: Array = []
var _nodes: Array = []
var _hour_cells: Array = []
var _cells: Array = []


func on_create() -> void:
	_header.register_back_btn(_on_close)
	_header.register_setting_btn(_on_close)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_reset_work_segs()
	_sync_param_texts()


func on_show(_params: Dictionary = {}) -> void:
	ScrollDragHelper.attach(_scroll, true).elastic_max_overscroll = 0.0
	_podium_area.visible = false
	_float_row.visible = false
	var cta: Node = get_node_or_null("MainVBox/CtaBtn")
	if cta != null:
		(cta as CanvasItem).visible = false

	_status.add_theme_color_override("font_color", Color(0.22, 0.16, 0.08))
	_list_group.modulate = Color(1, 1, 1, 1)
	AnimUtil.play(_anim, &"Appear")
	if _sims.is_empty():
		_run_all()
	else:
		_refresh_all()


func on_hide() -> void:
	_clear_cells()


func _on_close() -> void:
	UIManager.hide_ui(UiName.DBG_RANK_BOARD)


func _on_cta_pressed() -> void:
	_on_close()


func on_escape() -> bool:
	_on_close()
	return true


func _on_case_pressed() -> void:
	_scenario_idx = (_scenario_idx + 1) % SCENARIOS.size()
	_reset_work_segs()
	_sync_param_texts()
	_run_all()


func _reset_work_segs() -> void:
	_work_segs = (SCENARIOS[_scenario_idx]["segs"] as Array).duplicate(true)
	_custom_n = 0


func _parse_minute(txt: String) -> float:
	var t: String = txt.strip_edges()
	if t == "":
		return -1.0
	if t.contains(":"):
		var parts: PackedStringArray = t.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return -1.0
		if int(parts[1]) < 0 or int(parts[1]) > 59:
			return -1.0
		var m: float = float(int(parts[0]) * 60 + int(parts[1]))
		return m if m >= 0.0 and m <= 1440.0 else -1.0
	if not t.is_valid_float():
		return -1.0
	var v: float = float(t)
	return v if v >= 0.0 and v <= 1440.0 else -1.0


func _on_add_win_pressed() -> void:
	_add_custom_node(true)


func _on_add_open_pressed() -> void:
	_add_custom_node(false)


func _on_reset_custom_pressed() -> void:
	_reset_work_segs()
	_run_all()


func _add_custom_node(is_win: bool) -> void:
	var m: float = _parse_minute(_time_edit.text)
	if m < 0.0:
		Toast.popup("时间无效，填 08:00 或 480", self)
		return
	if is_win:
		_work_segs.append({"wins": 1, "from": m, "to": m})
	else:
		_work_segs.append({"open": m})
	_custom_n += 1
	_run_all()


func _on_prev_pressed() -> void:
	_prev_idx = (_prev_idx + 1) % PREV_PRESETS.size()
	_sync_param_texts()
	_run_all()


func _on_seed_pressed() -> void:
	_rng_seed = randi() % 99999999
	_sync_param_texts()
	_run_all()


func _on_group0_pressed() -> void:
	_select_group(0)


func _on_group1_pressed() -> void:
	_select_group(1)


func _on_group2_pressed() -> void:
	_select_group(2)


func _on_group3_pressed() -> void:
	_select_group(3)


func _on_group4_pressed() -> void:
	_select_group(4)


func _select_group(gi: int) -> void:
	_group_idx = gi
	_refresh_all()


func _sync_param_texts() -> void:
	_case_btn.text = "Case: %s >" % SCENARIOS[_scenario_idx]["name"]
	_prev_btn.text = (
		"上期: %d分/第%d名 >" % [int(PREV_PRESETS[_prev_idx][0]), int(PREV_PRESETS[_prev_idx][1])]
	)
	_seed_btn.text = "seed: %d" % _rng_seed


func _expand_scenario() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	var ops: Array = []
	var total: int = 0
	for seg: Dictionary in _work_segs:
		if seg.has("open"):
			ops.append({"min": float(seg["open"]), "open": true})
			continue
		var n: int = int(seg["wins"])
		var t1: float = float(seg["from"])
		var t2: float = float(seg["to"])
		for i in range(n):
			var gain: int = rng.randi_range(1, WIN_GAIN_MAX)
			total += gain
			var f: float = 0.0 if n <= 1 else float(i) / float(n - 1)
			ops.append({"min": t1 + (t2 - t1) * f, "win": total, "gain": gain})
	ops.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["min"]) < float(b["min"])
	)

	var run: int = 0
	for op: Dictionary in ops:
		if op.has("win"):
			run += int(op["gain"])
			op["win"] = run
	return ops


func _run_all() -> void:
	for s in _sims:
		if s != null and is_instance_valid(s):
			s.free()
	_sims = []
	_keys = []
	_ops = _expand_scenario()
	var ps: int = int(PREV_PRESETS[_prev_idx][0])
	var pr: int = int(PREV_PRESETS[_prev_idx][1])

	for g: Dictionary in GROUPS:
		var a: Array = g["args"]
		var sim = SIM_SCRIPT.new()
		sim.begin(_rng_seed)
		var cfg: RobotConfig = RankActivityConfig.build_robot_config_for(
			bool(a[0]), bool(a[1]), bool(a[2])
		)
		var key: String = sim.open_period(cfg, ps, pr)
		var cur: int = 0
		for op: Dictionary in _ops:
			sim.at_minute(key, float(op["min"]))
			if op.has("win"):
				cur = int(op["win"])
				sim.player_win(key, cur)
			if op.has("open"):
				sim.open_board(key, cur)
		_sims.append(sim)
		_keys.append(key)

	_rebuild_nodes()

	_node_idx = _nodes.size() - 1
	for i in range(_nodes.size()):
		if str(_nodes[i]["kind"]) == "break":
			_node_idx = i
			break
	_refresh_all()


func _rebuild_nodes() -> void:
	for c in _node_row.get_children():
		c.queue_free()
	_hour_cells = []
	_nodes = []
	if _sims.is_empty():
		return

	var xb: int = int(_sims[0].x_base(_keys[0]))
	var prev_total: int = 0
	for op: Dictionary in _ops:
		var m: float = float(op["min"])
		if op.has("win"):
			var total: int = int(op["win"])
			var gain: int = int(op.get("gain", 0))
			var label: String = "%s 得分 +%d (累计 %d)" % [_hm(m), gain, total]
			var short_label: String = "%s +%d" % [_hm(m), gain]
			var kind: String = "win"
			if prev_total <= xb and total > xb:
				label += " 破水位线"
				short_label += " 破"
				kind = "break"
			prev_total = total
			_nodes.append(
				{"min": m, "label": label, "kind": kind, "total": total, "short_label": short_label}
			)
		else:
			_nodes.append(
				{
					"min": m,
					"label": "%s 打开榜单" % _hm(m),
					"kind": "open",
					"total": prev_total,
					"short_label": "%s 看榜" % _hm(m)
				}
			)

	var buckets: Array = []
	for h in range(HOURS):
		buckets.append([])
	for i in range(_nodes.size()):
		var h: int = clampi(int(float(_nodes[i]["min"]) / 60.0), 0, HOURS - 1)
		(buckets[h] as Array).append(i)

	var running_total: int = 0
	for h in range(HOURS):
		var idxs: Array = buckets[h]
		var wins: int = 0
		var opens: int = 0
		var has_break: bool = false
		for i: int in idxs:
			match str(_nodes[i]["kind"]):
				"open":
					opens += 1
				"break":
					wins += 1
					has_break = true
				_:
					wins += 1
			running_total = int(_nodes[i]["total"])

		if idxs.is_empty():
			continue
		var cell: HBoxContainer = HOUR_CELL.instantiate()
		var title: Label = cell.get_node("Body/Title")
		var seg: OptionButton = cell.get_node("Body/Seg")
		var gap: Label = cell.get_node("Gap")
		title.text = "%02d 打%d看%d" % [h, wins, opens]

		if has_break:
			title.text += " 破"
			title.add_theme_color_override("font_color", Color(0.75, 0.15, 0.05))
		else:
			title.add_theme_color_override("font_color", Color(0.25, 0.18, 0.1))
		gap.text = "%d分" % running_total
		gap.add_theme_color_override("font_color", Color(0.55, 0.35, 0.0))
		seg.clear()
		for i: int in idxs:
			seg.add_item(str(_nodes[i]["short_label"]))
			seg.set_item_metadata(seg.item_count - 1, i)

		seg.get_popup().index_pressed.connect(
			func(sel: int) -> void:
				_node_idx = int(seg.get_item_metadata(sel))
				_refresh_all()
		)
		_node_row.add_child(cell)
		_hour_cells.append(cell)


func _sync_hour_selection() -> void:
	if _node_idx < 0 or _node_idx >= _nodes.size():
		return
	for cell in _hour_cells:
		var seg: OptionButton = (cell as HBoxContainer).get_node("Body/Seg")
		var owns: bool = false
		for k in range(seg.item_count):
			if int(seg.get_item_metadata(k)) == _node_idx:
				seg.select(k)
				owns = true
				break

		seg.add_theme_color_override(
			"font_color", Color(0.85, 0.45, 0.0) if owns else Color(0.3, 0.3, 0.32, 0.65)
		)


func _refresh_all() -> void:
	if _sims.is_empty() or _node_idx < 0 or _node_idx >= _nodes.size():
		return
	var m: float = float(_nodes[_node_idx]["min"])
	var cfg: RobotConfig = (_sims[_group_idx]._pools[_keys[_group_idx]] as RobotPool).config

	var extra: String = ("   自定义+%d" % _custom_n) if _custom_n > 0 else ""
	_status.text = (
		"水位%d 天花板%d 共%d局%s   选中: %s"
		% [
			int(_sims[_group_idx].x_base(_keys[_group_idx])),
			cfg.ceiling,
			_count_wins(),
			extra,
			str(_nodes[_node_idx]["label"])
		]
	)
	_title_label.text = "G%d %s" % [_group_idx, _hm(m)]
	_sync_hour_selection()
	_refresh_group_btns(m)
	_rebuild_board(m)


func _count_wins() -> int:
	var n: int = 0
	for op: Dictionary in _ops:
		if op.has("win"):
			n += 1
	return n


func _refresh_group_btns(minute: float) -> void:
	for i in range(_group_btns.size()):
		var sim = _sims[i]
		var key: String = _keys[i]
		var board: Array = sim.peek_board(key, minute)
		var pr: int = sim.peek_player_rank(key, minute)
		var pa: Dictionary = sim.player_at(minute)
		var top: Array = []
		for e: Dictionary in board:
			if not bool(e.get("is_player", false)) and top.size() < 3:
				top.append(str(int(e["score"])))
		var mem: Array = sim.members_at(minute)
		var mark: String = ">" if i == _group_idx else " "
		_group_btns[i].text = (
			"%s %s  玩家%d分/第%d名  前3: %s  陪伴%s"
			% [
				mark,
				GROUPS[i]["name"],
				int(pa["score"]),
				pr,
				"/".join(top),
				("%d只" % mem.size()) if not mem.is_empty() else "-"
			]
		)
		_group_btns[i].add_theme_color_override(
			"font_color", Color(0.85, 0.45, 0.0) if i == _group_idx else Color(0.2, 0.2, 0.22)
		)


func _rebuild_board(minute: float) -> void:
	_clear_cells()
	var rows: Array = _sims[_group_idx].peek_rank_list(
		_keys[_group_idx],
		minute,
		ProfileService.get_player_info(),
		[],
		STALK_SUFFIX,
		STOPPED_SUFFIX
	)
	for info in rows:
		if info == null:
			continue
		var cell = create_child(_RANK_CELL, {})
		var cur: Node = cell.get_parent()
		if cur != null:
			cur.remove_child(cell)
		_row_list.add_child(cell)
		cell.apply_score_icon()
		cell.set_show_chest(true)
		var pinfo: PlayerInfo = info.player_info
		cell.set_player(pinfo)
		cell.set_entry(
			info.rank, info.is_self(), pinfo.nickname if pinfo != null else "", info.score
		)
		cell.show_static()
		_cells.append(cell)
	_scroll.scroll_vertical = 0


func _clear_cells() -> void:
	for c in _cells:
		if is_instance_valid(c):
			destroy_child(c)
	_cells = []


static func _hm(minute: float) -> String:
	var mi: int = int(round(minute))
	return "%02d:%02d" % [mi / 60, mi % 60]
