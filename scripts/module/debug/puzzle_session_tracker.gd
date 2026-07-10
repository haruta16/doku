class_name PuzzleSessionTracker
extends RefCounted





static var _entries: Array[Dictionary] = []
static var _label: RichTextLabel = null

static func record(puzzle_id: String, level: int = 0) -> void :
    _entries.append({"level": level, "puzzle_id": puzzle_id})
    _refresh()

static func build_cheat_tab(content: ScrollContainer) -> void :
    ScrollDragHelper.attach(content)
    var vbox: = VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(vbox)

    _label = RichTextLabel.new()
    _label.bbcode_enabled = true
    _label.fit_content = true
    _label.scroll_active = false
    _label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _label.add_theme_font_size_override("normal_font_size", 36)
    vbox.add_child(_label)
    _refresh()

static func _refresh() -> void :
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
    for entry: Dictionary in _entries:
        var lv: int = entry["level"]
        var pid: String = entry["puzzle_id"]
        if id_count[pid] > 1:
            lines.append("[color=red]Lv%d : %s[/color]" % [lv, pid])
        else:
            lines.append("Lv%d : %s" % [lv, pid])
    _label.text = "\n".join(lines)
