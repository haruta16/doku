## 游戏日志页签：读取内存日志缓冲，提供显示、筛选与清理入口。
class_name CheatTabLog
extends CheatTabBase

var _filter_state: Dictionary = {
	"show_info": true, "show_warn": true, "show_error": true, "keyword": ""
}


func title() -> String:
	return "日志"


func build(content: ScrollContainer, _panel: CheatPanel) -> void:
	var buf: InGameLogBuffer = InGameLogBuffer.instance
	if buf == null:
		var hint := Label.new()
		hint.text = "InGameLogBuffer 未初始化"
		hint.add_theme_font_size_override("font_size", 40)
		content.add_child(hint)
		return

	content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	content.add_child(vbox)

	var state: Dictionary = _filter_state

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 16)
	vbox.add_child(toolbar)

	var make_toggle := func(label: String, key: String, color: Color) -> Button:
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.button_pressed = state[key]
		btn.custom_minimum_size = Vector2(0, 90)
		btn.add_theme_font_size_override("font_size", 40)
		btn.add_theme_color_override("font_pressed_color", color)
		return btn

	toolbar.add_child(make_toggle.call("Log", "show_info", Color.WHITE))
	toolbar.add_child(make_toggle.call("Warn", "show_warn", Color.YELLOW))
	toolbar.add_child(make_toggle.call("Error", "show_error", Color.RED))

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size = Vector2(0, 90)
	clear_btn.add_theme_font_size_override("font_size", 40)
	toolbar.add_child(clear_btn)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 16)
	vbox.add_child(filter_row)

	var filter_input := LineEdit.new()
	filter_input.placeholder_text = "关键词过滤..."
	filter_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_input.custom_minimum_size = Vector2(0, 90)
	filter_input.add_theme_font_size_override("font_size", 38)
	filter_input.text = state.keyword
	filter_row.add_child(filter_input)

	var log_label := RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 32)
	log_label.add_theme_font_size_override("mono_font_size", 32)
	vbox.add_child(log_label)

	const _LOG_ENTRY_MAX_CHARS: int = 1200

	var render_log := func() -> void:
		var entries: Array[Dictionary] = buf.get_entries()
		var lines: PackedStringArray = []
		var kw: String = state.keyword
		for e in entries:
			var lv: int = e.level
			if lv == InGameLogBuffer.Level.INFO and not state.show_info:
				continue
			if lv == InGameLogBuffer.Level.WARN and not state.show_warn:
				continue
			if lv == InGameLogBuffer.Level.ERROR and not state.show_error:
				continue
			var text: String = e.text
			if not kw.is_empty() and text.findn(kw) == -1:
				continue
			var sec: float = e.time_ms * 0.001
			var prefix: String = "%.1f|" % sec
			if text.length() > _LOG_ENTRY_MAX_CHARS:
				text = text.left(_LOG_ENTRY_MAX_CHARS) + "..."
			var escaped: String = text.replace("[", "[lb]")
			match lv:
				InGameLogBuffer.Level.ERROR:
					lines.append("[color=red]%s%s[/color]" % [prefix, escaped])
				InGameLogBuffer.Level.WARN:
					lines.append("[color=yellow]%s%s[/color]" % [prefix, escaped])
				_:
					lines.append(prefix + escaped)
		log_label.text = "\n".join(lines) if not lines.is_empty() else "[color=gray]（暂无日志）[/color]"

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(func() -> void: render_log.call())
	vbox.add_child(timer)

	for btn in toolbar.get_children():
		if btn is Button and btn.toggle_mode:
			var key: String = ""
			if btn.text == "Log":
				key = "show_info"
			elif btn.text == "Warn":
				key = "show_warn"
			elif btn.text == "Error":
				key = "show_error"
			if not key.is_empty():
				btn.toggled.connect(
					func(on: bool, k: String = key) -> void:
						state[k] = on
						render_log.call()
				)
	clear_btn.pressed.connect(
		func() -> void:
			buf.clear_entries()
			render_log.call()
	)
	filter_input.text_changed.connect(
		func(new_text: String) -> void:
			state.keyword = new_text.strip_edges()
			render_log.call()
	)

	render_log.call()
