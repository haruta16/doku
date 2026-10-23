## 运行信息页签：汇总版本、活跃天数、用户标识与实验状态，支持复制诊断信息。
class_name CheatTabInfo
extends CheatTabBase

const RemoteConsoleAccess: GDScript = preload("res://scripts/module/cheat/remote_console_access.gd")

const _NAME_COL_W: float = 320.0
const _FONT_SIZE: int = 38


func title() -> String:
	return "信息"


func build(content: ScrollContainer, panel: CheatPanel) -> void:
	ScrollDragHelper.attach(content)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	content.add_child(vbox)

	var rows: Array = []

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 16)
	vbox.add_child(toolbar)

	_add_group(vbox, "版本")
	_add_row(
		vbox,
		rows,
		panel,
		"versionName",
		func() -> String: return _or_na(UniKitManager.get_version_name(), "(未获取)"),
		false
	)
	_add_row(
		vbox,
		rows,
		panel,
		"versionCode",
		func() -> String:
			var code: int = UniKitManager.get_version_code()
			return str(code) if code > 0 else "0（非 Android 恒 0）",
		false
	)
	_add_row(
		vbox,
		rows,
		panel,
		"安装版本",
		func() -> String: return _or_na(GameState.get_install_version(), "(未记录)"),
		false
	)

	_add_group(vbox, "天数")
	_add_row(
		vbox,
		rows,
		panel,
		"活跃天数",
		func() -> String: return "%d 天" % GameState.get_active_days(),
		false
	)
	_add_row(
		vbox,
		rows,
		panel,
		"安装天数",
		func() -> String:
			var days: int = ABTestManager.living_days.days_since_first_open()
			return "%d 天" % days if days >= 0 else "(未知，拿不到首启时间)",
		false
	)

	_add_group(vbox, "标识")
	_add_row(
		vbox, rows, panel, "luid", func() -> String: return _or_na(UniKitManager.get_luid()), true
	)
	_add_row(
		vbox, rows, panel, "uuid", func() -> String: return _or_na(UniKitManager.get_uuid()), true
	)
	_add_row(
		vbox,
		rows,
		panel,
		"device_id",
		func() -> String: return _or_na(AuthManager.get_device_id()),
		true
	)

	_add_group(vbox, "AB")
	_add_row(
		vbox,
		rows,
		panel,
		"getDyeingTag",
		func() -> String: return _or_na(ABTestManager.get_ab_dyeing_tag(), "(空)"),
		true
	)
	_add_row(
		vbox,
		rows,
		panel,
		"getAllTag",
		func() -> String: return _or_na(ABTestManager.get_ab_all_tag(), "(空)"),
		true
	)
	_add_group(vbox, "远端")
	_add_row(
		vbox, rows, panel, "远程控制台", func() -> String: return RemoteConsoleAccess.status_text(), true
	)

	var refresh_btn := _make_tool_button("刷新")
	refresh_btn.pressed.connect(
		func() -> void:
			for r: Dictionary in rows:
				(r.node as Label).text = (r.getter as Callable).call()
	)
	toolbar.add_child(refresh_btn)

	var copy_all_btn := _make_tool_button("全部复制")
	copy_all_btn.pressed.connect(
		func() -> void:
			var lines: PackedStringArray = []
			for r: Dictionary in rows:
				lines.append("%s: %s" % [r.name, (r.getter as Callable).call()])
			DisplayServer.clipboard_set("\n".join(lines))
			Toast.popup("已复制 %d 项信息" % rows.size(), panel)
	)
	toolbar.add_child(copy_all_btn)


func _make_tool_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 90)
	btn.add_theme_font_size_override("font_size", 40)
	return btn


func _add_group(parent: VBoxContainer, name: String) -> void:
	var lab := Label.new()
	lab.text = "【%s】" % name
	lab.add_theme_font_size_override("font_size", 40)
	lab.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	parent.add_child(lab)


func _add_row(
	parent: VBoxContainer,
	rows: Array,
	panel: CheatPanel,
	name: String,
	getter: Callable,
	copyable: bool
) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_lab := Label.new()
	name_lab.text = name
	name_lab.custom_minimum_size = Vector2(_NAME_COL_W, 0)
	name_lab.add_theme_font_size_override("font_size", _FONT_SIZE)
	name_lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	row.add_child(name_lab)

	var value_lab := Label.new()
	value_lab.text = getter.call()
	value_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_lab.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	value_lab.add_theme_font_size_override("font_size", _FONT_SIZE)
	row.add_child(value_lab)

	if copyable:
		var copy_btn := Button.new()
		copy_btn.text = "复制"
		copy_btn.custom_minimum_size = Vector2(140, 80)
		copy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		copy_btn.add_theme_font_size_override("font_size", 34)
		copy_btn.pressed.connect(
			func() -> void:
				var v: String = getter.call()
				DisplayServer.clipboard_set(v)
				Toast.popup("%s: %s（已复制）" % [name, v], panel)
		)
		row.add_child(copy_btn)

	rows.append({"name": name, "node": value_lab, "getter": getter})


func _or_na(v: String, na: String = "(不可用，当前平台无此能力)") -> String:
	return v if not v.is_empty() else na
