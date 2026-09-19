# 对局记录器：静态数组按开局顺序记下 puzzle_id，供作弊面板「题库」页查重（同 id 出现两次就标红）
class_name PuzzleSessionTracker
extends RefCounted

# ---- 静态状态（全进程共享，不随实例销毁） ----
static var _entries: Array[Dictionary] = [] # 记录 [{level, puzzle_id}]，追加顺序即开局顺序
static var _label: RichTextLabel = null # 作弊面板里的富文本框；面板没打开时为 null


# 记一局：由 game_page / daily_game_page 开局时调用；level=0 表示每日关
static func record(puzzle_id: String, level: int = 0) -> void:
	_entries.append({"level": level, "puzzle_id": puzzle_id})
	_refresh()


# 构建作弊面板的「题库」页：建一个富文本框，挂上拖动滚动后立即刷新
static func build_cheat_tab(content: ScrollContainer) -> void:
	ScrollDragHelper.attach(content) # 挂上拖动滚动（面板里没有滚动条）
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 让 vbox 撑满宽度
	content.add_child(vbox)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true # 文本里用 [color=...] 标签标红
	_label.fit_content = true
	_label.scroll_active = false # 滚动交给外层 ScrollContainer
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("normal_font_size", 36) # 字号 36 像素
	vbox.add_child(_label)
	_refresh()


# 按当前记录重刷文本；同一 puzzle_id 出现多次的行整行标红
static func _refresh() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if _entries.is_empty():
		_label.text = "[color=gray]暂无记录（进入关卡后自动记录）[/color]"
		return
	# 先数一遍每个 puzzle_id 出现几次，决定是否标红
	var id_count: Dictionary = {}
	for entry: Dictionary in _entries:
		var pid: String = entry["puzzle_id"]
		id_count[pid] = id_count.get(pid, 0) + 1
	var lines: PackedStringArray = []
	# 再按记录顺序逐行输出关卡号与 id
	for entry: Dictionary in _entries:
		var lv: int = entry["level"]
		var pid: String = entry["puzzle_id"]
		if id_count[pid] > 1:
			lines.append("[color=red]Lv%d : %s[/color]" % [lv, pid])
		else:
			lines.append("Lv%d : %s" % [lv, pid])
	_label.text = "\n".join(lines)
