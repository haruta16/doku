# 调试页总目录：把「解题技巧 / V3 尺寸示例 / R1-R5 策略」排成卡片列表，点「体验」带调试参数直接进 GAME 页
# 只在非 Android 构建里注册（UIRegistry._DEBUG_PAGES）；脚本内没有别的调用点，只有 GeneratorPage 的返回按钮会回到本页
class_name DebugPage
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _content_vbox: VBoxContainer = $ScrollContainer/ContentVBox # 卡片都塞进这个纵向容器（子节点全部由脚本创建）

# ---- 卡片数据：解题技巧（config 为 null 表示暂无对应关卡，卡片置灰） ----
# 每项含 label 标题 / level 徽章 / desc 说明 / config（作为 GAME 页的 debug_config）
const TECHNIQUE_ENTRIES: Array[Dictionary] = [
	{"label": "整行整列交叉", "level": "L1", "desc": "整行+整列同色 → 交叉点放猫", "config": null},
	{
		"label": "唯一候选",
		"level": "L1",
		"desc": "区域/行/列仅剩1个可放位 → 直接放置",
		"config": {"size": 6, "seed": 5, "version": 3, "v3_attempt": 11, "label": "D-Naked"}
	},
	{
		"label": "区域-行锁定",
		"level": "L2",
		"desc": "区域候选全在同一行 → 排除该行其他候选",
		"config": {"size": 6, "seed": 1, "version": 3, "v3_attempt": 37, "label": "D-RegRowLk"}
	},
	{
		"label": "区域-列锁定",
		"level": "L2",
		"desc": "区域候选全在同一列 → 排除该列其他候选",
		"config": {"size": 6, "seed": 2, "version": 3, "v3_attempt": 23, "label": "D-RegColLk"}
	},
	{
		"label": "行-区域锁定",
		"level": "L2",
		"desc": "行候选全属同一区域 → 排除该区域其他行",
		"config": {"size": 6, "seed": 11, "version": 3, "v3_attempt": 5, "label": "D-RowRegLk"}
	},
	{
		"label": "列-区域锁定",
		"level": "L2",
		"desc": "列候选全属同一区域 → 排除该区域其他列",
		"config": {"size": 6, "seed": 10, "version": 3, "v3_attempt": 58, "label": "D-ColRegLk"}
	},
	{
		"label": "公共邻接消除",
		"level": "L2",
		"desc": "区域所有候选都与某格相邻 → 该格不可放猫",
		"config": {"size": 6, "seed": 3, "version": 3, "v3_attempt": 7, "label": "D-AdjElim"}
	},
	{
		"label": "浅层矛盾",
		"level": "L2",
		"desc": "假设放置 → 2步内矛盾 → 排除",
		"config": {"size": 6, "seed": 10, "version": 3, "v3_attempt": 58, "label": "D-ShallowC"}
	},
	{"label": "小集合逻辑(K=2)", "level": "L2", "desc": "2区域恰占2行/列 → 锁定", "config": null},
	{"label": "深层矛盾", "level": "L3", "desc": "假设放置 → 超过2步后矛盾 → 排除", "config": null},
	{"label": "中集合逻辑(K=3-4)", "level": "L3", "desc": "3-4区域恰占K行/列 → 锁定", "config": null},
	{"label": "大集合逻辑(K>=5)", "level": "L4", "desc": "5+区域恰占K行/列 → 锁定", "config": null},
]

# ---- 卡片数据：V3 尺寸示例 4×4 ~ 10×10（固定 seed 与 attempt，保证每次都是同一张图） ----
const SIZE_DEMO_ENTRIES: Array[Dictionary] = [
	{
		"label": "4×4 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 4, "seed": 1, "version": 3, "v3_attempt": 1, "label": "D-4x4"}
	},
	{
		"label": "5×5 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 5, "seed": 1, "version": 3, "v3_attempt": 1, "label": "D-5x5"}
	},
	{
		"label": "6×6 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 6, "seed": 1, "version": 3, "v3_attempt": 37, "label": "D-6x6"}
	},
	{
		"label": "7×7 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 7, "seed": 1, "version": 3, "v3_attempt": 14, "label": "D-7x7"}
	},
	{
		"label": "8×8 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 8, "seed": 1, "version": 3, "v3_attempt": 2, "label": "D-8x8"}
	},
	{
		"label": "9×9 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 9, "seed": 1, "version": 3, "v3_attempt": 9, "label": "D-9x9"}
	},
	{
		"label": "10×10 V3关卡",
		"desc": "无预填充 · 唯一解",
		"config": {"size": 10, "seed": 1, "version": 3, "v3_attempt": 201, "label": "D-10x10"}
	},
]

# ---- 卡片数据：R1-R5 策略体验（r=难度档决定配色，size=棋盘边长，地图现场生成） ----
const STRATEGY_ENTRIES: Array[Dictionary] = [
	{"label": "4×4 R1 Beginner", "r": 1, "size": 4},
	{"label": "4×4 R2 Easy", "r": 2, "size": 4},
	{"label": "4×4 R3 Medium", "r": 3, "size": 4},
	{"label": "4×4 R4 Hard", "r": 4, "size": 4},
	{"label": "4×4 R5 Expert", "r": 5, "size": 4},
	{"label": "7×7 R4 Hard", "r": 4, "size": 7},
	{"label": "7×7 R5 Expert", "r": 5, "size": 7},
	{"label": "8×8 R4 Hard", "r": 4, "size": 8},
]

# ---- 样式表：层级配色（L1~L4 是技巧层级，V3 给尺寸示例用） ----
const LEVEL_COLORS: Dictionary = {
	"L1":
	{
		"bg": Color(0.863, 0.988, 0.906),
		"text": Color(0.086, 0.396, 0.204),
		"border": Color(0.525, 0.937, 0.675)
	},
	"L2":
	{
		"bg": Color(0.859, 0.918, 1.0),
		"text": Color(0.118, 0.251, 0.686),
		"border": Color(0.576, 0.773, 0.988)
	},
	"L3":
	{
		"bg": Color(0.996, 0.953, 0.78),
		"text": Color(0.573, 0.251, 0.055),
		"border": Color(0.988, 0.827, 0.302)
	},
	"L4":
	{
		"bg": Color(0.996, 0.886, 0.886),
		"text": Color(0.6, 0.106, 0.106),
		"border": Color(0.988, 0.647, 0.647)
	},
	"V3":
	{
		"bg": Color(0.953, 0.91, 1.0),
		"text": Color(0.42, 0.129, 0.659),
		"border": Color(0.753, 0.518, 0.988)
	},
}
# ---- 样式表：R1~R5 配色（下标 0 留空，方便直接用 r 当索引） ----
const R_COLORS: Array[Dictionary] = [
	{},
	{
		"bg": Color(0.863, 0.988, 0.906),
		"text": Color(0.086, 0.396, 0.204),
		"border": Color(0.525, 0.937, 0.675)
	},
	{
		"bg": Color(0.859, 0.918, 1.0),
		"text": Color(0.118, 0.251, 0.686),
		"border": Color(0.576, 0.773, 0.988)
	},
	{
		"bg": Color(0.996, 0.953, 0.78),
		"text": Color(0.573, 0.251, 0.055),
		"border": Color(0.988, 0.827, 0.302)
	},
	{
		"bg": Color(0.996, 0.886, 0.886),
		"text": Color(0.6, 0.106, 0.106),
		"border": Color(0.988, 0.647, 0.647)
	},
	{
		"bg": Color(0.953, 0.91, 1.0),
		"text": Color(0.42, 0.129, 0.659),
		"border": Color(0.753, 0.518, 0.988)
	},
]

# ---- 字号（像素）与卡片留白 ----
const _FS_SM: int = 25 # 小号字（徽章、暂无）
const _FS_MD: int = 28 # 中号字（描述、按钮）
const _FS_BTN: int = 30 # 按钮字
const _FS_LG: int = 36 # 大号字（卡片标题）
const _FS_TIT: int = 39 # 分组标题字
const _CARD_MARGIN: int = 22 # 卡片左右外边距（像素）
const _CARD_PAD: int = 28 # 卡片内边距（像素）
const _BADGE_H: int = 50 # 徽章最小高度（像素）


# ================= 生命周期 =================
# 进场景树时一次性把所有卡片建出来
func _ready() -> void:
	_build_content()


# 按「生成器入口 → 技巧 → 尺寸示例 → 策略」搭列表，最后统一处理鼠标穿透
func _build_content() -> void:
	# 顶部先给一个直达关卡生成器的入口
	_content_vbox.add_child(_make_generator_btn())

	# 三个分组，之间用分隔线断开
	_content_vbox.add_child(_make_section_header("解题技巧调试", Color(0.118, 0.251, 0.686)))
	for entry: Dictionary in TECHNIQUE_ENTRIES:
		_content_vbox.add_child(_make_technique_card(entry))

	_content_vbox.add_child(_make_divider())

	_content_vbox.add_child(_make_section_header("V3 尺寸示例 (4-10)", Color(0.42, 0.129, 0.659)))
	for entry: Dictionary in SIZE_DEMO_ENTRIES:
		_content_vbox.add_child(_make_size_demo_card(entry))

	_content_vbox.add_child(_make_divider())

	_content_vbox.add_child(_make_section_header("R1-R5 策略体验", Color(0.929, 0.267, 0.267)))
	for entry: Dictionary in STRATEGY_ENTRIES:
		_content_vbox.add_child(_make_strategy_card(entry))

	# 底部留 60 像素空白，避免最后一张卡贴边
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	_content_vbox.add_child(spacer)

	# 把整棵子树里的非按钮 Control 的 mouse_filter 设成 PASS，
	# 否则 ScrollContainer 收不到拖动事件（按钮保留自己的点击）
	var _bfs: Array[Node] = []
	_bfs.append_array(_content_vbox.get_children())
	while not _bfs.is_empty():
		var _n: Node = _bfs.pop_back()
		_bfs.append_array(_n.get_children())
		if _n is Control and not (_n is Button):
			(_n as Control).mouse_filter = Control.MOUSE_FILTER_PASS


# ================= 卡片构造 =================
# 造分组标题（大号彩色字，左右留卡片边距）
func _make_section_header(title: String, color: Color) -> Control:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", _CARD_MARGIN)
	mc.add_theme_constant_override("margin_right", _CARD_MARGIN)
	mc.add_theme_constant_override("margin_top", _CARD_PAD)
	mc.add_theme_constant_override("margin_bottom", 8)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", _FS_TIT)
	lbl.add_theme_color_override("font_color", color)
	mc.add_child(lbl)
	return mc


# 造一条浅灰分隔线
func _make_divider() -> Control:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", _CARD_MARGIN)
	mc.add_theme_constant_override("margin_right", _CARD_MARGIN)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.886, 0.918, 0.941, 0.6)
	style.content_margin_top = 1
	sep.add_theme_stylebox_override("separator", style)
	mc.add_child(sep)
	return mc


# 造顶部「✨ 关卡生成器」大按钮
func _make_generator_btn() -> Control:
	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_theme_constant_override("margin_left", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_right", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_top", _CARD_PAD)
	outer.add_theme_constant_override("margin_bottom", 0)

	var btn := Button.new()
	btn.text = "✨ 关卡生成器"
	btn.add_theme_font_size_override("font_size", _FS_BTN + 3)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.388, 0.4, 0.945, 1)
	btn_style.corner_radius_top_left = 22
	btn_style.corner_radius_top_right = 22
	btn_style.corner_radius_bottom_right = 22
	btn_style.corner_radius_bottom_left = 22
	btn_style.content_margin_top = 28
	btn_style.content_margin_bottom = 28
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("hover", btn_style)
	btn.add_theme_stylebox_override("pressed", btn_style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 点一下打开关卡生成器页
	btn.pressed.connect(func() -> void: UIManager.show_ui(UiName.GENERATOR))
	outer.add_child(btn)
	return outer


# 造一张技巧卡：层级徽章 + 标题 + 说明，右侧「体验」按钮；无 config 时整卡置灰
func _make_technique_card(entry: Dictionary) -> Control:
	# 按 level 取配色，取不到就退到 L1
	var colors: Dictionary = LEVEL_COLORS.get(entry["level"], LEVEL_COLORS["L1"])
	# 有 config 才能开局，否则置灰并显示「暂无关卡」
	var available: bool = entry["config"] != null

	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_theme_constant_override("margin_left", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_right", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 0)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1) if available else Color(0.973, 0.973, 0.973, 1)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = colors["border"] if available else Color(0.831, 0.831, 0.831, 0.4)
	panel_style.corner_radius_top_left = 28
	panel_style.corner_radius_top_right = 28
	panel_style.corner_radius_bottom_right = 28
	panel_style.corner_radius_bottom_left = 28
	panel_style.content_margin_left = _CARD_PAD
	panel_style.content_margin_right = _CARD_PAD
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 10)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 16)
	top_hbox.add_child(_make_badge(entry["level"], colors, available))
	var name_lbl := Label.new()
	name_lbl.text = entry["label"]
	name_lbl.add_theme_font_size_override("font_size", _FS_LG)
	name_lbl.add_theme_color_override(
		"font_color", Color(0.102, 0.102, 0.18) if available else Color(0.612, 0.643, 0.675)
	)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_hbox.add_child(name_lbl)
	left_vbox.add_child(top_hbox)

	var desc_lbl := Label.new()
	desc_lbl.text = entry["desc"]
	desc_lbl.add_theme_font_size_override("font_size", _FS_MD)
	desc_lbl.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	left_vbox.add_child(desc_lbl)

	hbox.add_child(left_vbox)

	# 右侧：可用就给「体验」按钮，不可用就给灰字提示
	if available:
		hbox.add_child(_make_play_btn(entry["config"]))
	else:
		var no_lbl := Label.new()
		no_lbl.text = "暂无关卡"
		no_lbl.add_theme_font_size_override("font_size", _FS_SM)
		no_lbl.add_theme_color_override("font_color", Color(0.796, 0.835, 0.878))
		no_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(no_lbl)

	panel.add_child(hbox)
	outer.add_child(panel)
	return outer


# 造一张尺寸示例卡（配色固定用 V3 紫），右侧永远有「体验」
func _make_size_demo_card(entry: Dictionary) -> Control:
	var colors: Dictionary = LEVEL_COLORS["V3"]

	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_theme_constant_override("margin_left", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_right", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 0)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = colors["border"]
	panel_style.corner_radius_top_left = 28
	panel_style.corner_radius_top_right = 28
	panel_style.corner_radius_bottom_right = 28
	panel_style.corner_radius_bottom_left = 28
	panel_style.content_margin_left = _CARD_PAD
	panel_style.content_margin_right = _CARD_PAD
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 10)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 16)
	top_hbox.add_child(_make_badge("V3", colors, true))
	var name_lbl := Label.new()
	name_lbl.text = entry["label"]
	name_lbl.add_theme_font_size_override("font_size", _FS_LG)
	name_lbl.add_theme_color_override("font_color", Color(0.102, 0.102, 0.18))
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_hbox.add_child(name_lbl)
	left_vbox.add_child(top_hbox)

	var desc_lbl := Label.new()
	desc_lbl.text = entry["desc"]
	desc_lbl.add_theme_font_size_override("font_size", _FS_MD)
	desc_lbl.add_theme_color_override("font_color", Color(0.392, 0.455, 0.545))
	left_vbox.add_child(desc_lbl)

	hbox.add_child(left_vbox)
	hbox.add_child(_make_play_btn(entry["config"]))
	panel.add_child(hbox)
	outer.add_child(panel)
	return outer


# 造一张策略卡：R 徽章 + 名称 + 「体验」；点击时现场生成地图
func _make_strategy_card(entry: Dictionary) -> Control:
	# r 决定配色，sz 决定棋盘边长
	var r: int = entry["r"]
	var sz: int = entry.get("size", 4)
	var colors: Dictionary = R_COLORS[r] if r < R_COLORS.size() else R_COLORS[1] # 超出表格范围就退到 R1 配色

	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_theme_constant_override("margin_left", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_right", _CARD_MARGIN)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 0)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = colors["border"]
	panel_style.corner_radius_top_left = 28
	panel_style.corner_radius_top_right = 28
	panel_style.corner_radius_bottom_right = 28
	panel_style.corner_radius_bottom_left = 28
	panel_style.content_margin_left = _CARD_PAD
	panel_style.content_margin_right = _CARD_PAD
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)

	var badge_mc := MarginContainer.new()
	badge_mc.add_theme_constant_override("margin_left", 8)
	badge_mc.add_theme_constant_override("margin_right", 8)
	badge_mc.add_theme_constant_override("margin_top", 4)
	badge_mc.add_theme_constant_override("margin_bottom", 4)
	var badge_panel := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = colors["bg"]
	badge_style.corner_radius_top_left = 11
	badge_style.corner_radius_top_right = 11
	badge_style.corner_radius_bottom_right = 11
	badge_style.corner_radius_bottom_left = 11
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	var badge_lbl := Label.new()
	badge_lbl.text = "R%d" % r
	badge_lbl.add_theme_font_size_override("font_size", _FS_MD)
	badge_lbl.add_theme_color_override("font_color", colors["text"])
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_panel.add_child(badge_lbl)
	badge_mc.add_child(badge_panel)
	hbox.add_child(badge_mc)

	var name_lbl := Label.new()
	name_lbl.text = entry["label"]
	name_lbl.add_theme_font_size_override("font_size", _FS_BTN + 3)
	name_lbl.add_theme_color_override("font_color", Color(0.118, 0.18, 0.239))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	var btn := Button.new()
	btn.text = "体验"
	btn.add_theme_font_size_override("font_size", _FS_MD)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = colors["border"]
	btn_normal.corner_radius_top_left = 17
	btn_normal.corner_radius_top_right = 17
	btn_normal.corner_radius_bottom_right = 17
	btn_normal.corner_radius_bottom_left = 17
	btn_normal.content_margin_left = 22
	btn_normal.content_margin_right = 22
	btn_normal.content_margin_top = 10
	btn_normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_normal)
	btn.add_theme_stylebox_override("pressed", btn_normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 点击后现场生成（seed 固定 1、最多试 300 次），成功就带 regions / solution 开局
	btn.pressed.connect(
		func() -> void:
			var result: Dictionary = (
				LevelGeneratorEditor
				. generate_solvable_puzzle(
					{
						"size": sz,
						"seed": 1,
						"max_attempts": 300,
					}
				)
			)
			if result.is_empty():
				push_warning("[DebugPage] 无法生成 %s" % entry["label"])
				return
			(
				UIManager
				. show_ui(
					UiName.GAME,
					{
						"debug_prebuilt":
						{
							"size": sz,
							"label": entry["label"],
							"regions": result["regions"],
							"solution": result["solution"],
						}
					}
				)
			)
	)
	hbox.add_child(btn)

	panel.add_child(hbox)
	outer.add_child(panel)
	return outer


# 造左上角的层级徽章（最小 88×50，不可用时变灰）
func _make_badge(level_text: String, colors: Dictionary, available: bool) -> Control:
	var badge_panel := PanelContainer.new()
	badge_panel.custom_minimum_size = Vector2(88, _BADGE_H) # 宽固定 88，高取 _BADGE_H
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = colors["bg"] if available else Color(0.9, 0.9, 0.9)
	badge_style.corner_radius_top_left = 11
	badge_style.corner_radius_top_right = 11
	badge_style.corner_radius_bottom_right = 11
	badge_style.corner_radius_bottom_left = 11
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	var lbl := Label.new()
	lbl.text = level_text
	lbl.add_theme_font_size_override("font_size", _FS_SM)
	lbl.add_theme_color_override(
		"font_color", colors["text"] if available else Color(0.6, 0.6, 0.6)
	)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_panel.add_child(lbl)
	return badge_panel


# 造「体验」按钮，点击按 debug_config 打开 GAME 页
func _make_play_btn(config: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "体验"
	btn.add_theme_font_size_override("font_size", _FS_BTN)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.388, 0.4, 0.945)
	btn_normal.corner_radius_top_left = 17
	btn_normal.corner_radius_top_right = 17
	btn_normal.corner_radius_bottom_right = 17
	btn_normal.corner_radius_bottom_left = 17
	btn_normal.content_margin_left = 22
	btn_normal.content_margin_right = 22
	btn_normal.content_margin_top = 11
	btn_normal.content_margin_bottom = 11
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_normal)
	btn.add_theme_stylebox_override("pressed", btn_normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func() -> void: UIManager.show_ui(UiName.GAME, {"debug_config": config})) # debug_config 由 GamePage 映射成 EntryMode.DEBUG_CONFIG
	return btn


# Header 的返回按钮：回主页并关掉本页
func _on_back_btn_pressed() -> void:
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.DEBUG)
