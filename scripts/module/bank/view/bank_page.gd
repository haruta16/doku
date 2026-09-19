# 题库页面：只读浏览 BankData 的六类题库（常规 / LK / LK改 / LK优化 / GC / SP），点关卡直接开局
# 界面全在代码里现拼；本页不写任何题库文件，只读数据 + 调 UIManager 打开 GamePage
class_name BankPage
extends UIFrameWindow

# ---- 通用配色 ----
# _COLOR_BG 页面底色、_COLOR_CARD 卡片白、_COLOR_CARD_HL 卡片按下态浅黄、_COLOR_BORDER_Y 卡片黄描边
# _COLOR_LK 系列是 LK 主题蓝（主色 / 淡底 / 描边）；_COLOR_TEXT 主文字、_COLOR_GRAY 次要文字、_COLOR_SEPARATOR 列表分隔线
const _COLOR_BG := Color("#f0ece6")
const _COLOR_CARD := Color(1.0, 1.0, 1.0, 1.0)
const _COLOR_CARD_HL := Color("#fff8e7")
const _COLOR_BORDER_Y := Color("#f0c040")
const _COLOR_LK := Color(0.04, 0.4, 0.76, 1.0)
const _COLOR_LK_LIGHT := Color(0.04, 0.4, 0.76, 0.12)
const _COLOR_LK_BORDER := Color(0.04, 0.4, 0.76, 0.4)
const _COLOR_TEXT := Color("#333333")
const _COLOR_GRAY := Color("#888888")
const _COLOR_SEPARATOR := Color(0.85, 0.85, 0.85, 1.0)

# ---- 尺寸称号：4~10 每个尺寸配一个称号和主题色 ----
# _SIZE_TIER_COLORS 是尺寸 -> 颜色，_SIZE_TIER_LABELS 是尺寸 -> 称号，只用在常规题库的尺寸卡片上
const _SIZE_TIER_COLORS: Dictionary = {
	4: Color("#4caf50"),
	5: Color("#26a69a"),
	6: Color("#ff9800"),
	7: Color("#4a90e2"),
	8: Color("#e25c4a"),
	9: Color("#9b59b6"),
	10: Color("#c0392b"),
}

const _SIZE_TIER_LABELS: Dictionary = {
	4: "入门",
	5: "进阶",
	6: "挑战",
	7: "高手",
	8: "大师",
	9: "宗师",
	10: "传奇",
}

# ---- 难度信息 R1~R5：难度卡片与列表徽章的文案和配色 ----
# 每项字段：rank 难度号 / label 徽章文字 / desc 一句话说明 / bg 卡片底 / badge 徽章色 / go_color GO 按钮色
# 取值一律用 _RANK_INFO[rank - 1]：rank 从 1 起算、下标从 0 起算，不要混
const _RANK_INFO: Array[Dictionary] = [
	{
		rank = 1,
		label = "R1 Beginner",
		desc = "唯一候选",
		bg = Color("#e8f5e9"),
		badge = Color("#4caf50"),
		go_color = Color("#388e3c")
	},
	{
		rank = 2,
		label = "R2 Easy",
		desc = "区域-行列约束",
		bg = Color("#e3f2fd"),
		badge = Color("#2196f3"),
		go_color = Color("#1565c0")
	},
	{
		rank = 3,
		label = "R3 Medium",
		desc = "集合锁定(K≤3)",
		bg = Color("#fff8e1"),
		badge = Color("#ff9800"),
		go_color = Color("#e65100")
	},
	{
		rank = 4,
		label = "R4 Hard",
		desc = "高阶锁定/浅层推理",
		bg = Color("#fce4ec"),
		badge = Color("#f44336"),
		go_color = Color("#b71c1c")
	},
	{
		rank = 5,
		label = "R5 Expert",
		desc = "深层链式推理",
		bg = Color("#f3e5f5"),
		badge = Color("#9c27b0"),
		go_color = Color("#6a1b9a")
	},
]

# ---- H 档难度信息：只有 4H / 5H 两档，键直接是 rank（不是下标） ----
# 字段与 _RANK_INFO 相同，另多一个 tier = "H"
const _RANK_H_INFO: Dictionary = {
	4:
	{
		rank = 4,
		tier = "H",
		label = "R4H Hard+",
		desc = "深度高阶推理",
		bg = Color("#ff8a80"),
		badge = Color("#c62828"),
		go_color = Color("#7f0000")
	},
	5:
	{
		rank = 5,
		tier = "H",
		label = "R5H Expert+",
		desc = "极深链式推理",
		bg = Color("#e040fb"),
		badge = Color("#6a1b9a"),
		go_color = Color("#38006b")
	},
}

# ---- 允许出现 H 档的 [尺寸, 难度] 组合：4H 覆盖 7~12，5H 覆盖 8~11 ----
const _H_TIER_KEYS: Array = [
	[7, 4], [8, 4], [9, 4], [10, 4], [11, 4], [12, 4], [8, 5], [9, 5], [10, 5], [11, 5]
]

# ---- 难度徽章色：LK 列表按每关的 maxR 字段取色 ----
const _RANK_COLORS: Dictionary = {
	1: Color("#4caf50"),
	2: Color("#2196f3"),
	3: Color("#ff9800"),
	4: Color("#f44336"),
	5: Color("#9c27b0"),
}

# ---- 子节点引用（@onready：进场景树后才可用，节点都在 bank_page.tscn 里） ----
# 六块面板：SizePanel 首页 / TierPanel 难度 / ListPanel 关卡列表 / LKPanel / LKStyleSizePanel / RegularSizePanel
# 其中 ListPanel 被常规与 SP 共用，LKStyleSizePanel 被 LK 优化与 GC 共用
@onready var _size_panel: Control = $SizePanel
@onready var _size_vbox: VBoxContainer = $SizePanel/SizeScroll/VBox
@onready var _tier_panel: Control = $TierPanel
@onready var _tier_scroll: ScrollContainer = $TierPanel/Scroll
@onready var _tier_vbox: VBoxContainer = $TierPanel/Scroll/TierVBox
@onready var _tier_title: Label = $TierPanel/TierHeader/TierTitle
@onready var _list_panel: Control = $ListPanel
@onready var _list_title: Label = $ListPanel/ListHeader/ListTitle
@onready var _list_scroll: ScrollContainer = $ListPanel/Scroll
@onready var _level_list: VBoxContainer = $ListPanel/Scroll/LevelList
@onready var _lk_panel: Control = $LKPanel
@onready var _lk_info_label: Label = $LKPanel/LKInfoLabel
@onready var _lk_selector_container: Control = $LKPanel/LKSelectorContainer
@onready var _lk_scroll: ScrollContainer = $LKPanel/LKScroll
@onready var _lk_list: VBoxContainer = $LKPanel/LKScroll/LKList
@onready var _lkss_panel: Control = $LKStyleSizePanel
@onready var _lkss_vbox: VBoxContainer = $LKStyleSizePanel/LKSSScroll/LKSSVBox
@onready var _lkss_title: Label = $LKStyleSizePanel/LKSSHeader/LKSSTitle
@onready var _regular_panel: Control = $RegularSizePanel
@onready var _regular_vbox: VBoxContainer = $RegularSizePanel/RegScroll/RegVBox

# ---- 交互状态：当前尺寸/难度、各卡片序号、以及互斥的题库模式开关 ----
var _selected_size: int = 7  # 当前尺寸，列表页/难度页返回时用来重建
var _selected_rank: int = 1  # 当前难度（只写不读，保留给返回逻辑）
var _tier_num: Dictionary = {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, "4H": 1, "4N": 1, "5H": 1}  # 难度卡片的序号选择器，键 = 难度号或 "4H"/"4N"/"5H"
var _tier_num_labels: Dictionary = {}  # 上面那些序号 Label 的引用（键同上），± 键直接改它的 text
var _lk_num: int = 1  # LK 页序号选择器的当前值，从 1 起
var _lk_num_label: Label = null  # LK 页序号 Label；null = 序号条还没建出来
var _lk_style_mode: bool = false  # 正在看 LK 优化题库
var _gc_mode: bool = false  # 正在看 GC 题库
var _sp_mode: bool = false  # 正在看 SP 题库
var _regular_mode: bool = false  # 正在常规题库的尺寸页
var _lk_modified_mode: bool = false  # LK 页当前展示的是「改题库」而不是原版


# ================= 生命周期与面板切换 =================
# 进场景树：先按实际存在的题库拼首页卡片，再给六个滚动区挂上拖动滚动助手
func _ready() -> void:
	_build_size_cards()  # 按 BankData 里实际存在的题库拼首页卡片
	_show_size_panel()  # 打开时默认停在首页

	ScrollDragHelper.attach($SizePanel/SizeScroll)  # 六个滚动区都挂上「按住拖动滚动」助手（含橡皮筋回弹）
	ScrollDragHelper.attach(_tier_scroll)
	ScrollDragHelper.attach(_list_scroll)
	ScrollDragHelper.attach(_lk_scroll)
	ScrollDragHelper.attach($RegularSizePanel/RegScroll)
	ScrollDragHelper.attach($LKStyleSizePanel/LKSSScroll)


# UIManager 显示本页时的回调：按参数直接跳到某个子面板，否则回首页
func on_show(params: Dictionary = {}) -> void:
	if params.get("go_lk_style", false):
		_show_lk_style_tier_panel(params.get("sz", 7))
	elif params.get("go_lk", false):
		_show_lk_panel()
	elif params.get("go_regular", false):
		_show_tier_panel(params.get("sz", 7))
	else:
		_show_size_panel()


# 一次藏掉六块面板；所有 _show_* 切换前都先调它
func _hide_all_panels() -> void:
	_size_panel.visible = false
	_tier_panel.visible = false
	_list_panel.visible = false
	_lk_panel.visible = false
	_lkss_panel.visible = false
	_regular_panel.visible = false


# 回最外层「题库入口」页：顺手清掉常规 / GC / SP 模式标记
func _show_size_panel() -> void:
	_sp_mode = false  # 回总入口：三个子模式标记一起清掉
	_regular_mode = false
	_gc_mode = false
	_hide_all_panels()
	_size_panel.visible = true


# 显示常规题库某尺寸的难度页；进来先把各卡片的序号重置为 1
func _show_tier_panel(sz: int) -> void:
	_lk_style_mode = false
	_regular_mode = true
	_selected_size = sz
	_tier_title.text = "%d×%d 题库" % [sz, sz]
	_tier_num = {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, "4H": 1, "4N": 1, "5H": 1}
	_tier_num_labels.clear()
	_build_tier_cards(sz)
	_hide_all_panels()
	_tier_panel.visible = true
	_tier_scroll.scroll_vertical = 0


# 直接跳到关卡列表页（标题按当前模式加 GC / LK优化 前缀）；目前仓库内没有调用方，属保留入口
func _show_list_panel(sz: int, rank: int, tier: String = "") -> void:
	_selected_rank = rank
	var prefix: String
	if _gc_mode:
		prefix = "GC %d×%d" % [sz, sz]
	elif _lk_style_mode:
		prefix = "LK优化 %d×%d" % [sz, sz]
	else:
		prefix = "%d×%d" % [sz, sz]
	var rank_label: String = _RANK_INFO[rank - 1]["label"]
	if tier == "H":
		rank_label = _RANK_H_INFO[rank]["label"]
	_list_title.text = "%s / %s" % [prefix, rank_label]
	_build_level_list(sz, rank, tier)
	_hide_all_panels()
	_list_panel.visible = true
	_list_scroll.scroll_vertical = 0


# 显示 LK 原版题库页：整份存档平铺成一关一行
func _show_lk_panel() -> void:
	_lk_modified_mode = false
	var levels: Array = BankData.get_lk_levels()
	_lk_info_label.text = "共 %d 关  ·  按日期排序" % levels.size()
	_lk_num = 1
	_build_lk_selector(levels.size())
	_build_lk_list(levels)
	_hide_all_panels()
	_lk_panel.visible = true
	_lk_scroll.scroll_vertical = 0


# 显示 LK 改题库页（旋转/镜像变换版），与 LK 原版共用同一块面板
func _show_lk_modified_panel() -> void:
	_lk_modified_mode = true
	var levels: Array = BankData.get_lk_modified_levels()
	_lk_info_label.text = "共 %d 关  ·  LK 改题库" % levels.size()
	_lk_num = 1
	_build_lk_selector(levels.size())
	_build_lk_list(levels)
	_hide_all_panels()
	_lk_panel.visible = true
	_lk_scroll.scroll_vertical = 0


# 显示 LK 优化题库的尺寸选择页
func _show_lk_style_size_panel() -> void:
	_build_lkss_cards()
	_hide_all_panels()
	_lkss_panel.visible = true


# 重建 LK 优化尺寸卡片：每张卡显示尺寸、总关数和出现过的难度
func _build_lkss_cards() -> void:
	for child in _lkss_vbox.get_children():
		child.queue_free()
	for sz: int in BankData.get_lk_style_sizes():
		var ranks: Array[int] = BankData.get_lk_style_ranks(sz)
		var total: int = 0
		for r: int in ranks:
			total += BankData.get_lk_style_level_count(sz, r)
		var btn: Button = _make_lkss_size_card(sz, total, ranks)
		_lkss_vbox.add_child(btn)
		btn.pressed.connect(func() -> void: _show_lk_style_tier_panel(sz))


# 造一张 LK 优化尺寸卡片（紫色主题），返回按钮本身，点击逻辑由调用方接
func _make_lkss_size_card(sz: int, count: int, ranks: Array[int]) -> Button:
	# 本卡主题紫：_C 主色 / _CL 淡底 / _CB 描边，不走通用配色
	const _C: Color = Color(0.38, 0.18, 0.72, 1.0)
	const _CL: Color = Color(0.38, 0.18, 0.72, 0.1)
	const _CB: Color = Color(0.38, 0.18, 0.72, 0.4)
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _CB
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _CL
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _C
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0
	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)
	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "%d×%d" % [sz, sz]
	sl.add_theme_font_size_override("font_size", 56)
	sl.add_theme_color_override("font_color", _C)
	lv.add_child(sl)
	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)
	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)
	var rank_parts: Array[String] = []
	for r: int in ranks:
		rank_parts.append("R%d" % r)
	var rl := Label.new()
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rl.text = " · ".join(rank_parts)
	rl.add_theme_font_size_override("font_size", 24)
	rl.add_theme_color_override("font_color", _COLOR_GRAY)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(rl)
	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _C)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)
	return btn


# 显示 LK 优化题库某尺寸的难度页；卡片由 _build_tier_cards 按 _lk_style_mode 分派
func _show_lk_style_tier_panel(sz: int) -> void:
	_lk_style_mode = true
	_selected_size = sz
	_tier_title.text = "LK优化 %d×%d" % [sz, sz]
	_tier_num = {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, "4H": 1, "4N": 1, "5H": 1}
	_tier_num_labels.clear()
	_build_tier_cards(sz)
	_hide_all_panels()
	_tier_panel.visible = true
	_tier_scroll.scroll_vertical = 0


# ================= 首页入口卡片（六类题库） =================
# 重建首页卡片：常规 / LK / LK改 / LK优化 / GC / SP，哪类题库一关都没有就不出那张卡
func _build_size_cards() -> void:
	for child in _size_vbox.get_children():
		child.queue_free()

	# 常规题库：把各尺寸各难度的关数合计起来
	var reg_sizes: Array[int] = BankData.get_sizes()
	if reg_sizes.size() > 0:
		var reg_total: int = 0
		for sz: int in reg_sizes:
			for r: int in BankData.get_ranks(sz):
				reg_total += BankData.get_level_count(sz, r)
		var reg_btn: Button = _make_regular_card(reg_total, reg_sizes)
		_size_vbox.add_child(reg_btn)
		reg_btn.pressed.connect(_show_regular_size_panel)

	# LK 原版：LinkedIn Queens 存档，按日期排序
	var lk_levels: Array = BankData.get_lk_levels()
	if lk_levels.size() > 0:
		var lk_btn: Button = _make_lk_card(lk_levels.size())
		_size_vbox.add_child(lk_btn)
		lk_btn.pressed.connect(_show_lk_panel)

	# LK 改题库：旋转 / 镜像变换版
	var lk_mod_levels: Array = BankData.get_lk_modified_levels()
	if lk_mod_levels.size() > 0:
		var lk_mod_btn: Button = _make_lk_modified_card(lk_mod_levels.size())
		_size_vbox.add_child(lk_mod_btn)
		lk_mod_btn.pressed.connect(_show_lk_modified_panel)

	# LK 优化题库：难度取各尺寸的并集，再按 1~5 排序后显示
	var lk_style_sizes: Array[int] = BankData.get_lk_style_sizes()
	if lk_style_sizes.size() > 0:
		var lk_style_total: int = 0
		var all_ranks: Dictionary = {}
		for sz: int in lk_style_sizes:
			for r: int in BankData.get_lk_style_ranks(sz):
				all_ranks[r] = true
				lk_style_total += BankData.get_lk_style_level_count(sz, r)
		var sorted_ranks: Array[int] = []
		for r: int in [1, 2, 3, 4, 5]:
			if all_ranks.has(r):
				sorted_ranks.append(r)
		var lk_style_btn: Button = _make_lk_style_card(lk_style_total, sorted_ranks)
		_size_vbox.add_child(lk_style_btn)
		lk_style_btn.pressed.connect(_show_lk_style_size_panel)

	# GC 题库：同样从各尺寸扫出难度并集
	var gc_sizes: Array[int] = BankData.get_gc_sizes()
	if gc_sizes.size() > 0:
		var gc_total: int = 0
		var gc_all_ranks: Dictionary = {}
		for sz: int in gc_sizes:
			for r: int in BankData.get_gc_ranks(sz):
				gc_all_ranks[r] = true
				gc_total += BankData.get_gc_level_count(sz, r)
		var gc_sorted_ranks: Array[int] = []
		for r: int in [1, 2, 3, 4, 5]:
			if gc_all_ranks.has(r):
				gc_sorted_ranks.append(r)
		var gc_btn: Button = _make_gc_card(gc_total, gc_sorted_ranks)
		_size_vbox.add_child(gc_btn)
		gc_btn.pressed.connect(_show_gc_size_panel)

	# SP 特殊图案题库
	var sp_levels: Array = BankData.get_sp_levels()
	if sp_levels.size() > 0:
		var sp_btn: Button = _make_sp_card(sp_levels.size())
		_size_vbox.add_child(sp_btn)
		sp_btn.pressed.connect(_show_sp_panel)


# ================= 常规题库：尺寸页 =================
# 显示常规题库尺寸页并置 _regular_mode，返回时靠它判断回哪一层
func _show_regular_size_panel() -> void:
	_regular_mode = true
	_build_regular_size_cards()
	_hide_all_panels()
	_regular_panel.visible = true


# 重建常规题库的尺寸卡片，每张统计该尺寸的总关数与难度列表
func _build_regular_size_cards() -> void:
	for child in _regular_vbox.get_children():
		child.queue_free()
	for sz: int in BankData.get_sizes():
		var ranks: Array[int] = BankData.get_ranks(sz)
		var total: int = 0
		for r: int in ranks:
			total += BankData.get_level_count(sz, r)
		var btn: Button = _make_size_card(sz, total, ranks)
		_regular_vbox.add_child(btn)
		btn.pressed.connect(func() -> void: _show_tier_panel(sz))


# 造首页「常规题库」总入口卡：显示尺寸范围与全部关卡数
func _make_regular_card(count: int, sizes: Array[int]) -> Button:
	# 本卡主题绿：主色 / 淡底 / 描边
	const _C: Color = Color(0.18, 0.55, 0.28, 1.0)
	const _CL: Color = Color(0.18, 0.55, 0.28, 0.1)
	const _CB: Color = Color(0.18, 0.55, 0.28, 0.4)
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _CB
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _CL
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _C
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0
	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)
	var nl := Label.new()
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.text = "常规题库"
	nl.add_theme_font_size_override("font_size", 52)
	nl.add_theme_color_override("font_color", _C)
	lv.add_child(nl)
	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "%d×%d ~ %d×%d" % [sizes.front(), sizes.front(), sizes.back(), sizes.back()]
	sl.add_theme_font_size_override("font_size", 26)
	sl.add_theme_color_override("font_color", _COLOR_GRAY)
	lv.add_child(sl)
	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)
	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)
	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _C)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)
	return btn


# 常规尺寸页返回：清 _regular_mode 再回首页（由 RegBackBtn 的 pressed 触发）
func _on_regular_back_btn_pressed() -> void:
	_regular_mode = false
	_show_size_panel()


# 造常规题库的尺寸卡片：尺寸大字 + 称号 + 关数 + 难度列表
func _make_size_card(sz: int, count: int, ranks: Array[int]) -> Button:
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.shadow_color = Color(0, 0, 0, 0.1)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)

	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _COLOR_CARD_HL
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(3)
	sf_p.border_color = _COLOR_BORDER_Y

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0

	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)

	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "%d×%d" % [sz, sz]
	sl.add_theme_font_size_override("font_size", 56)
	sl.add_theme_color_override("font_color", _COLOR_TEXT)
	lv.add_child(sl)

	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.text = _SIZE_TIER_LABELS.get(sz, "")
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", _SIZE_TIER_COLORS.get(sz, _COLOR_GRAY))
	lv.add_child(tl)

	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)

	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)

	var rank_parts: Array[String] = []
	for r: int in ranks:
		rank_parts.append("R%d" % r)
	var rl := Label.new()
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rl.text = " · ".join(rank_parts)
	rl.add_theme_font_size_override("font_size", 24)
	rl.add_theme_color_override("font_color", _COLOR_GRAY)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(rl)

	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _COLOR_GRAY)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)

	return btn


# 造首页「LK 题库」卡：蓝色主题，副标题标明是 LinkedIn Queens 存档
func _make_lk_card(count: int) -> Button:
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _COLOR_LK_BORDER
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)

	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _COLOR_LK_LIGHT
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _COLOR_LK

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0

	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)

	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "LK 题库"
	sl.add_theme_font_size_override("font_size", 48)
	sl.add_theme_color_override("font_color", _COLOR_LK)
	lv.add_child(sl)

	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.text = "LinkedIn Queens 存档"
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", _COLOR_GRAY)
	lv.add_child(tl)

	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)

	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)

	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _COLOR_LK)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)

	return btn


# 造首页「LK 改题库」卡：青绿主题，副标题标明是旋转 / 镜像变换版
func _make_lk_modified_card(count: int) -> Button:
	# 本卡主题青绿：主色 / 淡底 / 描边
	const _C: Color = Color(0.12, 0.58, 0.45, 1.0)
	const _CL: Color = Color(0.12, 0.58, 0.45, 0.1)
	const _CB: Color = Color(0.12, 0.58, 0.45, 0.4)
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _CB
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _CL
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _C
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0
	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)
	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "LK 改题库"
	sl.add_theme_font_size_override("font_size", 48)
	sl.add_theme_color_override("font_color", _C)
	lv.add_child(sl)
	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.text = "旋转/镜像变换版"
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", _COLOR_GRAY)
	lv.add_child(tl)
	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)
	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)
	var al2 := Label.new()
	al2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al2.text = "›"
	al2.add_theme_font_size_override("font_size", 56)
	al2.add_theme_color_override("font_color", _C)
	al2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al2)
	return btn


# 造首页「LK 优化题库」卡：紫色主题，尺寸范围现问 BankData
func _make_lk_style_card(count: int, ranks: Array[int]) -> Button:
	# 本卡主题紫：主色 / 淡底 / 描边
	const _COLOR_STYLE := Color(0.38, 0.18, 0.72, 1.0)
	const _COLOR_STYLE_LIGHT := Color(0.38, 0.18, 0.72, 0.1)
	const _COLOR_STYLE_BORDER := Color(0.38, 0.18, 0.72, 0.4)

	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _COLOR_STYLE_BORDER
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)

	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _COLOR_STYLE_LIGHT
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _COLOR_STYLE

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0

	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)

	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "LK 优化题库"
	sl.add_theme_font_size_override("font_size", 44)
	sl.add_theme_color_override("font_color", _COLOR_STYLE)
	lv.add_child(sl)

	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lk_sizes := BankData.get_lk_style_sizes()
	var sz_min: int = lk_sizes[0] if lk_sizes.size() > 0 else 8
	var sz_max: int = lk_sizes[-1] if lk_sizes.size() > 0 else 8
	tl.text = "%d×%d ~ %d×%d  LinkedIn 优化版" % [sz_min, sz_min, sz_max, sz_max]
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", _COLOR_GRAY)
	lv.add_child(tl)

	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)

	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)

	var rank_parts: Array[String] = []
	for r: int in ranks:
		rank_parts.append("R%d" % r)
	var rl := Label.new()
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rl.text = " · ".join(rank_parts)
	rl.add_theme_font_size_override("font_size", 24)
	rl.add_theme_color_override("font_color", _COLOR_GRAY)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(rl)

	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _COLOR_STYLE)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)

	return btn


# 造首页「GC 题库」卡：青绿主题，尺寸范围现问 BankData
func _make_gc_card(count: int, ranks: Array[int]) -> Button:
	# 本卡主题青绿：主色 / 淡底 / 描边
	const _C := Color(0.08, 0.6, 0.45, 1.0)
	const _CL := Color(0.08, 0.6, 0.45, 0.1)
	const _CB := Color(0.08, 0.6, 0.45, 0.4)
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = _COLOR_CARD
	sf_n.set_corner_radius_all(24)
	sf_n.set_border_width_all(2)
	sf_n.border_color = _CB
	sf_n.shadow_color = Color(0, 0, 0, 0.08)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = _CL
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(2)
	sf_p.border_color = _C
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -48.0
	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(lv)
	var sl := Label.new()
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.text = "GC 题库"
	sl.add_theme_font_size_override("font_size", 44)
	sl.add_theme_color_override("font_color", _C)
	lv.add_child(sl)
	var gc_sizes := BankData.get_gc_sizes()
	var sz_min: int = gc_sizes[0] if gc_sizes.size() > 0 else 6
	var sz_max: int = gc_sizes[-1] if gc_sizes.size() > 0 else 12
	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.text = "%d×%d ~ %d×%d  紧凑型区域布局" % [sz_min, sz_min, sz_max, sz_max]
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", _COLOR_GRAY)
	lv.add_child(tl)
	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(rv)
	var cl := Label.new()
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text = "%d 关" % count
	cl.add_theme_font_size_override("font_size", 32)
	cl.add_theme_color_override("font_color", _COLOR_GRAY)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(cl)
	var rank_parts: Array[String] = []
	for r: int in ranks:
		rank_parts.append("R%d" % r)
	var rl := Label.new()
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rl.text = " · ".join(rank_parts)
	rl.add_theme_font_size_override("font_size", 24)
	rl.add_theme_color_override("font_color", _COLOR_GRAY)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(rl)
	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 56)
	al.add_theme_color_override("font_color", _C)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(al)
	return btn


# ================= GC 题库 =================
# 显示 GC 题库尺寸页：复用 LK 优化那块面板（_lkss_panel），只换标题和数据源
func _show_gc_size_panel() -> void:
	_build_lkss_cards_gc()
	_hide_all_panels()
	_lkss_panel.visible = true


# 用 GC 数据重建尺寸卡片（借用 LK 优化的卡片工厂），点击进 GC 难度页
func _build_lkss_cards_gc() -> void:
	for child in _lkss_vbox.get_children():
		child.queue_free()
	_lkss_title.text = "GC 题库"
	for sz: int in BankData.get_gc_sizes():
		var ranks: Array[int] = BankData.get_gc_ranks(sz)
		var total: int = 0
		for r: int in ranks:
			total += BankData.get_gc_level_count(sz, r)
		var btn: Button = _make_lkss_size_card(sz, total, ranks)
		_lkss_vbox.add_child(btn)
		btn.pressed.connect(func() -> void: _show_gc_tier_panel(sz))


# 显示 GC 某尺寸的难度页：置 _gc_mode，卡片由 _build_tier_cards 分派
func _show_gc_tier_panel(sz: int) -> void:
	_lk_style_mode = false
	_gc_mode = true
	_selected_size = sz
	_tier_title.text = "GC %d×%d" % [sz, sz]
	_tier_num = {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, "4H": 1, "4N": 1, "5H": 1}
	_tier_num_labels.clear()
	_build_tier_cards(sz)
	_hide_all_panels()
	_tier_panel.visible = true
	_tier_scroll.scroll_vertical = 0


# ================= LK 题库页（一行一关） =================
# 重建 LK 页顶部序号条：− / 数字 / + / GO，数字范围 1~总关数 count
func _build_lk_selector(count: int) -> void:
	for child in _lk_selector_container.get_children():
		child.queue_free()
	_lk_num_label = null

	var sf_card := StyleBoxFlat.new()
	sf_card.bg_color = Color(1, 1, 1, 1)
	sf_card.set_corner_radius_all(20)
	sf_card.set_border_width_all(2)
	sf_card.border_color = _COLOR_LK_BORDER
	sf_card.shadow_color = Color(0, 0, 0, 0.06)
	sf_card.shadow_size = 4
	sf_card.shadow_offset = Vector2(0, 2)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", sf_card)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lk_selector_container.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)

	var prompt_lbl := Label.new()
	prompt_lbl.text = "输入关卡序号"
	prompt_lbl.add_theme_font_size_override("font_size", 32)
	prompt_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	prompt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(prompt_lbl)

	var minus_btn: Button = _make_small_btn("−", _COLOR_LK)
	hbox.add_child(minus_btn)

	var num_lbl := Label.new()
	num_lbl.text = "1"
	num_lbl.add_theme_font_size_override("font_size", 40)
	num_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	num_lbl.custom_minimum_size = Vector2(80, 0)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(num_lbl)
	_lk_num_label = num_lbl

	var plus_btn: Button = _make_small_btn("+", _COLOR_LK)
	hbox.add_child(plus_btn)

	var go_sf := StyleBoxFlat.new()
	go_sf.bg_color = _COLOR_LK
	go_sf.set_corner_radius_all(16)
	go_sf.content_margin_left = 28
	go_sf.content_margin_right = 28
	go_sf.content_margin_top = 10
	go_sf.content_margin_bottom = 10

	var go_sf_p := StyleBoxFlat.new()
	go_sf_p.bg_color = _COLOR_LK.darkened(0.2)
	go_sf_p.set_corner_radius_all(16)
	go_sf_p.content_margin_left = 28
	go_sf_p.content_margin_right = 28
	go_sf_p.content_margin_top = 10
	go_sf_p.content_margin_bottom = 10

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var go_btn := Button.new()
	go_btn.text = "GO"
	go_btn.add_theme_font_size_override("font_size", 36)
	go_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	go_btn.add_theme_stylebox_override("normal", go_sf)
	go_btn.add_theme_stylebox_override("pressed", go_sf_p)
	go_btn.add_theme_stylebox_override("hover", go_sf)
	go_btn.add_theme_stylebox_override("focus", sf_f)
	hbox.add_child(go_btn)

	minus_btn.pressed.connect(func() -> void: _on_lk_minus(count))
	plus_btn.pressed.connect(func() -> void: _on_lk_plus(count))
	go_btn.pressed.connect(_on_lk_go)


# 重建 LK 关卡列表：一关一个按钮，关与关之间插 2px 分隔线
func _build_lk_list(levels: Array) -> void:
	for child in _lk_list.get_children():
		child.queue_free()

	for i: int in levels.size():
		var entry: Dictionary = levels[i]
		_lk_list.add_child(_make_lk_item(entry, i))

		if i < levels.size() - 1:
			var sep := ColorRect.new()
			sep.color = _COLOR_SEPARATOR
			sep.custom_minimum_size = Vector2(0, 2)
			_lk_list.add_child(sep)


# 造 LK 列表一行：序号 + 尺寸 + 日期 + 难度标签，点击直接开局
func _make_lk_item(entry: Dictionary, i: int) -> Button:
	var max_r: int = entry.get("maxR", 1)
	var rank_color: Color = _RANK_COLORS.get(max_r, _COLOR_GRAY)
	var sz: int = entry.get("size", 8)

	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = Color(1, 1, 1, 1) if i % 2 == 0 else Color(0.98, 0.98, 1.0, 1)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = Color(0.93, 0.93, 0.93, 1)
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 110)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_n)
	btn.add_theme_stylebox_override("focus", sf_f)

	var levels: Array = (
		BankData.get_lk_modified_levels() if _lk_modified_mode else BankData.get_lk_levels()
	)
	var is_mod: bool = _lk_modified_mode
	btn.pressed.connect(func() -> void: _play_lk_level(levels, i, is_mod))

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 36.0
	hbox.offset_right = -36.0

	var idx_lbl := Label.new()
	idx_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idx_lbl.text = "#%d" % (i + 1)
	idx_lbl.add_theme_font_size_override("font_size", 30)
	idx_lbl.add_theme_color_override("font_color", _COLOR_LK)
	idx_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	idx_lbl.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(idx_lbl)

	var sz_lbl := Label.new()
	sz_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sz_lbl.text = "%d×%d" % [sz, sz]
	sz_lbl.add_theme_font_size_override("font_size", 32)
	sz_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	sz_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sz_lbl.custom_minimum_size = Vector2(110, 0)
	hbox.add_child(sz_lbl)

	var date_lbl := Label.new()
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_lbl.text = entry.get("date", "")
	date_lbl.add_theme_font_size_override("font_size", 26)
	date_lbl.add_theme_color_override("font_color", _COLOR_GRAY)
	date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(date_lbl)

	var rank_lbl := Label.new()
	rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_lbl.text = entry.get("label", "R%d" % max_r)
	rank_lbl.add_theme_font_size_override("font_size", 24)
	rank_lbl.add_theme_color_override("font_color", rank_color)
	rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_lbl.custom_minimum_size = Vector2(130, 0)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(rank_lbl)

	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 50)
	al.add_theme_color_override("font_color", _COLOR_LK)
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	al.custom_minimum_size = Vector2(50, 0)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(al)

	return btn


# LK 序号减一，下限 1
func _on_lk_minus(_count: int) -> void:
	_lk_num = maxi(1, _lk_num - 1)
	if _lk_num_label != null:
		_lk_num_label.text = str(_lk_num)


# LK 序号加一，上限是总关数 count
func _on_lk_plus(count: int) -> void:
	_lk_num = mini(count, _lk_num + 1)
	if _lk_num_label != null:
		_lk_num_label.text = str(_lk_num)


# GO：按序号条上的数字跳关（界面从 1 起算，传给 _play_lk_level 时减 1）
func _on_lk_go() -> void:
	var levels: Array = (
		BankData.get_lk_modified_levels() if _lk_modified_mode else BankData.get_lk_levels()
	)
	_play_lk_level(levels, _lk_num - 1, _lk_modified_mode)


# 打开 LK 题库第 idx 关：把该关的 regionMap / solution 等预置数据交给 GamePage
func _play_lk_level(levels: Array, idx: int, is_modified: bool = false) -> void:
	if levels.is_empty() or idx < 0 or idx >= levels.size():
		return
	var entry: Dictionary = levels[idx]
	var sz: int = entry.get("size", 8)
	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"bank_mode": true,
				"bank_lk": true,
				"bank_lk_modified": is_modified,
				"bank_size": sz,
				"bank_rank": entry.get("maxR", 1),
				"bank_index": idx + 1,
				"bank_total": levels.size(),
				"prebuilt_regions": entry.get("regionMap", []),
				"prebuilt_solution": entry.get("solution", []),
				"level_seed": entry.get("id", 0),
			}
		)
	)


# ================= 难度页（R1~R5 与 4H/5H 卡片） =================
# 重建难度卡片：先出 R1~R5，再按 _H_TIER_KEYS 补 H 档；关数为 0 的档位直接跳过
func _build_tier_cards(sz: int) -> void:
	for child in _tier_vbox.get_children():
		child.queue_free()

	# 第一轮：R1~R5 五个常规档位
	for info: Dictionary in _RANK_INFO:
		var rank: int = info["rank"]
		var has_h_tier: bool = _H_TIER_KEYS.any(
			func(k: Array) -> bool: return k[0] == sz and k[1] == rank
		)
		var count: int
		var effective_tier: String = ""
		if _gc_mode:
			var gc_h: bool = has_h_tier and BankData.get_gc_level_count_by_tier(sz, rank, "H") > 0
			if gc_h:
				count = BankData.get_gc_level_count_by_tier(sz, rank, "N")
				effective_tier = "N"
			else:
				count = BankData.get_gc_level_count(sz, rank)
				effective_tier = ""
		elif has_h_tier and _lk_style_mode:
			count = BankData.get_lk_style_level_count_by_tier(sz, rank, "N")
			effective_tier = "N"
		elif has_h_tier and not _lk_style_mode:
			count = BankData.get_level_count_by_tier(sz, rank, "N")
			effective_tier = "N"
		elif _lk_style_mode:
			count = BankData.get_lk_style_level_count(sz, rank)
		else:
			count = BankData.get_level_count(sz, rank)
		if count == 0:
			continue
		var card: Control = _make_tier_card(info, count, sz, effective_tier)
		_tier_vbox.add_child(card)

	# 第二轮：H 档（4H / 5H），只在 _H_TIER_KEYS 列出的尺寸里出现
	for key in _H_TIER_KEYS:
		var h_sz: int = key[0]
		var h_rank: int = key[1]
		if h_sz != sz:
			continue
		var h_info: Dictionary = _RANK_H_INFO[h_rank]
		var h_count: int
		if _gc_mode:
			h_count = BankData.get_gc_level_count_by_tier(sz, h_rank, "H")
		elif _lk_style_mode:
			h_count = BankData.get_lk_style_level_count_by_tier(sz, h_rank, "H")
		else:
			h_count = BankData.get_level_count_by_tier(sz, h_rank, "H")
		if h_count == 0:
			continue
		var h_card: Control = _make_tier_card(h_info, h_count, sz, "H")
		_tier_vbox.add_child(h_card)


# 造一张难度卡片：难度徽章 + 说明 + 关数 + 序号选择器 + GO
func _make_tier_card(info: Dictionary, count: int, sz: int, tier: String = "") -> Control:
	var rank: int = info["rank"]
	var bg: Color = info["bg"]
	var badge: Color = info["badge"]
	var go_c: Color = info["go_color"]
	# 序号选择器的键：H / N 档带档位后缀，普通档直接用难度号
	var num_key: Variant = (
		("%dH" % rank) if tier == "H" else (("%dN" % rank) if tier == "N" else rank)
	)

	var sf_bg := StyleBoxFlat.new()
	sf_bg.bg_color = bg
	sf_bg.set_corner_radius_all(20)
	sf_bg.set_border_width_all(2)
	sf_bg.border_color = badge.lightened(0.35)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sf_bg)
	panel.custom_minimum_size = Vector2(0, 200)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	vbox.add_child(row1)

	var badge_sf := StyleBoxFlat.new()
	badge_sf.bg_color = badge
	badge_sf.set_corner_radius_all(12)
	badge_sf.content_margin_left = 18
	badge_sf.content_margin_right = 18
	badge_sf.content_margin_top = 6
	badge_sf.content_margin_bottom = 6

	var badge_panel := PanelContainer.new()
	badge_panel.add_theme_stylebox_override("panel", badge_sf)
	row1.add_child(badge_panel)

	var badge_lbl := Label.new()
	badge_lbl.text = info["label"]
	badge_lbl.add_theme_font_size_override("font_size", 28)
	badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	badge_panel.add_child(badge_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = info["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 30)
	desc_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(desc_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "共 %d 关" % count
	count_lbl.add_theme_font_size_override("font_size", 26)
	count_lbl.add_theme_color_override("font_color", _COLOR_GRAY)
	vbox.add_child(count_lbl)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	vbox.add_child(row3)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(spacer)

	var minus_btn: Button = _make_small_btn("−", badge)
	row3.add_child(minus_btn)

	var num_lbl := Label.new()
	num_lbl.text = "1"
	num_lbl.add_theme_font_size_override("font_size", 38)
	num_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	num_lbl.custom_minimum_size = Vector2(70, 0)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row3.add_child(num_lbl)
	_tier_num_labels[num_key] = num_lbl

	var plus_btn: Button = _make_small_btn("+", badge)
	row3.add_child(plus_btn)

	var go_sf := StyleBoxFlat.new()
	go_sf.bg_color = go_c
	go_sf.set_corner_radius_all(16)
	go_sf.content_margin_left = 28
	go_sf.content_margin_right = 28
	go_sf.content_margin_top = 10
	go_sf.content_margin_bottom = 10

	var go_sf_p := StyleBoxFlat.new()
	go_sf_p.bg_color = go_c.darkened(0.2)
	go_sf_p.set_corner_radius_all(16)
	go_sf_p.content_margin_left = 28
	go_sf_p.content_margin_right = 28
	go_sf_p.content_margin_top = 10
	go_sf_p.content_margin_bottom = 10

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var go_btn := Button.new()
	go_btn.text = "GO"
	go_btn.add_theme_font_size_override("font_size", 36)
	go_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	go_btn.add_theme_stylebox_override("normal", go_sf)
	go_btn.add_theme_stylebox_override("pressed", go_sf_p)
	go_btn.add_theme_stylebox_override("hover", go_sf)
	go_btn.add_theme_stylebox_override("focus", sf_f)
	row3.add_child(go_btn)

	# 三个按钮各自闭包捕获本卡的参数：± 只改本卡数字，GO 用本卡的尺寸/难度开局
	minus_btn.pressed.connect(func() -> void: _on_tier_minus(num_key, count))
	plus_btn.pressed.connect(func() -> void: _on_tier_plus(num_key, count))
	go_btn.pressed.connect(func() -> void: _on_tier_go(sz, rank, tier))

	return panel


# 造 ± 小圆角按钮：底色由传入的主色淡化而来
func _make_small_btn(label: String, color: Color) -> Button:
	var sf := StyleBoxFlat.new()
	sf.bg_color = color.lightened(0.5)
	sf.set_corner_radius_all(12)
	sf.content_margin_left = 16
	sf.content_margin_right = 16
	sf.content_margin_top = 8
	sf.content_margin_bottom = 8

	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = color.lightened(0.2)
	sf_p.set_corner_radius_all(12)
	sf_p.content_margin_left = 16
	sf_p.content_margin_right = 16
	sf_p.content_margin_top = 8
	sf_p.content_margin_bottom = 8

	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 36)
	btn.add_theme_color_override("font_color", color.darkened(0.3))
	btn.add_theme_stylebox_override("normal", sf)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf)
	btn.add_theme_stylebox_override("focus", sf_f)
	return btn


# 难度卡片序号减一，下限 1
func _on_tier_minus(key: Variant, _count: int) -> void:
	_tier_num[key] = maxi(1, _tier_num.get(key, 1) - 1)
	if _tier_num_labels.has(key):
		(_tier_num_labels[key] as Label).text = str(_tier_num[key])


# 难度卡片序号加一，上限是该档关数 count
func _on_tier_plus(key: Variant, count: int) -> void:
	_tier_num[key] = mini(count, _tier_num.get(key, 1) + 1)
	if _tier_num_labels.has(key):
		(_tier_num_labels[key] as Label).text = str(_tier_num[key])


# 按当前题库模式 + tier 取关卡数组，跳到序号对应的那一关
func _on_tier_go(sz: int, rank: int, tier: String = "") -> void:
	# 取数分派：GC 一路，带档位的（H / N）一路，其余按普通难度取
	var levels: Array
	if _gc_mode:
		levels = (
			BankData.get_gc_levels_by_tier(sz, rank, tier)
			if (tier == "H" or tier == "N")
			else BankData.get_gc_levels(sz, rank)
		)
	elif tier == "H" or tier == "N":
		levels = (
			BankData.get_lk_style_levels_by_tier(sz, rank, tier)
			if _lk_style_mode
			else BankData.get_levels_by_tier(sz, rank, tier)
		)
	else:
		levels = (
			BankData.get_lk_style_levels(sz, rank)
			if _lk_style_mode
			else BankData.get_levels(sz, rank)
		)
	if levels.is_empty():
		return
	# 序号键的算法与 _make_tier_card 保持一致
	var num_key: Variant = (
		("%dH" % rank) if tier == "H" else (("%dN" % rank) if tier == "N" else rank)
	)
	# 序号夹到合法范围，防止题库变动后越界
	var idx: int = clampi(_tier_num.get(num_key, 1) - 1, 0, levels.size() - 1)
	var entry: Dictionary = levels[idx]
	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"bank_mode": true,
				"bank_size": sz,
				"bank_rank": rank,
				"bank_index": idx + 1,
				"bank_total": levels.size(),
				"prebuilt_regions": entry.get("regionMap", []),
				"prebuilt_solution": entry.get("solution", []),
				"level_seed": entry.get("seed", 0),
				"r1_steps": entry.get("r1", 0),
				"r2_steps": entry.get("r2", 0),
				"r3_steps": entry.get("r3", 0),
				"r4_steps": entry.get("r4", 0),
				"r5_steps": entry.get("r5", 0),
				"bank_lk_style": _lk_style_mode,
				"bank_gc": _gc_mode,
				"bank_tier_h": tier == "H",
				"bank_tier": tier,
			}
		)
	)


# ================= 关卡列表页 =================
# 重建关卡列表：按当前模式与 tier 取数组，一行一关
func _build_level_list(sz: int, rank: int, tier: String = "") -> void:
	for child in _level_list.get_children():
		child.queue_free()

	var levels: Array
	if _gc_mode:
		levels = (
			BankData.get_gc_levels_by_tier(sz, rank, tier)
			if (tier == "H" or tier == "N")
			else BankData.get_gc_levels(sz, rank)
		)
	elif tier == "H" or tier == "N":
		levels = (
			BankData.get_lk_style_levels_by_tier(sz, rank, tier)
			if _lk_style_mode
			else BankData.get_levels_by_tier(sz, rank, tier)
		)
	else:
		levels = (
			BankData.get_lk_style_levels(sz, rank)
			if _lk_style_mode
			else BankData.get_levels(sz, rank)
		)
	for i: int in levels.size():
		var entry: Dictionary = levels[i]
		_level_list.add_child(_make_level_item(entry, sz, rank, i, levels, tier))

		if i < levels.size() - 1:
			var sep := ColorRect.new()
			sep.color = _COLOR_SEPARATOR
			sep.custom_minimum_size = Vector2(0, 2)
			_level_list.add_child(sep)


# 造关卡列表一行：序号 + 步数 + 难度标签，点击把这一关的数据交给 GamePage
func _make_level_item(
	entry: Dictionary, sz: int, rank: int, i: int, levels: Array = [], tier: String = ""
) -> Button:
	# 徽章色：H 档查 _RANK_H_INFO，普通档查 _RANK_INFO，越界则用灰色
	var badge_color: Color
	if tier == "H" and _RANK_H_INFO.has(rank):
		badge_color = _RANK_H_INFO[rank]["badge"]
	elif rank >= 1 and rank <= 5:
		badge_color = _RANK_INFO[rank - 1]["badge"]
	else:
		badge_color = _COLOR_GRAY

	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = Color(1, 1, 1, 1)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = Color(0.93, 0.93, 0.93, 1)
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 130)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_n)
	btn.add_theme_stylebox_override("focus", sf_f)
	# 闭包捕获这一行的下标 i 与 entry：点哪个开哪个
	var total: int = levels.size()
	btn.pressed.connect(
		func() -> void:
			(
				UIManager
				. show_ui(
					UiName.GAME,
					{
						"bank_mode": true,
						"bank_size": sz,
						"bank_rank": rank,
						"bank_index": i + 1,
						"bank_total": total,
						"prebuilt_regions": entry.get("regionMap", []),
						"prebuilt_solution": entry.get("solution", []),
						"level_seed": entry.get("seed", 0),
						"r1_steps": entry.get("r1", 0),
						"r2_steps": entry.get("r2", 0),
						"r3_steps": entry.get("r3", 0),
						"r4_steps": entry.get("r4", 0),
						"r5_steps": entry.get("r5", 0),
						"bank_lk_style": _lk_style_mode,
						"bank_gc": _gc_mode,
						"bank_tier_h": tier == "H",
						"bank_tier": tier,
					}
				)
			)
	)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 40.0
	hbox.offset_right = -40.0

	var nl := Label.new()
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.text = "#%d" % (i + 1)
	nl.add_theme_font_size_override("font_size", 40)
	nl.add_theme_color_override("font_color", _COLOR_TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(nl)

	var steps: int = entry.get("steps", 0)
	if steps > 0:
		var sl := Label.new()
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.text = "%d步" % steps
		sl.add_theme_font_size_override("font_size", 26)
		sl.add_theme_color_override("font_color", _COLOR_GRAY)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.custom_minimum_size = Vector2(80, 0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(sl)

	var tl := Label.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.text = ("R%dH" % rank) if tier == "H" else ("R%d" % rank)
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", badge_color)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.custom_minimum_size = Vector2(80, 0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(tl)

	var al := Label.new()
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al.text = "›"
	al.add_theme_font_size_override("font_size", 50)
	al.add_theme_color_override("font_color", _COLOR_GRAY)
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	al.custom_minimum_size = Vector2(50, 0)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(al)

	return btn


# ================= 返回按钮 =================
# 顶栏返回：切回主页 UI 并隐藏题库页
func _on_back_btn_pressed() -> void:
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.BANK)


# 难度页返回：按模式退回 LK 优化尺寸页 / 常规尺寸页 / 首页
func _on_tier_back_btn_pressed() -> void:
	if _lk_style_mode:
		_show_lk_style_size_panel()
	elif _regular_mode:
		_show_regular_size_panel()
	else:
		_show_size_panel()


# 关卡列表返回：SP 回首页，其余回难度页（LK 优化回它自己的尺寸页）
func _on_list_back_btn_pressed() -> void:
	if _sp_mode:
		_show_size_panel()
	elif _lk_style_mode:
		_show_lk_style_tier_panel(_selected_size)
	else:
		_show_tier_panel(_selected_size)


# LK 页返回首页
func _on_lk_back_btn_pressed() -> void:
	_show_size_panel()


# LK 优化尺寸页返回首页
func _on_lkss_back_btn_pressed() -> void:
	_show_size_panel()


# ================= SP 特殊图案题库 =================
# 显示 SP 列表：复用关卡列表面板，只换标题与数据源
func _show_sp_panel() -> void:
	_sp_mode = true
	_hide_all_panels()
	_build_sp_list()
	_list_title.text = "SP 特殊图案题库"
	_list_panel.visible = true


# 重建 SP 列表：一行一个图案关
func _build_sp_list() -> void:
	for child in _level_list.get_children():
		child.queue_free()
	var sp_levels: Array = BankData.get_sp_levels()
	for i: int in sp_levels.size():
		var entry: Dictionary = sp_levels[i]
		_level_list.add_child(_make_sp_item(entry, i))
		if i < sp_levels.size() - 1:
			var sep := ColorRect.new()
			sep.color = _COLOR_SEPARATOR
			sep.custom_minimum_size = Vector2(0, 2)
			_level_list.add_child(sep)


# 造 SP 一行：图案名 + 尺寸/难度 + 难度徽章，点击时额外把 colorMap 传给 GamePage
func _make_sp_item(entry: Dictionary, i: int) -> Button:
	var sz: int = entry.get("size", 9)
	var rank: int = entry.get("r", 1)
	var pattern: String = entry.get("pattern", "")

	var rank_color: Color = (
		_RANK_INFO[rank - 1]["badge"] if rank >= 1 and rank <= 5 else _COLOR_GRAY
	)

	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = Color(1, 1, 1, 1)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = Color(0.93, 0.93, 0.93, 1)
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 140)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_n)
	btn.add_theme_stylebox_override("focus", sf_f)

	# SP 专用：每关自带配色表，开局时要一起传过去
	var cm_raw: Array = entry.get("colorMap", [])

	btn.pressed.connect(
		func() -> void:
			var raw_sol: Array = entry.get("solution", [])
			var raw_reg: Array = entry.get("regionMap", [])
			(
				UIManager
				. show_ui(
					UiName.GAME,
					{
						"bank_mode": true,
						"bank_size": sz,
						"bank_rank": rank,
						"bank_index": i + 1,
						"bank_total": BankData.get_sp_level_count(),
						"prebuilt_regions": raw_reg,
						"prebuilt_solution": raw_sol,
						"level_seed": entry.get("id", 0),
						"r1_steps": entry.get("r1", 0),
						"r2_steps": entry.get("r2", 0),
						"r3_steps": entry.get("r3", 0),
						"r4_steps": entry.get("r4", 0),
						"r5_steps": entry.get("r5", 0),
						"bank_lk_style": false,
						"bank_sp": true,
						"custom_color_map": cm_raw,
					}
				)
			)
	)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 40.0
	hbox.offset_right = -40.0

	var num_lbl := Label.new()
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num_lbl.text = "#%d" % (i + 1)
	num_lbl.add_theme_font_size_override("font_size", 38)
	num_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	num_lbl.custom_minimum_size = Vector2(80, 0)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(num_lbl)

	var info_vbox := VBoxContainer.new()
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(info_vbox)

	var pattern_lbl := Label.new()
	pattern_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pattern_lbl.text = pattern
	pattern_lbl.add_theme_font_size_override("font_size", 46)
	pattern_lbl.add_theme_color_override("font_color", _COLOR_TEXT)
	info_vbox.add_child(pattern_lbl)

	var meta_lbl := Label.new()
	meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_lbl.text = "%d×%d  R%d" % [sz, sz, rank]
	meta_lbl.add_theme_font_size_override("font_size", 26)
	meta_lbl.add_theme_color_override("font_color", _COLOR_GRAY)
	info_vbox.add_child(meta_lbl)

	var sf_badge := StyleBoxFlat.new()
	sf_badge.bg_color = rank_color
	sf_badge.set_corner_radius_all(10)
	sf_badge.content_margin_left = 14
	sf_badge.content_margin_right = 14
	sf_badge.content_margin_top = 4
	sf_badge.content_margin_bottom = 4
	var badge_panel := PanelContainer.new()
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_theme_stylebox_override("panel", sf_badge)
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(badge_panel)
	var badge_lbl := Label.new()
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_lbl.text = "R%d" % rank
	badge_lbl.add_theme_font_size_override("font_size", 28)
	badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	badge_panel.add_child(badge_lbl)

	return btn


# 造首页「SP 特殊图案题库」卡：橙色主题，副标题写「数字图案 共 N 关」
func _make_sp_card(count: int) -> Button:
	var sf_n := StyleBoxFlat.new()
	sf_n.bg_color = Color("#fff3e0")
	sf_n.set_corner_radius_all(24)
	sf_n.shadow_color = Color(0, 0, 0, 0.1)
	sf_n.shadow_size = 5
	sf_n.shadow_offset = Vector2(0, 3)
	var sf_p := StyleBoxFlat.new()
	sf_p.bg_color = Color("#ffe0b2")
	sf_p.set_corner_radius_all(24)
	sf_p.set_border_width_all(3)
	sf_p.border_color = Color("#ff9800")
	var sf_f := StyleBoxFlat.new()
	sf_f.bg_color = Color(0, 0, 0, 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 170)
	btn.add_theme_stylebox_override("normal", sf_n)
	btn.add_theme_stylebox_override("pressed", sf_p)
	btn.add_theme_stylebox_override("hover", sf_p)
	btn.add_theme_stylebox_override("focus", sf_f)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48.0
	hbox.offset_right = -30.0

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.text = "SP 特殊图案题库"
	title_lbl.add_theme_font_size_override("font_size", 40)
	title_lbl.add_theme_color_override("font_color", Color("#e65100"))
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.text = "数字图案  共 %d 关" % count
	sub_lbl.add_theme_font_size_override("font_size", 28)
	sub_lbl.add_theme_color_override("font_color", Color("#bf360c"))
	vbox.add_child(sub_lbl)

	var arrow_lbl := Label.new()
	arrow_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_lbl.text = "›"
	arrow_lbl.add_theme_font_size_override("font_size", 50)
	arrow_lbl.add_theme_color_override("font_color", _COLOR_GRAY)
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_lbl.custom_minimum_size = Vector2(50, 0)
	arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(arrow_lbl)

	return btn
