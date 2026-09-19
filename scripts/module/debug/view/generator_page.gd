# 关卡生成器页：调 LevelGeneratorEditor 现场造一张地图直接送进 GAME 页试玩（入口在 DebugPage 顶部的「✨ 关卡生成器」）
# 只在非 Android 构建里注册（UIRegistry._DEBUG_PAGES）；由 DebugPage 顶部的「✨ 关卡生成器」打开
class_name GeneratorPage
extends UIFrameWindow

# ---- 可调参数（-1 表示「不限」，由加减按钮改） ----
var _board_size: int = 8 # 棋盘边长 4~10，默认 8
var _min_region: int = -1 # 最小区域面积；-1 = 不限
var _strip_num: int = -1 # 单行/单列区域数量；-1 = 不限（当前生成器没有读取它）

# ---- 子节点引用（界面全在 _build_ui 里用代码建，这里只存标签） ----
var _size_label: Label = null # 棋盘尺寸的大号数字
var _min_region_label: Label = null # 最小区域面积的大号数字
var _strip_num_label: Label = null # 区域数量的大号数字
var _status_label: Label = null # 生成中 / 生成失败的提示

# ---- 字号（像素） ----
const _FS_HINT: int = 33 # 提示文字
const _FS_BTN: int = 33 # 按钮文字
const _FS_BIG: int = 88 # 大号数字


# 进场景树就搭界面（本页 .tscn 里只有一个空 Control，没有子节点）
func _ready() -> void:
	_build_ui()


# -1 统一显示成「不限」，其余原样转字符串
func _label_val(v: int) -> String:
	return "不限" if v == -1 else str(v)


# 从零搭出整页：底色 + 顶栏 + 三组「减 / 数字 / 加」+ 两个生成按钮 + 状态文字
func _build_ui() -> void:
	# 淡紫底色，铺满全屏且不吃鼠标事件
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.961, 0.941, 1.0, 1.0)
	add_child(bg)

	# 顶栏样式：白色半透明 + 一条下边框
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(1.0, 1.0, 1.0, 0.95)
	header_style.border_width_bottom = 1
	header_style.border_color = Color(0.886, 0.91, 0.941, 0.5)

	# 顶栏固定在屏幕顶部，高 194 像素
	var header := PanelContainer.new()
	header.z_index = 10
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 194.0
	header.add_theme_stylebox_override("panel", header_style)
	add_child(header)

	# 左返回 + 中标题 + 右侧等宽占位（让标题真居中）
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)
	header.add_child(hbox)

	# 返回按钮做成无色扁平，只留文字
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

	# 主体区域：顶栏之下、底边再留 80 像素，内容整体居中
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 194.0
	center.offset_bottom = -80.0
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 50)
	center.add_child(vbox)

	# 第一组：棋盘尺寸，范围 4~10
	vbox.add_child(_make_hint_label("棋盘尺寸"))

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 44)
	row1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row1)

	# 减：下限 4；顺手把越界的区域面积与区域数量压回合法值
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

	# 加：上限 10
	row1.add_child(_make_stepper_btn("+", func() -> void:
		_board_size = min(10, _board_size + 1)
		_size_label.text = str(_board_size)
	))

	# 第二组：最小区域面积，-1 表示不限
	vbox.add_child(_make_hint_label("最小区域面积"))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 44)
	row2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row2)

	# 减：-1 → 棋盘尺寸 → 逐级减到 1 → 再按一次回 -1
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

	# 加：-1 → 1 → 逐级加到棋盘尺寸 → 再按一次回 -1
	row2.add_child(_make_stepper_btn("+", func() -> void:
		if _min_region == -1:
			_min_region = 1
		elif _min_region >= _board_size:
			_min_region = -1
		else:
			_min_region += 1
		_min_region_label.text = _label_val(_min_region)
	))

	# 第三组：单行/单列的区域数量，-1 表示不限
	vbox.add_child(_make_hint_label("单行列区域数量"))

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 44)
	row3.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(row3)

	# 减：-1 → 尺寸-1 → 减到 0 → 再按一次回 -1
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

	# 加：-1 → 0 → 加到尺寸-1 → 再按一次回 -1
	row3.add_child(_make_stepper_btn("+", func() -> void:
		if _strip_num == -1:
			_strip_num = 0
		elif _strip_num >= _board_size - 1:
			_strip_num = -1
		else:
			_strip_num += 1
		_strip_num_label.text = _label_val(_strip_num)
	))

	# 主按钮：用当前参数加随机种子生成
	var gen_btn := _make_action_btn("生成关卡", Color(0.388, 0.4, 0.945, 1))
	gen_btn.pressed.connect(_on_generate_pressed)
	vbox.add_child(gen_btn)

	# 备选按钮：走「按策略生成」分支
	var strat_btn := _make_action_btn("按策略生成关卡", Color(0.937, 0.62, 0.043, 1))
	strat_btn.pressed.connect(_on_generate_by_strategy_pressed)
	vbox.add_child(strat_btn)

	# 状态标签：显示进度、失败原因与调参建议，可自动换行
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(700, 0)
	vbox.add_child(_status_label)


# 造一个居中的灰色提示标签
func _make_hint_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _FS_HINT)
	lbl.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


# 造一个圆形加减按钮，点击回调由调用方传入
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


# 造一个通栏大按钮（最小宽 600、圆角 22、上下留白 28）
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


# 「← 返回」按钮：回到 DebugPage（本页的按钮都是脚本建的，不走 .tscn 信号连接）
func _on_back_pressed() -> void:
	UIManager.show_ui(UiName.DEBUG)


# 普通生成：先刷状态文字并等一帧让界面重绘，再跑（生成会卡住主线程）
func _on_generate_pressed() -> void:
	_set_status("生成中...", Color(0.388, 0.4, 0.945))
	await get_tree().process_frame # 等一帧，先让「生成中...」画出来
	_do_generate(false)


# 按策略生成：同上，只是走 by_strategy 分支
func _on_generate_by_strategy_pressed() -> void:
	_set_status("按策略生成中...", Color(0.937, 0.62, 0.043))
	await get_tree().process_frame # 同上，先让界面重绘
	_do_generate(true)


# 真正干活：组 config → 调编辑器生成 → 压成一维 solution → 打开 GAME 页试玩
func _do_generate(by_strategy: bool) -> void:
	# 用毫秒时间戳当种子，每次点都不一样
	var seed_val: int = Time.get_ticks_msec() % 100000
	# -1（不限）传给生成器前按 0 处理
	var min_rs: int = max(0, _min_region)
	var strip_c: int = _strip_num

	# 交给 LevelGeneratorEditor.generate_solvable_puzzle 的参数
	var config: Dictionary = {
		"size": _board_size,
		"seed": seed_val,
		"min_region_size": min_rs,
		"strip_count": strip_c,
		"max_attempts": 300,
	}

	# 策略模式：把 strip_count 拉满（当前恢复版生成器只读 size / seed / min_region_size / max_attempts）
	if by_strategy:
		config["strip_count"] = _board_size - 1

	var result: Dictionary = LevelGeneratorEditor.generate_solvable_puzzle(config) # 同步调用，最多尝试 300 次

	# 生成失败：按当前参数给两条最可能有效的建议
	if result.is_empty():
		var hint: String = "生成失败，请尝试："
		if min_rs >= 4:
			hint += "降低最小区域面积、"
		if strip_c >= 0 and strip_c < _board_size - 2:
			hint += "增加单行列数量、"
		hint += "或点击重试"
		_set_status(hint, Color(0.929, 0.267, 0.267))
		return

	# GAME 页要的是「每行猫所在列」的一维数组，从二维 solution 压出来
	var solution_1d: Array = []
	for r: int in range(_board_size):
		for c: int in range(_board_size):
			if result["solution"][r][c]:
				solution_1d.append(c) # 每行只有一只猫，找到就不用再往下扫
				break

	# 清掉状态文字
	_set_status("", Color(0.392, 0.455, 0.545))
	# 用 bank_mode 加 prebuilt_* 的形式把生成结果直接开局
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


# 更新状态标签的文字与颜色（具体语义色由调用方决定）
func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
