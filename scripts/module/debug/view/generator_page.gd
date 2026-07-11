class_name GeneratorPage
extends UIFrameWindow

var _board_size: int = 8
var _min_region: int = -1
var _strip_num: int = -1

var _size_label: Label = null
var _min_region_label: Label = null
var _strip_num_label: Label = null
var _status_label: Label = null

const _FS_HINT: int = 33
const _FS_BTN: int = 33
const _FS_BIG: int = 88


func _ready() -> void:
	_build_ui()


func _label_val(v: int) -> String:
	return "不限" if v == -1 else str(v)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.961, 0.941, 1.0, 1.0)
	add_child(bg)

	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(1.0, 1.0, 1.0, 0.95)
	header_style.border_width_bottom = 1
	header_style.border_color = Color(0.886, 0.91, 0.941, 0.5)

	var header := PanelContainer.new()
	header.z_index = 10
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 194.0
	header.add_theme_stylebox_override("panel", header_style)
	add_child(header)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)
	header.add_child(hbox)

	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0, 0, 0, 0)
	back_style.content_margin_left = 22.0
	back_style.content_margin_right = 22.0

	var back_btn := Button.new()
	back_btn.custom_minimum_size = Vector2(200, 0)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_color_override("font_color", Color(0.388, 0.4, 0.945, 1))
	back_btn.add_theme_font_size_override("font_size", 41)
	back_btn.add_theme_stylebox_override("normal", back_style)
	back_btn.add_theme_stylebox_override("pressed", back_style)
	back_btn.add_theme_stylebox_override("hover", back_style)
	back_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back_btn.text = "← 返回"
	back_btn.pressed.connect(_on_back_pressed)
	hbox.add_child(back_btn)

	var title_lbl := Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color(0.118, 0.106, 0.294, 1))
	title_lbl.add_theme_font_size_override("font_size", 39)
	title_lbl.text = "关卡生成器"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(title_lbl)

	var right_spacer := Control.new()
	right_spacer.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(right_spacer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 194.0
	center.offset_bottom = -80.0
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 50)
	center.add_child(vbox)

	vbox.add_child(_make_hint_label("棋盘尺寸"))

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 44)
	row1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row1)

	row1.add_child(_make_stepper_btn("−", func() -> void:
		_board_size = max(4, _board_size - 1)
		_size_label.text = str(_board_size)
		if _min_region > _board_size:
			_min_region = _board_size; _min_region_label.text = _label_val(_min_region)
		if _strip_num >= _board_size:
			_strip_num = _board_size - 1; _strip_num_label.text = _label_val(_strip_num)
	))

	_size_label = Label.new()
	_size_label.text = str(_board_size)
	_size_label.add_theme_font_size_override("font_size", _FS_BIG)
	_size_label.add_theme_color_override("font_color", Color(0.118, 0.106, 0.294, 1))
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_label.custom_minimum_size = Vector2(180, 0)
	row1.add_child(_size_label)

	row1.add_child(_make_stepper_btn("+", func() -> void:
		_board_size = min(10, _board_size + 1)
		_size_label.text = str(_board_size)
	))

	vbox.add_child(_make_hint_label("最小区域面积"))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 44)
	row2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row2)

	row2.add_child(_make_stepper_btn("−", func() -> void:
		if _min_region == -1:
			_min_region = _board_size
		elif _min_region <= 1:
			_min_region = -1
		else:
			_min_region -= 1
		_min_region_label.text = _label_val(_min_region)
	))

	_min_region_label = Label.new()
	_min_region_label.text = _label_val(_min_region)
	_min_region_label.add_theme_font_size_override("font_size", _FS_BIG)
	_min_region_label.add_theme_color_override("font_color", Color(0.118, 0.106, 0.294, 1))
	_min_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_min_region_label.custom_minimum_size = Vector2(240, 0)
	row2.add_child(_min_region_label)

	row2.add_child(_make_stepper_btn("+", func() -> void:
		if _min_region == -1:
			_min_region = 1
		elif _min_region >= _board_size:
			_min_region = -1
		else:
			_min_region += 1
		_min_region_label.text = _label_val(_min_region)
	))

	vbox.add_child(_make_hint_label("单行列区域数量"))

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 44)
	row3.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row3)

	row3.add_child(_make_stepper_btn("−", func() -> void:
		if _strip_num == -1:
			_strip_num = _board_size - 1
		elif _strip_num <= 0:
			_strip_num = -1
		else:
			_strip_num -= 1
		_strip_num_label.text = _label_val(_strip_num)
	))

	_strip_num_label = Label.new()
	_strip_num_label.text = _label_val(_strip_num)
	_strip_num_label.add_theme_font_size_override("font_size", _FS_BIG)
	_strip_num_label.add_theme_color_override("font_color", Color(0.118, 0.106, 0.294, 1))
	_strip_num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip_num_label.custom_minimum_size = Vector2(240, 0)
	row3.add_child(_strip_num_label)

	row3.add_child(_make_stepper_btn("+", func() -> void:
		if _strip_num == -1:
			_strip_num = 0
		elif _strip_num >= _board_size - 1:
			_strip_num = -1
		else:
			_strip_num += 1
		_strip_num_label.text = _label_val(_strip_num)
	))

	var gen_btn := _make_action_btn("生成关卡", Color(0.388, 0.4, 0.945, 1))
	gen_btn.pressed.connect(_on_generate_pressed)
	vbox.add_child(gen_btn)

	var strat_btn := _make_action_btn("按策略生成关卡", Color(0.937, 0.62, 0.043, 1))
	strat_btn.pressed.connect(_on_generate_by_strategy_pressed)
	vbox.add_child(strat_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(700, 0)
	vbox.add_child(_status_label)


func _make_hint_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _FS_HINT)
	lbl.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _make_stepper_btn(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(110, 110)
	btn.add_theme_font_size_override("font_size", 55)
	btn.add_theme_color_override("font_color", Color(0.278, 0.341, 0.424))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.886, 0.91, 0.941, 1.0)
	s.corner_radius_top_left = 55
	s.corner_radius_top_right = 55
	s.corner_radius_bottom_right = 55
	s.corner_radius_bottom_left = 55
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(callback)
	return btn


func _make_action_btn(label_text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", _FS_BTN)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.custom_minimum_size = Vector2(600, 0)
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left = 22
	s.corner_radius_top_right = 22
	s.corner_radius_bottom_right = 22
	s.corner_radius_bottom_left = 22
	s.content_margin_top = 28
	s.content_margin_bottom = 28
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return btn


func _on_back_pressed() -> void:
	UIManager.show_ui(UiName.DEBUG)


func _on_generate_pressed() -> void:
	_set_status("生成中...", Color(0.388, 0.4, 0.945))
	await get_tree().process_frame
	_do_generate(false)


func _on_generate_by_strategy_pressed() -> void:
	_set_status("按策略生成中...", Color(0.937, 0.62, 0.043))
	await get_tree().process_frame
	_do_generate(true)


func _do_generate(by_strategy: bool) -> void:
	var seed_val: int = Time.get_ticks_msec() % 100000
	var min_rs: int = max(0, _min_region)
	var strip_c: int = _strip_num

	var config: Dictionary = {
		"size": _board_size,
		"seed": seed_val,
		"min_region_size": min_rs,
		"strip_count": strip_c,
		"max_attempts": 300,
	}

	if by_strategy:
		config["strip_count"] = _board_size - 1

	var result: Dictionary = LevelGeneratorEditor.generate_solvable_puzzle(config)

	if result.is_empty():
		var hint: String = "生成失败，请尝试："
		if min_rs >= 4:
			hint += "降低最小区域面积、"
		if strip_c >= 0 and strip_c < _board_size - 2:
			hint += "增加单行列数量、"
		hint += "或点击重试"
		_set_status(hint, Color(0.929, 0.267, 0.267))
		return

	var solution_1d: Array = []
	for r: int in range(_board_size):
		for c: int in range(_board_size):
			if result["solution"][r][c]:
				solution_1d.append(c)
				break

	_set_status("", Color(0.392, 0.455, 0.545))
	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"bank_mode": true,
				"bank_size": _board_size,
				"bank_rank": 0,
				"bank_index": 0,
				"prebuilt_regions": result["regions"],
				"prebuilt_solution": solution_1d,
				"level_seed": result.get("seed", seed_val),
			}
		)
	)


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
