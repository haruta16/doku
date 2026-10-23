## 题目会话追踪器：记录本次运行的题目来源和难度，构建调试展示表。
class_name PuzzleSessionTracker
extends RefCounted

# ---- 静态状态（全进程共享，不随实例销毁） ----
static var _entries: Array[Dictionary] = [] # 记录 [{level, puzzle_id}]，追加顺序即开局顺序
static var _label: RichTextLabel = null # 作弊面板里的富文本框；面板没打开时为 null

const _SOURCE_LABELS: Dictionary = {
	"regular": "Regular",
	"lkstyle": "LKStyle",
	"gc": "GC",
	"lk_mod": "lk_mod",
	"sp": "SP",
	"lk": "lk",
}


static func record(
	puzzle_id: String, level: int = 0, rank: int = 0, source: String = "", is_fotd: bool = false
) -> void:
	(
		_entries
		. append(
			{
				"level": level,
				"puzzle_id": puzzle_id,
				"rank": rank,
				"source": source,
				"is_fotd": is_fotd,
			}
		)
	)
	_refresh()


## 构建作弊面板的「题库」页：建一个富文本框，挂上拖动滚动后立即刷新
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


static func _refresh() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if _entries.is_empty():
		_label.text = "[color=gray]暂无记录（进入关卡后自动记录）[/color]"
		return

	var id_count: Dictionary = {}
	for entry: Dictionary in _entries:
		var pid: String = entry["puzzle_id"]
		id_count[pid] = id_count.get(pid, 0) + 1
	var lines: PackedStringArray = []
	var last_rank: int = 0
	for entry: Dictionary in _entries:
		var lv: int = entry["level"]
		var pid: String = entry["puzzle_id"]
		var rank: int = entry.get("rank", 0)
		var is_fotd: bool = entry.get("is_fotd", false)
		var prev: int = 0 if is_fotd else last_rank
		var line_text: String = (
			"Lv%d : %s%s%s%s"
			% [
				lv,
				pid,
				_rank_tag(rank, prev),
				_source_tag(entry.get("source", "")),
				" [↓First-Of-The-Day]" if is_fotd else "",
			]
		)
		if rank > 0 and not is_fotd:
			last_rank = rank
		if id_count.get(pid, 0) > 1:
			lines.append("[color=red]%s[/color]" % line_text)
		else:
			lines.append(line_text)
	_label.text = "\n".join(lines)


static func _rank_tag(rank: int, prev: int) -> String:
	if rank <= 0:
		return ""
	var arrow: String = ""
	if prev > 0 and rank != prev:
		arrow = "↑" if rank > prev else "↓"
	return " [%sR%d]" % [arrow, rank]


static func _source_tag(source: String) -> String:
	if not _SOURCE_LABELS.has(source):
		return ""
	return " [%s]" % _SOURCE_LABELS[source]
