# 作弊面板命令集：把开发用的调试操作注册成 CheatBus 命令与 7 个标签页
# 只在非 release 构建由 launcher.gd add_child 进来；_ready 先清空再注册，重载场景不会重复
extends Node

# ---- 命令表 ----
var _command_defs: Array = [] # {name, label, default_args, handler}；没有 handler 的由对局页自己订阅处理

var _clickdbg_enabled: bool = false # clickdbg 开关：打开后打印每次点击命中的节点

# ---- 「日志」页的过滤状态（切走再回来还保留） ----
# show_info/show_warn/show_error 是等级开关，keyword 是关键词过滤
var _log_filter_state: Dictionary = {
	"show_info": true, "show_warn": true, "show_error": true, "keyword": ""
}


# ================= 初始化 ===================
# 面板初始化：清掉上一份注册（场景重载会再 new 一份），登记 AB 参数、命令、标签页与分发
func _ready() -> void:
	# 三条 clear 先把上一份注册清干净（launcher 重载会再 new 一份，不清会重复注册）
	CheatBus.clear_commands()
	CheatBus.clear_tabs()
	CheatBus.clear_ab_params()
	_register_ab_params()
	# 命令表：name 是输入框里敲的名字，label 是按钮文案，default_args 会预填进输入框
	# 没有 handler 的命令（win / draft_win / lives / lifeplus / dumpjson）由对局页自己订阅处理
	_command_defs = [
		{"name": "re_login", "label": "重新登录(重看splash文案)", "handler": _cmd_re_login},
		{"name": "reset_tutorial", "label": "重置引导", "handler": _cmd_reset_tutorial},
		{"name": "clear", "label": "清理存档并退出", "handler": _cmd_clear},
		{"name": "savetest", "label": "存档容错自检(8 case)", "handler": _cmd_savetest},
		{"name": "speed", "label": "设置游戏速度倍率", "handler": _cmd_speed, "default_args": "1.0"},
		{"name": "kill", "label": "杀死进程", "handler": _cmd_kill},
		{"name": "vibrate", "label": "测试震动", "handler": _cmd_vibrate},
		{"name": "feedback", "label": "打开反馈页", "handler": _cmd_feedback},
		{"name": "show_cmp", "label": "强制显示CMP行并开设置", "handler": _cmd_show_cmp},
		{"name": "win", "label": "立即胜利"},
		{"name": "draft_win", "label": "草稿全填+Apply"},
		{"name": "level", "label": "跳关", "default_args": "1", "handler": _cmd_level},
		{"name": "lives", "label": "设置生命", "default_args": "3"},
		{"name": "lifeplus", "label": "+1血特效(1首次带引导/0之后)", "default_args": "1"},
		{
			"name": "lifeplus_sec",
			"label": "+1血触发秒门槛(默认60)",
			"default_args": "10",
			"handler": _cmd_lifeplus_sec
		},
		{"name": "locate", "label": "增加定位", "default_args": "3", "handler": _cmd_locate},
		{"name": "hint", "label": "增加提示", "default_args": "3", "handler": _cmd_hint},
		{"name": "undo", "label": "增加撤销", "default_args": "3", "handler": _cmd_undo},
		{
			"name": "free",
			"label": "道具免费态(hint/locate/all/off)",
			"default_args": "all",
			"handler": _cmd_free
		},
		{"name": "daily", "label": "每日挑战", "handler": _cmd_daily},
		{
			"name": "daily_top",
			"label": "设置每日Top%",
			"default_args": "4.1",
			"handler": _cmd_daily_top
		},
		{"name": "streak", "label": "打卡主页", "handler": _cmd_streak_open},
		{"name": "streak_clear", "label": "清今日打卡", "handler": _cmd_streak_clear},
		{"name": "streak_skip", "label": "跨天", "handler": _cmd_streak_skip},
		{"name": "streak_6", "label": "6天已打+今未打", "handler": _cmd_streak_6},
		{"name": "bank", "label": "打开题库", "handler": _cmd_bank},
		{"name": "level_json", "label": "json开局", "handler": _cmd_level_json},
		{"name": "dumpjson", "label": "导出题目JSON(0=局面 1=初始)", "default_args": "1"},
		{"name": "playtest", "label": "玩家行为模拟", "handler": _cmd_playtest},
		{"name": "show_debug_tools", "label": "显示调试工具栏", "handler": _cmd_show_debug_tools},
		{
			"name": "bank_preview",
			"label": "预览题库关卡+变换",
			"default_args": "1 0 reg_10_3",
			"handler": _cmd_bank_preview
		},
		{"name": "reset_rate_us", "label": "重置评分弹窗", "handler": _cmd_reset_rate_us},
		{"name": "ad_debug", "label": "打开广告调试器", "handler": _cmd_ad_debug},
		{"name": "hide_ui", "label": "隐藏UI", "handler": _cmd_hide_ui},
		{
			"name": "mock_ad_fail",
			"label": "模拟广告加载失败回调(iOS,验证MVAdError桥接)",
			"handler": _cmd_mock_ad_fail
		},
		{"name": "inter", "label": "弹插屏", "handler": _cmd_inter},
		{"name": "reward", "label": "弹激励视频", "handler": _cmd_reward},
		{
			"name": "mock_reward_miss",
			"label": "模拟视频奖励补发(0正常发奖/1漏奖补发)",
			"default_args": "1",
			"handler": _cmd_mock_reward_miss
		},
		{
			"name": "inter_prob_count",
			"label": "设置本 session 激励视频次数(inter_prob)",
			"default_args": "3",
			"handler": _cmd_inter_prob_count
		},
		{"name": "add_session", "label": "增加Session", "handler": _cmd_add_session},
		{"name": "ab", "label": "设置AB参数", "default_args": "region_color 0", "handler": _cmd_ab},
		{"name": "ab_debug", "label": "ABTest分流调试", "handler": _cmd_ab_debug},
		{"name": "ab_tag", "label": "打印染色", "handler": _cmd_ab_tag},
		{
			"name": "clickdbg",
			"label": "打印点击命中节点(on/off/toggle)",
			"default_args": "toggle",
			"handler": _cmd_clickdbg
		},
		{"name": "swipe_viz", "label": "保护区可视化(锁定行/列滑动范围)", "handler": _cmd_swipe_viz},
		{
			"name": "ac_offset",
			"label": "AutoComplete Y偏移",
			"default_args": "0",
			"handler": _cmd_ac_offset
		},
		{"name": "reset_first_easy", "label": "重置首局降档", "handler": _cmd_reset_first_easy},
		{
			"name": "reset_auto_mark_tutorial",
			"label": "重置 auto_mark 组2 新手引导",
			"handler": _cmd_reset_auto_mark_tutorial
		},
		{
			"name": "daily_auto_mark_popup",
			"label": "弹 daily auto_mark 引导弹窗(组5)",
			"handler": _cmd_daily_auto_mark_popup
		},
		{
			"name": "reset_daily_auto_mark",
			"label": "清今日 daily auto_mark 激活(便于反复测组5)",
			"handler": _cmd_reset_daily_auto_mark
		},
		{
			"name": "reset_free_auto_mark",
			"label": "清生涯 daily auto_mark FREE(便于反复测组5 首次免费)",
			"handler": _cmd_reset_free_auto_mark
		},
		{"name": "toast", "label": "弹Toast", "default_args": "Hello Toast!", "handler": _cmd_toast},
		{"name": "luid", "label": "获取LUID并复制", "handler": _cmd_luid},
		{"name": "uuid", "label": "获取UUID并复制", "handler": _cmd_uuid},
		{"name": "test_att", "label": "测试ATT流程", "handler": _cmd_test_att, "editor_only": true},
	]
	# 生成 CheatCommand 并注册给 CheatBus
	_register_commands()
	# 注册 7 个标签页的构建函数（切到该页时 CheatPanel 才调用）
	_register_tabs()
	# 输入框回车后 CheatBus 发命令，这里分发到对应 handler
	CheatBus.command_issued.connect(_on_command_issued)


# ================= 标签页构建 ===================
# 注册标签页；builder 由 CheatPanel 在切页时调用，签名是 (ScrollContainer, CheatPanel)
func _register_tabs() -> void:
	# 命令按钮墙（平铺 + 搜索）
	CheatBus.register_tab("命令", _build_command_tab)
	# AB 参数列表
	CheatBus.register_tab("AB测", _build_ab_tab)
	# 广告状态与各条门槛的 bypass 开关
	CheatBus.register_tab("广告", _build_ad_tab)
	# 语言切换
	CheatBus.register_tab("语言", _build_lang_tab)
	# 运行日志查看器
	CheatBus.register_tab("日志", _build_log_tab)
	# 题库调试（交给 PuzzleSessionTracker）
	CheatBus.register_tab("题库", _build_puzzle_tab)
	# 分页版命令：目前只有第 1 页填了内容，其余是占位
	CheatBus.register_tab("命令(新)", _build_categorized_command_tab)


# 在标签内容区上方加一条搜索栏 + 清空按钮，并把滚动内容下推；返回搜索框给调用方接过滤
func _add_tab_search_header(content: ScrollContainer, placeholder: String) -> LineEdit:
	# 搜索栏高度（像素）：滚动内容从上往下让出这么多
	const SEARCH_H: float = 96.0 # 搜索栏高度（像素）
	# 搜索栏挂到 ScrollContainer 的父节点上（那里才是整页），不能挂在滚动内容里
	var page: Control = content.get_parent()
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = SEARCH_H
	header.add_theme_constant_override("separation", 12)
	page.add_child(header)

	# 输入框：文本变化由调用方接过滤逻辑
	var search := LineEdit.new()
	search.placeholder_text = placeholder
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_vertical = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 42)
	header.add_child(search)

	# 清空按钮：顺手补发一次 text_changed，保证过滤逻辑也会跑
	var clear_btn := Button.new()
	clear_btn.text = "✕"
	clear_btn.custom_minimum_size = Vector2(110, 0)
	clear_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clear_btn.add_theme_font_size_override("font_size", 54)
	header.add_child(clear_btn)
	clear_btn.pressed.connect(
		func() -> void:
			search.text = ""
			search.text_changed.emit("")
	)

	# 把滚动内容整体下移，别被搜索栏压住
	content.offset_top = SEARCH_H
	return search


# 「命令」页：把命令表平铺成按钮墙；点按钮只把「名字 + 默认参数」填进输入框，不直接执行
func _build_command_tab(content: ScrollContainer, panel: CheatPanel) -> void:
	# 让滚动区支持鼠标拖动
	ScrollDragHelper.attach(content)
	# 搜索框：按 name / label 过滤按钮
	var search := _add_tab_search_header(content, "搜索命令(name / 名称)…")
	# 按钮最大宽度（像素），超了就裁字
	const MAX_BTN_WIDTH: float = 600.0 # 按钮最大宽度（像素）
	# 流式布局：按钮按宽度自动换行
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	content.add_child(flow)

	# [{btn, text}]：搜索时按 text 做子串匹配
	var searchable: Array = [] # [{btn, text}]：搜索时按 text 匹配

	# 每个命令一个按钮；文案优先用 label
	for cmd in CheatBus.get_commands():
		var btn := Button.new()
		btn.text = cmd.label if cmd.label != "" else cmd.name
		btn.custom_minimum_size = Vector2(0, 100)
		btn.add_theme_font_size_override("font_size", 48)
		# 闭包捕获到局部变量，避免循环变量串号
		var captured_cmd: CheatCommand = cmd # 闭包捕获到局部变量，避免循环变量串号
		# 点击只是预填输入框，真正执行交给输入框回车
		btn.pressed.connect(
			func() -> void:
				var raw: String = captured_cmd.name
				if captured_cmd.default_args != "":
					raw += " " + captured_cmd.default_args
				panel.fill_input(raw)
		)
		flow.add_child(btn)
		# 先按文字自然宽度定尺寸，过宽再限制到 MAX_BTN_WIDTH
		var natural_w: float = btn.get_minimum_size().x # 先按文字自然宽度定尺寸
		if natural_w > MAX_BTN_WIDTH:
			btn.clip_text = true
			btn.custom_minimum_size = Vector2(MAX_BTN_WIDTH, 100)
		else:
			btn.custom_minimum_size = Vector2(natural_w + 30, 100)
		searchable.append({"btn": btn, "text": (cmd.name + " " + cmd.label).to_lower()})

	# 搜索：name + label 拼起来做小写子串匹配
	search.text_changed.connect(
		func(q: String) -> void:
			var needle: String = q.strip_edges().to_lower()
			for item: Dictionary in searchable:
				item.btn.visible = needle.is_empty() or needle in item.text
	)


# 「命令(新)」页的分页表：每页一个命令名数组，只有第 1 页填了内容，其余留空占位
const _NEW_CMD_PAGES: Array = [
	["reset_first_easy", "streak", "streak_clear", "streak_skip", "streak_6"],
	[],
	[],
	[],
	[],
	[],
]


# 「命令(新)」页：上面 TabBar 分页，下面每页一个滚动区，给命令分类腾地方
func _build_categorized_command_tab(content: ScrollContainer, panel: CheatPanel) -> void:
	# 支持拖动滚动
	ScrollDragHelper.attach(content)
	# 竖向排布：TabBar + 页面容器
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	# 分页栏
	var tab_bar := TabBar.new()
	tab_bar.custom_minimum_size = Vector2(0, 80)
	tab_bar.add_theme_font_size_override("font_size", 40)
	for i: int in range(_NEW_CMD_PAGES.size()):
		tab_bar.add_tab(str(i + 1))
	vbox.add_child(tab_bar)

	# 页面容器：固定最小高度，滚动交给每一页自己
	var pages_container := Control.new()
	pages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages_container.custom_minimum_size = Vector2(0, 1800)
	vbox.add_child(pages_container)

	# 所有子页一次性建好，只切 visible，避免切页时才创建
	var sub_pages: Array[Control] = []
	for i: int in range(_NEW_CMD_PAGES.size()):
		var page := Control.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = (i == 0)
		pages_container.add_child(page)
		sub_pages.append(page)
		_build_sub_page_buttons(page, panel, _NEW_CMD_PAGES[i])

	# 切页只改可见性，不销毁重建
	tab_bar.tab_changed.connect(
		func(idx: int) -> void:
			for i: int in range(sub_pages.size()):
				sub_pages[i].visible = (i == idx)
	)


# 构建分页里的某一页：按命令名找定义并平铺成按钮（逻辑同「命令」页）
func _build_sub_page_buttons(page: Control, panel: CheatPanel, cmd_names: Array) -> void:
	# 与「命令」页一致的最大按钮宽度
	const MAX_BTN_WIDTH: float = 600.0 # 与「命令」页一致的最大按钮宽度
	# 每页自己一个滚动区，只允许竖向滚
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ScrollDragHelper.attach(scroll)
	page.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	scroll.add_child(flow)

	# 先建 name -> CheatCommand 索引，方便按名字取
	var cmd_map: Dictionary = {} # name -> CheatCommand 索引
	for cmd in CheatBus.get_commands():
		cmd_map[cmd.name] = cmd

	# 表里没有的名字直接跳过（比如该构建没注册这条命令）
	for cmd_name: String in cmd_names:
		if not cmd_map.has(cmd_name):
			continue
		var cmd: CheatCommand = cmd_map[cmd_name]
		var btn := Button.new()
		btn.text = cmd.label if cmd.label != "" else cmd.name
		btn.custom_minimum_size = Vector2(0, 100)
		btn.add_theme_font_size_override("font_size", 48)
		var captured_cmd: CheatCommand = cmd
		btn.pressed.connect(
			func() -> void:
				var raw: String = captured_cmd.name
				if captured_cmd.default_args != "":
					raw += " " + captured_cmd.default_args
				panel.fill_input(raw)
		)
		flow.add_child(btn)
		var natural_w: float = btn.get_minimum_size().x
		if natural_w > MAX_BTN_WIDTH:
			btn.clip_text = true
			btn.custom_minimum_size = Vector2(MAX_BTN_WIDTH, 100)
		else:
			btn.custom_minimum_size = Vector2(natural_w + 30, 100)


# 「AB测」页：列出所有 AB 参数与当前取值；点一行把「ab key 当前值」填进输入框
func _build_ab_tab(content: ScrollContainer, panel: CheatPanel) -> void:
	# 支持拖动滚动
	ScrollDragHelper.attach(content)
	# 搜索框：按 key / label 过滤
	var search := _add_tab_search_header(content, "搜索 AB 参数(key / 名称)…")

	# 一行一个参数，竖向排布
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	content.add_child(vbox)

	var searchable: Array = []

	# 按 key 字母序排，方便找
	var params: Array = CheatBus.get_ab_params()
	params.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["key"].to_lower() < b["key"].to_lower()
	)
	# 每行：按钮文本带当前值，点一下预填 ab 命令
	for param in params:
		var key: String = param["key"]
		var label: String = param["label"]
		# 取当前值的回调，由 AbConfigBase 提供
		var value_fn: Callable = param["current_value_fn"] # 取当前值的回调（AbConfigBase 提供）

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 110)
		row.add_theme_constant_override("separation", 20)

		var btn := Button.new()
		var cur_val: String = value_fn.call()
		btn.text = "%s  [当前: %s]" % [label, cur_val]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 110)
		btn.add_theme_font_size_override("font_size", 46)
		btn.clip_text = true
		var captured_key: String = key
		var captured_value_fn: Callable = value_fn
		btn.pressed.connect(
			func() -> void: panel.fill_input("ab %s %s" % [captured_key, captured_value_fn.call()])
		)
		row.add_child(btn)
		vbox.add_child(row)
		searchable.append({"row": row, "text": (key + " " + label).to_lower()})

	search.text_changed.connect(
		func(q: String) -> void:
			var needle: String = q.strip_edges().to_lower()
			for item: Dictionary in searchable:
				item.row.visible = needle.is_empty() or needle in item.text
	)


# 「题库」页：直接交给 PuzzleSessionTracker 构建（题库调试逻辑不放在这里）
func _build_puzzle_tab(content: ScrollContainer, _panel: CheatPanel) -> void:
	PuzzleSessionTracker.build_cheat_tab(content)


# 「日志」页：读 InGameLogBuffer，按等级/关键词过滤，每秒重绘一次
func _build_log_tab(content: ScrollContainer, _panel: CheatPanel) -> void:
	# 日志缓冲没初始化（例如没走 launcher）就给个提示
	var buf: InGameLogBuffer = InGameLogBuffer.instance
	if buf == null:
		var hint := Label.new()
		hint.text = "InGameLogBuffer 未初始化"
		hint.add_theme_font_size_override("font_size", 40)
		content.add_child(hint)
		return

	# 关掉外层滚动，改由 RichTextLabel 自己滚
	content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # 关掉外层滚动，改由 RichTextLabel 自己滚

	# 竖向排布：等级工具条 + 关键词行 + 日志正文
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	content.add_child(vbox)

	# 直接引用成员字典，改动跨标签切换保留
	var state: Dictionary = _log_filter_state # 直接引用成员字典，改动跨标签切换保留

	# 等级开关工具条
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 16)
	vbox.add_child(toolbar)

	# 小工具：按当前状态造一个等级开关按钮
	var make_toggle := func(label: String, key: String, color: Color) -> Button:
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.button_pressed = state[key]
		btn.custom_minimum_size = Vector2(0, 90)
		btn.add_theme_font_size_override("font_size", 40)
		btn.add_theme_color_override("font_pressed_color", color)
		return btn

	# Log / Warn / Error 三个等级开关
	toolbar.add_child(make_toggle.call("Log", "show_info", Color.WHITE))
	toolbar.add_child(make_toggle.call("Warn", "show_warn", Color.YELLOW))
	toolbar.add_child(make_toggle.call("Error", "show_error", Color.RED))

	# 清空按钮：清掉日志缓冲区
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size = Vector2(0, 90)
	clear_btn.add_theme_font_size_override("font_size", 40)
	toolbar.add_child(clear_btn)

	# 关键词过滤行
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 16)
	vbox.add_child(filter_row)

	# 关键词输入框：回填上次的过滤词
	var filter_input := LineEdit.new()
	filter_input.placeholder_text = "关键词过滤..."
	filter_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_input.custom_minimum_size = Vector2(0, 90)
	filter_input.add_theme_font_size_override("font_size", 38)
	filter_input.text = state.keyword
	filter_row.add_child(filter_input)

	# 日志正文：BBCode 渲染，自动跟随最新一行
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

	# 单条日志最多显示 300 字，超出截断
	const _LOG_ENTRY_MAX_CHARS: int = 300 # 单条日志最多显示 300 字

	# 重绘：按等级开关 + 关键词过滤后拼成 BBCode
	var render_log := func() -> void:
		# 时间前缀用秒（保留 1 位小数）
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
			# 关键词过滤：不区分大小写的子串匹配，没命中就跳过这条
			var text: String = e.text
			if not kw.is_empty() and text.findn(kw) == -1:
				continue
			var sec: float = e.time_ms * 0.001
			var prefix: String = "%.1f|" % sec
			# 文本过长先截断，避免一帧塞太多 BBCode
			if text.length() > _LOG_ENTRY_MAX_CHARS:
				text = text.left(_LOG_ENTRY_MAX_CHARS) + "..."
			var escaped: String = text.replace("[", "[lb]") # 转义方括号，防止日志里的 [ 被当成 BBCode 标签
			# 按等级上色：ERROR 红、WARN 黄，其余不上色
			match lv:
				InGameLogBuffer.Level.ERROR:
					lines.append("[color=red]%s%s[/color]" % [prefix, escaped])
				InGameLogBuffer.Level.WARN:
					lines.append("[color=yellow]%s%s[/color]" % [prefix, escaped])
				_:
					lines.append(prefix + escaped)
		log_label.text = "\n".join(lines) if not lines.is_empty() else "[color=gray]（暂无日志）[/color]"

	# 每秒重绘一次：日志缓冲区是被动收集的，只能轮询
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(func() -> void: render_log.call())
	vbox.add_child(timer)

	# 把三个开关接到 state，切一下立即重绘
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
	# 清空：清缓冲并重绘
	clear_btn.pressed.connect(
		func() -> void:
			buf.clear_entries()
			render_log.call()
	)
	# 关键词变化立即重绘
	filter_input.text_changed.connect(
		func(new_text: String) -> void:
			state.keyword = new_text.strip_edges()
			render_log.call()
	)

	render_log.call()


# 「语言」页：列出所有支持的语言，点一下切换并落盘
func _build_lang_tab(content: ScrollContainer, _panel: CheatPanel) -> void:
	# 支持拖动滚动
	ScrollDragHelper.attach(content)
	# 语言清单：[locale 代码, 中文名]，Godot 用 locale 代码切翻译
	const LANG_DEFS: Array = [
		["en", "英语"],
		["zh_CN", "简体中文"],
		["pt_BR", "葡萄牙语(巴西)"],
		["hi", "印地语"],
		["id", "印尼语"],
		["fil", "菲律宾语"],
		["zh_TW", "繁体中文(台湾)"],
		["ru", "俄语"],
		["ja", "日语"],
		["de", "德语"],
		["fr", "法语"],
		["ko", "韩语"],
		["pt", "葡萄牙语"],
		["es", "西班牙语"],
		["az", "阿塞拜疆语"],
		["be", "白俄罗斯语"],
		["hr", "克罗地亚语"],
		["cs", "捷克语"],
		["da", "丹麦语"],
		["ar_EG", "阿拉伯语(埃及)"],
		["fi", "芬兰语"],
		["el", "希腊语"],
		["hu", "匈牙利语"],
		["fa", "波斯语"],
		["he", "希伯来语"],
		["it", "意大利语"],
		["ar_LB", "阿拉伯语(黎巴嫩)"],
		["lt", "立陶宛语"],
		["ms", "马来语"],
		["ar_MA", "阿拉伯语(摩洛哥)"],
		["nl_NL", "荷兰语"],
		["no", "挪威语"],
		["ar_OM", "阿拉伯语(阿曼)"],
		["en_PH", "英语(菲律宾)"],
		["pl", "波兰语"],
		["ro", "罗马尼亚语"],
		["ar_SA", "阿拉伯语(沙特)"],
		["sk", "斯洛伐克语"],
		["sv", "瑞典语"],
		["th", "泰语"],
		["ar_TN", "阿拉伯语(突尼斯)"],
		["tr", "土耳其语"],
		["uk", "乌克兰语"],
		["ar_AE", "阿拉伯语(阿联酋)"],
		["uz", "乌兹别克语"],
		["vi", "越南语"],
		["af", "南非荷兰语"],
		["am", "阿姆哈拉语"],
		["bn", "孟加拉语"],
		["bs", "波斯尼亚语"],
		["ca", "加泰罗尼亚语"],
		["es_ES", "西班牙语(西班牙)"],
		["es_MX", "西班牙语(墨西哥)"],
		["es_US", "西班牙语(美洲)"],
		["fr_CA", "法语(加拿大)"],
		["gu", "古吉拉特语"],
		["is", "冰岛语"],
		["kk", "哈萨克语"],
		["km", "高棉语"],
		["kn", "卡纳达语"],
		["lo", "老挝语"],
		["mk", "马其顿语"],
		["ml", "马拉雅拉姆语"],
		["mn", "蒙古语"],
		["mr", "马拉地语"],
		["ne", "尼泊尔语"],
		["pa", "旁遮普语"],
		["pt_PT", "葡萄牙语(葡萄牙)"],
		["si", "僧伽罗语"],
		["sl", "斯洛文尼亚语"],
		["sr", "塞尔维亚语"],
		["sw", "斯瓦希里语"],
		["ta", "泰米尔语"],
		["te", "泰卢固语"],
		["ur", "乌尔都语"],
	]
	# 流式按钮墙
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	content.add_child(flow)

	# 「跟随系统」按钮：清掉手动覆盖
	var sys_btn := Button.new()
	sys_btn.text = "跟随系统"
	sys_btn.add_theme_font_size_override("font_size", 44)
	sys_btn.pressed.connect(func() -> void: _apply_locale(""))
	flow.add_child(sys_btn)
	sys_btn.custom_minimum_size = Vector2(sys_btn.get_minimum_size().x + 30, 100)

	# 每种语言一个按钮
	for d in LANG_DEFS:
		var code: String = d[0]
		var btn := Button.new()
		btn.text = d[1]
		btn.add_theme_font_size_override("font_size", 44)
		btn.pressed.connect(func() -> void: _apply_locale(code))
		flow.add_child(btn)
		btn.custom_minimum_size = Vector2(btn.get_minimum_size().x + 30, 100)


# 「广告」页：广告 SDK 状态、展示总开关，以及各条 AB 门槛的 bypass 开关
func _build_ad_tab(content: ScrollContainer, _panel: CheatPanel) -> void:
	# 支持拖动滚动
	ScrollDragHelper.attach(content)
	# 竖向排布：刷新按钮 + 四段状态文本 + 两个 bypass 分组
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	content.add_child(vbox)

	# 四段状态文本：SDK 状态 / 最近未展示原因 / 存档统计 / 其余明细
	var status_label := _make_ad_label()
	var recent_label := _make_ad_label()
	var save_label := _make_ad_label()
	var other_label := _make_ad_label()
	# 刷新闭包：重算四段文本（刷新按钮和各开关都会调它）
	var refresh := func() -> void:
		status_label.text = _ad_text_status()
		recent_label.text = _ad_text_recent()
		save_label.text = _ad_text_save()
		other_label.text = _ad_text_other()

	# 手动刷新按钮
	var refresh_btn := Button.new()
	refresh_btn.text = "刷新"
	refresh_btn.custom_minimum_size = Vector2(0, 90)
	refresh_btn.add_theme_font_size_override("font_size", 44)
	refresh_btn.pressed.connect(refresh)
	vbox.add_child(refresh_btn)

	vbox.add_child(status_label)
	_add_ad_gap(vbox)

	_build_ad_show_toggles(vbox)
	_add_ad_gap(vbox)

	vbox.add_child(recent_label)
	_add_ad_gap(vbox)

	# 插屏广告的五条 AB 门槛（勾上＝bypass，强制放行）
	_build_bypass_section(
		vbox,
		"插屏广告 bypass:",
		[
			["inter_unlock_level", [ABTestManager.inter_unlock_level]],
			["inter_unlock_session", [ABTestManager.inter_unlock_session]],
			["inter_unlock_memory", [ABTestManager.inter_unlock_memory]],
			["inter_extra_protect_lc", [ABTestManager.inter_extra_protect_lc]],
			["inter_prob", [ABTestManager.inter_prob]],
		],
		refresh
	)
	_add_ad_gap(vbox)

	# banner 广告的四条 AB 门槛
	_build_bypass_section(
		vbox,
		"banner 广告 bypass:",
		[
			["banner_unlock_session", [ABTestManager.banner_unlock_session]],
			["banner_unlock_level", [ABTestManager.banner_unlock_level]],
			["banner_extra_protect_lc", [ABTestManager.banner_extra_protect_lc]],
			["banner_unlock_diff_lc", [ABTestManager.banner_unlock_diff_lc]],
		],
		refresh
	)
	_add_ad_gap(vbox)

	vbox.add_child(save_label)
	_add_ad_gap(vbox)

	vbox.add_child(other_label)

	refresh.call()


# 广告页的段间留白（像素）
func _add_ad_gap(parent: VBoxContainer) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 28)
	parent.add_child(sp)


# ---- 广告页的字体与勾选框图标 ----
const _AD_TAB_FONT_SIZE: int = 36 # 广告页正文统一字号


# 造一个自动换行的多行文本标签（广告页统一用它）
func _make_ad_label() -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	return l


# 三个广告展示总开关：关掉后对应类型一律不展示
func _build_ad_show_toggles(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "广告展示开关:"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	parent.add_child(title)
	var grid := _make_check_grid()
	parent.add_child(grid)
	# 插屏 / 激励视频 / banner 三个开关，直接写 UniKitManager 的静态开关
	grid.add_child(
		_make_ad_check(
			"展示插屏广告",
			UniKitManager.cheat_show_interstitial,
			func(v: bool) -> void: UniKitManager.cheat_show_interstitial = v
		)
	)
	grid.add_child(
		_make_ad_check(
			"展示视频广告",
			UniKitManager.cheat_show_reward,
			func(v: bool) -> void: UniKitManager.cheat_show_reward = v
		)
	)
	grid.add_child(
		_make_ad_check(
			"展示 banner 广告",
			UniKitManager.cheat_show_banner,
			func(v: bool) -> void: UniKitManager.cheat_show_banner = v
		)
	)


# 造一个两列复选网格，广告页所有开关共用
func _make_check_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	return grid


# ---- 勾选框图标（把主题图标放大后缓存） ----
const _AD_CHECK_ICON_PX: int = 56 # 勾选框图标边长（像素）
var _ad_check_icon_checked: ImageTexture = null # 放大后的「已勾选」图标
var _ad_check_icon_unchecked: ImageTexture = null # 放大后的「未勾选」图标


# 懒加载勾选框图标：从主题里取默认图标并放大到 _AD_CHECK_ICON_PX
func _ensure_ad_check_icons() -> void:
	if _ad_check_icon_checked != null and _ad_check_icon_unchecked != null:
		return
	var tmp := CheckBox.new()
	_ad_check_icon_checked = _scale_check_icon(tmp.get_theme_icon("checked"))
	_ad_check_icon_unchecked = _scale_check_icon(tmp.get_theme_icon("unchecked"))
	tmp.free()


# 把主题图标等比缩放到指定像素（LANCZOS 插值，放大后不糊）
func _scale_check_icon(tex: Texture2D) -> ImageTexture:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img.resize(_AD_CHECK_ICON_PX, _AD_CHECK_ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


# 造一个复选项：放大图标 + 可调字号，toggled 直接接外部回调
func _make_ad_check(
	text: String, pressed: bool, on_toggled: Callable, font_size: int = _AD_TAB_FONT_SIZE
) -> CheckBox:
	_ensure_ad_check_icons()
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = pressed
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_font_size_override("font_size", font_size)
	if _ad_check_icon_checked != null:
		cb.add_theme_icon_override("checked", _ad_check_icon_checked)
	if _ad_check_icon_unchecked != null:
		cb.add_theme_icon_override("unchecked", _ad_check_icon_unchecked)
	cb.custom_minimum_size = Vector2(0, 90)
	cb.toggled.connect(on_toggled)
	return cb


# 状态段：广告 SDK 是否初始化、插屏与激励视频当前有没有填充
func _ad_text_status() -> String:
	var lines: Array[String] = []
	lines.append("广告 SDK 已初始化: %s" % str(UniKitManager.is_ad_inited()))
	lines.append(
		"插屏已 ready(有填充): %s" % str(UniKitManager.is_interstitial_valid("interstitial", "cheat"))
	)
	lines.append("激励视频已 ready(有填充): %s" % str(UniKitManager.is_reward_valid("reward", "cheat")))
	return "\n".join(lines)


# 最近段：最近一次插屏/banner 未展示原因、补发判定结果与待补发道具
func _ad_text_recent() -> String:
	return (
		"最近插屏未展示原因: %s\n最近 banner 未展示原因: %s\n最近补发判定结果: %s\n%s"
		% [
			BaseGamePage.last_interstitial_status,
			BaseGamePage.last_banner_status,
			HomePage.last_restore_status,
			_ad_text_pending_rewards()
		]
	)


# 把待补发奖励按道具类型汇总成「kind xN」
func _ad_text_pending_rewards() -> String:
	var counts: Dictionary = {}
	# 待补发记录先按广告位映射成具体道具，映射不到就归到「其它」
	for r in GameState.get_pending_rewards():
		var items: Array = UniKitManager.restore_items_for_position(str(r.get("source", "")))
		if items.is_empty():
			var other: String = "其它(%s)" % str(r.get("source", "?"))
			counts[other] = int(counts.get(other, 0)) + 1
			continue
		for it in items:
			var kind: String = str(it.get("kind", ""))
			counts[kind] = int(counts.get(kind, 0)) + int(it.get("count", 0))
	if counts.is_empty():
		return "当前待补发道具: 无"
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [k, int(counts[k])])
	return "当前待补发道具: %s" % " / ".join(parts)


# 存档段：关卡与策略等级、session 与今日完局数、活跃时长、安装天数与生命周期段
func _ad_text_save() -> String:
	var lines: Array[String] = []
	lines.append("【进度 / 关卡】")
	lines.append("当前关卡: %d" % GameState.get_current_level())
	lines.append("当前策略等级: %d" % GameState.get_current_strategy())
	lines.append("")
	lines.append("【Session / 活跃】")
	lines.append("session 计数: %d" % GameState.get_session_count())
	lines.append("本 session 完局数: %d" % GameState.get_session_played_count())
	lines.append("今日完局数: %d" % GameState.get_today_played_count())
	lines.append("今日前台活跃: %d 秒" % SessionManager.get_today_active_sec())
	lines.append("本 session 前台活跃: %d 秒" % SessionManager.get_session_active_sec())
	lines.append("")
	lines.append("【首启 / 生命周期】")

	var install_days: int = ABTestManager.living_days.days_since_first_open()
	lines.append("安装天数: %s" % ("%d 天" % install_days if install_days >= 0 else "未知(拿不到首启时间)"))

	lines.append("活跃天数: %d 天" % GameState.get_active_days())
	lines.append(
		(
			"生命周期段: 第 %d 段 / 共 %d 段"
			% [
				ABTestManager.living_days.current_segment_index() + 1,
				ABTestManager.living_days.segment_count()
			]
		)
	)
	return "\n".join(lines)


# 明细段：插屏/banner 各条 AB 门槛的当前值、判定结果与 bypass 标记
func _ad_text_other() -> String:
	var lines: Array[String] = []
	# 有活跃对局页才有「当前关/当前题」这类上下文
	var page: Node = _get_active_game_page() # 有活跃对局页才有当前关/当前题上下文
	lines.append("【插屏 AB 门槛(当前值)】")
	lines.append(
		(
			"inter_unlock_level: %s%s"
			% [
				str(ABTestManager.inter_unlock_level.value()),
				_bypass_tag(ABTestManager.inter_unlock_level)
			]
		)
	)
	lines.append(
		(
			"inter_unlock_session: %s (已解锁=%s)%s"
			% [
				str(ABTestManager.inter_unlock_session.value()),
				str(ABTestManager.inter_unlock_session.is_unlocked()),
				_bypass_tag(ABTestManager.inter_unlock_session)
			]
		)
	)
	lines.append(
		(
			"inter_unlock_memory: %s MB (设备通过=%s)%s"
			% [
				str(ABTestManager.inter_unlock_memory.value()),
				str(ABTestManager.inter_unlock_memory.is_unlocked_for_device()),
				_bypass_tag(ABTestManager.inter_unlock_memory)
			]
		)
	)
	lines.append("插屏冷却秒数: %d 秒(inter_cd_lc)" % UniKitManager.get_interstitial_cd_sec())
	lines.append(
		(
			"inter_extra_protect_lc: %s%s"
			% [
				str(ABTestManager.inter_extra_protect_lc.value()),
				_bypass_tag(ABTestManager.inter_extra_protect_lc)
			]
		)
	)
	(
		lines
		. append(
			(
				"inter_prob: %s (本 session 激励视频次数=%d, 阈值=%d, 概率=%d%%, 闸位置=最前置)%s"
				% [
					str(ABTestManager.inter_prob.value()),
					GameState.get_session_reward_view_count(),
					ABTestManager.inter_prob.get_threshold(),
					ABTestManager.inter_prob.get_show_percent(),
					_bypass_tag(ABTestManager.inter_prob),
				]
			)
		)
	)
	# 插屏运行态与最终判定：直接调对局页的判定函数，看到的就是真实结果
	lines.append("")
	lines.append("【插屏运行态】")
	lines.append("dev 广告开关: %s" % str(UniKitManager.is_debug_ad_enabled()))
	lines.append("插屏冷却中(CD): %s" % str(UniKitManager.is_interstitial_in_cd()))
	lines.append("")
	lines.append("【最终判定 _eval_start_interstitial】")
	if page != null and page.has_method("_eval_start_interstitial"):
		var r: Dictionary = page.call("_eval_start_interstitial", {}, "cheat", true)
		var reason: String = r.get("reason", "")
		lines.append("eligible: %s" % str(r.get("eligible", false)))
		lines.append("reason: %s" % (reason if reason != "" else "(可播)"))
	else:
		lines.append("(无活跃游戏页,进游戏页后点刷新可见判定结果)")
	lines.append("")

	# banner 判定还要当前关卡号与题目尺寸
	var b_level: int = -1
	var b_size: int = -1
	if page != null:
		var lc: Variant = page.get("_level_config")
		if lc is Dictionary:
			b_level = int(lc.get("level", -1))
			b_size = int(lc.get("size", -1))
	# banner 各条门槛（带当前关/当前题的实际解锁情况）
	lines.append("【Banner AB 门槛(当前值)】")
	lines.append(
		(
			"banner_unlock_level: %s%s%s"
			% [
				str(ABTestManager.banner_unlock_level.value()),
				(
					(
						" (当前关 %d 解锁=%s)"
						% [b_level, str(ABTestManager.banner_unlock_level.is_unlocked_at(b_level))]
					)
					if b_level >= 0
					else " (无活跃关)"
				),
				_bypass_tag(ABTestManager.banner_unlock_level)
			]
		)
	)
	lines.append(
		(
			"banner_unlock_session: %s (已解锁=%s)%s"
			% [
				str(ABTestManager.banner_unlock_session.value()),
				str(ABTestManager.banner_unlock_session.is_unlocked()),
				_bypass_tag(ABTestManager.banner_unlock_session)
			]
		)
	)
	# 当前是否被保护策略拦下
	var b_protect: Dictionary = ABTestManager.banner_extra_protect_lc.eval_start_banner() # 当前是否被保护策略拦下
	lines.append(
		(
			"banner_extra_protect_lc: %s (当前阻拦=%s%s)%s"
			% [
				str(ABTestManager.banner_extra_protect_lc.value()),
				str(b_protect.get("blocked", false)),
				(
					""
					if str(b_protect.get("reason", "")) == ""
					else " / " + str(b_protect.get("reason"))
				),
				_bypass_tag(ABTestManager.banner_extra_protect_lc)
			]
		)
	)
	lines.append(
		(
			"banner_unlock_diff_lc: %s%s%s"
			% [
				str(ABTestManager.banner_unlock_diff_lc.value()),
				(
					(
						" (当前 size %d 允许=%s)"
						% [
							b_size,
							str(ABTestManager.banner_unlock_diff_lc.is_unlocked_for_size(b_size))
						]
					)
					if b_size >= 0
					else " (无活跃题)"
				),
				_bypass_tag(ABTestManager.banner_unlock_diff_lc)
			]
		)
	)
	lines.append("")
	# banner 最终判定
	lines.append("【最终判定 _eval_start_banner】")
	if page != null and page.has_method("_eval_start_banner"):
		var br: Dictionary = page.call("_eval_start_banner")
		var b_reason: String = br.get("reason", "")
		lines.append("eligible: %s" % str(br.get("eligible", false)))
		lines.append("reason: %s" % (b_reason if b_reason != "" else "(可展示)"))
	else:
		lines.append("(无活跃游戏页,进游戏页后点刷新可见判定结果)")
	return "\n".join(lines)


# 造一组 bypass 复选项：勾选＝把这些 AB 配置标记成 debug_disabled（强制放行）
func _build_bypass_section(
	parent: VBoxContainer, title: String, groups: Array, refresh: Callable
) -> void:
	var section_title := Label.new()
	section_title.text = title
	section_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_title.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	parent.add_child(section_title)
	var grid := _make_check_grid()
	parent.add_child(grid)
	# 一个复选项可以对应多条 AB 配置：只要有一条被禁用就先显示未勾选
	for group: Array in groups:
		var cb_text: String = group[0]
		var cfgs: Array = group[1]
		var any_disabled: bool = false
		for c: AbConfigBase in cfgs:
			if c.is_debug_disabled():
				any_disabled = true
				break
		var captured_cfgs: Array = cfgs
		var captured_refresh: Callable = refresh
		# 勾选/取消时批量改 debug_disabled，然后刷新文本
		var on_toggled := func(pressed: bool) -> void:
			for c: AbConfigBase in captured_cfgs:
				c.set_debug_disabled(not pressed)
			captured_refresh.call()
		grid.add_child(_make_ad_check(cb_text, not any_disabled, on_toggled))


# 给被 bypass 的配置加 [已 bypass] 后缀，没有就返回空串
func _bypass_tag(cfg: AbConfigBase) -> String:
	return " [已 bypass]" if cfg != null and cfg.is_debug_disabled() else ""


# ================= 注册与命令分发 ===================
# 把 ABTestManager 的所有配置登记给 CheatBus（ab 命令与「AB测」页都靠它）
func _register_ab_params() -> void:
	for cfg: AbConfigBase in ABTestManager.get_all_configs():
		CheatBus.register_ab_param(cfg.key, cfg.cheat_label(), cfg.cheat_value_str)


# 把命令表转成 CheatCommand 注册；editor_only 的命令在非编辑器构建里跳过
func _register_commands() -> void:
	for def: Dictionary in _command_defs:
		if def.get("editor_only", false) and not OS.has_feature("editor"):
			continue
		var cmd := CheatCommand.new()
		cmd.name = def["name"]
		cmd.label = def["label"]
		cmd.default_args = def.get("default_args", "")
		CheatBus.register_command(cmd)


# 命令分发：按名字找 handler 执行；没有 handler 的命令由对局页自己订阅处理
func _on_command_issued(cmd_name: String, args: Array[String]) -> void:
	for def: Dictionary in _command_defs:
		if def["name"] == cmd_name and def.has("handler"):
			(def["handler"] as Callable).call(args)
			return


# clickdbg 打开时，打印每次鼠标按下命中的控件与它的 mouse_filter
func _input(event: InputEvent) -> void:
	if not _clickdbg_enabled:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		print("[ClickDbg] btn=%d pos=%s → (no control hovered)" % [mb.button_index, mb.position])
	else:
		print(
			(
				"[ClickDbg] btn=%d pos=%s → %s mouse_filter=%d"
				% [mb.button_index, mb.position, hovered.get_path(), hovered.mouse_filter]
			)
		)


# ================= 通用命令 ===================
# 重新登录：清掉今日闪屏标记、收起所有页面重放闪屏，3 秒兜底强制结束
func _cmd_re_login(_args: Array[String]) -> void:
	GameState.set_last_splash_date("")
	UIManager.hide_all()
	var splash := UIManager.show_ui(UiName.SPLASH) as SplashPage

	splash.loading_complete.connect(
		func() -> void:
			UIManager.hide_ui(UiName.SPLASH)
			UIManager.show_ui(UiName.HOME),
		CONNECT_ONE_SHOT
	)

	get_tree().create_timer(3.0).timeout.connect(
		func() -> void:
			if splash != null and splash.is_showing():
				splash.force_complete()
	)


# 重置引导：教程标记与关卡都退回起点，然后直接打开引导页
func _cmd_reset_tutorial(_args: Array[String]) -> void:
	GameState.set_tutorial_done(false)
	GameState.set_current_level(1)
	UIManager.show_ui(UiName.TUTORIAL)


# 清存档并退出进程（所有本地进度都会重置）
func _cmd_clear(_args: Array[String]) -> void:
	GameState.reset_all()
	get_tree().quit()


# 弹一个 Toast；参数拼成文本，缺省 Hello Toast!
func _cmd_toast(args: Array[String]) -> void:
	var msg: String = " ".join(args) if args.size() > 0 else "Hello Toast!"
	Toast.popup(msg, self)


# 直接杀掉进程（测崩溃/被系统杀掉的表现）
func _cmd_kill(_args: Array[String]) -> void:
	OS.kill(OS.get_process_id())


# 触发一次最强震动
func _cmd_vibrate(_args: Array[String]) -> void:
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)


# 打开反馈页，关闭后回主页
func _cmd_feedback(_args: Array[String]) -> void:
	var page := UIManager.show_ui(UiName.FEEDBACK)
	await page.closed
	UIManager.hide_ui(UiName.FEEDBACK)
	UIManager.show_ui(UiName.HOME)


# 强制显示设置页里的 CMP 行并打开设置页
func _cmd_show_cmp(_args: Array[String]) -> void:
	SettingPage.debug_force_show_cmp = true
	UIManager.show_ui(UiName.SETTING)
	print("[Cheat] show_cmp: 已强制显示 CMP 行并打开设置页")


# ================= 关卡与对局命令 ===================
# 跳关：改存档里的当前关，再带参数打开对局页
func _cmd_level(args: Array[String]) -> void:
	var idx: int = int(args[0]) if args.size() > 0 else 1
	GameState.cheat_jump_to_level(idx)
	UIManager.show_ui(UiName.GAME, {"level_index": idx})


# 给「定位」道具加次数：读按钮角标再累加
func _cmd_locate(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = _get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	var btn: ToolButton = page.get_node("Root/VBoxContainer/BottomTools/RevealBtn")
	page.set_tool_count("locate", btn.badge_count + amount)


# 给「提示」道具加次数
func _cmd_hint(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = _get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	var btn: ToolButton = page.get_node("Root/VBoxContainer/BottomTools/HintBtn")
	page.set_tool_count("hint", btn.badge_count + amount)


# 给「撤销」道具加次数
func _cmd_undo(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = _get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	var btn: ToolButton = page.get_node_or_null("Root/VBoxContainer/BottomTools/UndoBtn")
	if btn == null:
		return
	page.set_tool_count("undo", btn.badge_count + amount)


# 开关滑动保护区可视化（只有 swipe_protect 实验组才看得到效果）
func _cmd_swipe_viz(_args: Array[String]) -> void:
	var page: Node = _get_active_game_page()
	if page == null:
		print("[Cheat] swipe_viz: 当前无活跃游戏页")
		return
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("toggle_swipe_zone_viz"):
		print("[Cheat] swipe_viz: board_view 不可用")
		return
	var on: bool = bv.toggle_swipe_zone_viz()
	print("[Cheat] 保护区可视化: %s (需 swipe_protect 非对照组 + 滑动锁定后可见)" % ("开" if on else "关"))


# 道具免费态：hint/locate/all/off，写 BaseGamePage 的静态开关并同步工具条
func _cmd_free(args: Array[String]) -> void:
	var which: String = args[0] if args.size() > 0 else "all"
	if which not in ["hint", "locate", "all", "off"]:
		print("[Cheat] free 用法: free [hint|locate|all|off],收到: ", which)
		return
	BaseGamePage.debug_force_free_tool = "" if which == "off" else which

	var page: Node = _get_active_game_page()
	if page != null and page.has_method("_sync_tools_from_state"):
		page.call("_sync_tools_from_state")
	print('[Cheat] free → debug_force_free_tool = "%s"' % BaseGamePage.debug_force_free_tool)


# 设置 +1 血特效的触发秒门槛（写 BaseGamePage 的静态字段）
func _cmd_lifeplus_sec(args: Array[String]) -> void:
	if args.is_empty():
		print("[Cheat] lifeplus_sec 用法: lifeplus_sec <秒>")
		return
	var sec: float = float(args[0])
	if sec < 0.0:
		print("[Cheat] lifeplus_sec 秒数需 >= 0,收到: ", args[0])
		return
	BaseGamePage.debug_life_plus_min_sec = sec
	print("[Cheat] lifeplus_sec → debug_life_plus_min_sec = %.1f" % sec)


# 找当前可见的对局页（普通对局或每日挑战），没有就返回 null
func _get_active_game_page() -> Node:
	for page_name in ["game", "daily_game"]:
		var p: Node = UIManager.get_ui(page_name)
		if p != null and p is CanvasItem and (p as CanvasItem).visible:
			return p
	return null


# 打开每日挑战；带参数则覆盖「今天」的天数偏移，先清掉今日完成记录
func _cmd_daily(args: Array[String]) -> void:
	if args.is_empty():
		DailyGamePage.debug_day_override = -1
	else:
		DailyGamePage.debug_day_override = max(0, int(args[0]))
	GameState.clear_daily_completion()
	UIManager.show_ui(UiName.DAILY_GAME)


# 伪造今日每日挑战成绩为 Top N%，然后回主页（用来预览榜单样式）
func _cmd_daily_top(args: Array[String]) -> void:
	var top_pct: float = float(args[0]) if not args.is_empty() else 4.1
	var beat: float = 100.0 - top_pct
	var today: String = Time.get_date_string_from_system()
	GameState.mark_daily_completed(today, 69, beat)
	print("[Cheat] daily_top → Top %.1f%% (beat=%.1f%%)" % [top_pct, beat])
	UIManager.show_ui(UiName.HOME)


# ================= 连胜打卡命令 ===================
# 打开连胜打卡主页
func _cmd_streak_open(_args: Array[String]) -> void:
	StreakPage.open_main()


# 清掉今日打卡记录，方便反复测打卡流程
func _cmd_streak_clear(_args: Array[String]) -> void:
	StreakManager.cheat_clear_today()
	print(
		"[Cheat] streak_clear: 今日打卡已清,can_checkin_today=%s" % str(StreakManager.can_checkin_today())
	)


# 把打卡数据跨一天（测断签与连续签到）
func _cmd_streak_skip(_args: Array[String]) -> void:
	StreakManager.cheat_skip_day()
	var data: StreakData = StreakManager.get_data()
	print(
		(
			"[Cheat] streak_skip: 跨天后 streak=%d reward_cycle_day=%d"
			% [data.current_streak, data.reward_cycle_day]
		)
	)


# 造出「已连打 6 天、今天还没打」的状态：今天打卡即触发满 7 天发奖
func _cmd_streak_6(_args: Array[String]) -> void:
	StreakManager.cheat_setup_six_days()
	print("[Cheat] streak_6: 6 天已打 + 今未打,今天 do_checkin 触发满 7 发奖")


# ================= 页面跳转命令 ===================
# 打开题库页
func _cmd_bank(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.BANK)


# 打开手输 JSON 开局页
func _cmd_level_json(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.LEVEL_JSON_INPUT)


# 打开玩家行为模拟器
func _cmd_playtest(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.PLAYTEST_SIMULATOR)


# ================= 评分 / 题库 / 调试工具命令 ===================
# 重置评分弹窗的已展示标记
func _cmd_reset_rate_us(_args: Array[String]) -> void:
	GameState.reset_rate_us_shown()
	print("[Cheat] reset_rate_us → has_shown_rate_us = ", GameState.has_shown_rate_us())


# 预览题库某一条：按题池取关、可选做对称变换，然后带 prebuilt 数据直接开局
func _cmd_bank_preview(args: Array[String]) -> void:
	# 参数：序号 idx、变换编号 transform(0~11)、题池 key（类型_尺寸_rank）
	var idx: int = clampi(int(args[0]) if args.size() > 0 else 1, 1, 9999)
	var transform: int = clampi(int(args[1]) if args.size() > 1 else 0, 0, 11)
	var pool_key: String = args[2] if args.size() > 2 else "reg_10_3"

	# 解析题池 key：reg=普通池 / lks=锁样式池 / lkm=改造池
	var parts: Array = pool_key.split("_")
	if parts.size() < 3:
		print("[bank_preview] pool 格式错误，应为 类型_尺寸_rank，如 reg_10_3")
		return
	var pool_type: String = parts[0]
	var sz: int = int(parts[1])
	var rank: int = int(parts[2])

	# 按类型取题库；lkm 还要按 size 与 rank 过滤
	var levels: Array = []
	match pool_type:
		"lks":
			levels = BankData.get_lk_style_levels(sz, rank)
		"lkm":
			var all: Array = BankData.get_lk_modified_levels()
			for e in all:
				if int(e.get("size", 0)) == sz and int(e.get("maxR", e.get("r", 0))) == rank:
					levels.append(e)
		_:
			levels = BankData.get_levels(sz, rank)

	if levels.is_empty():
		print("[bank_preview] 题库为空: ", pool_key)
		return

	var entry_idx: int = (idx - 1) % levels.size() # 序号按池子大小取模，超了从头再来
	var entry: Dictionary = levels[entry_idx]
	# 题库里的 regionMap / solution 存的是字符串，先转成 int 数组
	var sol_1d: Array = []
	for v in entry.get("solution", []):
		sol_1d.append(int(v))
	var int_regions: Array = []
	for row_arr in entry.get("regionMap", []):
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	# transform > 0 时对区域与解做对称变换，用来测同一题的多种形态
	if transform > 0:
		var transformed: Array = LevelData.apply_transform(int_regions, sol_1d, sz, transform)
		int_regions = transformed[0]
		sol_1d = transformed[1]
	print(
		(
			"[bank_preview] %s #%d/%d  transform=%d  sz=%d  rank=%d"
			% [pool_key, entry_idx + 1, levels.size(), transform, sz, rank]
		)
	)
	# 用 prebuilt_* 参数开局：对局页直接用这份题目，不再自己抽题
	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"bank_mode": true,
				"bank_size": sz,
				"bank_rank": rank,
				"bank_index": idx,
				"bank_total": levels.size(),
				"prebuilt_regions": int_regions,
				"prebuilt_solution": sol_1d,
				"level_seed": int(entry.get("seed", entry.get("id", 0))),
				"_bank_transform": transform,
			}
		)
	)


# 把对局页上藏起来的调试按钮（清空、坐标）显示出来
func _cmd_show_debug_tools(_args: Array[String]) -> void:
	var page: Node = _get_active_game_page()
	if page == null:
		return
	var clear_btn: Node = page.get_node_or_null("Root/VBoxContainer/FunctionArea/ClearBtn")
	var coord_btn: Node = page.get_node_or_null("Root/VBoxContainer/BottomTools/CoordBtn")
	if clear_btn != null:
		clear_btn.visible = true
	if coord_btn != null:
		coord_btn.visible = true


# ================= 语言 / 广告 / AB / 埋点命令 ===================
# 切换语言并落盘；空 / clear / system 表示清除覆盖、跟随系统
func _apply_locale(locale: String) -> void:
	if locale == "" or locale == "clear" or locale == "system":
		GameState.set_apply_locale("")
		LanguageManager.apply_system_locale()
		print("[Cheat] locale 覆盖已清除,跟随系统 = ", LanguageManager.get_locale())
		return
	LanguageManager.set_locale(locale)
	GameState.set_apply_locale(locale)
	print("[Cheat] locale = ", LanguageManager.get_locale(), " (已落盘)")


# 打开广告调试面板
func _cmd_ad_debug(_args: Array[String]) -> void:
	UniKitManager.open_ad_debug_view()


# 隐藏/显示对局页的一批 UI 节点（截屏用）：以第一个节点的当前可见性为准整组取反
func _cmd_hide_ui(_args: Array[String]) -> void:
	var page: Node = _get_active_game_page()
	if page == null:
		return
	# 要一起切换的节点路径：顶部信息栏 + 底部道具按钮
	const PATHS: Array[String] = [
		"Root/VBoxContainer/Header/GearBtn",
		"Root/VBoxContainer/Header/LevelLabel",
		"Root/VBoxContainer/Header/SettingsBtn",
		"Root/VBoxContainer/Header/StrategyBtn",
		"Root/VBoxContainer/Header/PrevBtn",
		"Root/VBoxContainer/Header/NextBtn",
		"Root/VBoxContainer/BottomTools/RevealBtn",
		"Root/VBoxContainer/BottomTools/HintBtn",
	]

	# 先探测第一个节点现在的可见性，作为整组的目标状态
	var target_visible: bool = true
	for path: String in PATHS:
		var node: Node = page.get_node_or_null(path)
		if node != null:
			target_visible = not (node as CanvasItem).visible
			break
	for path: String in PATHS:
		var node: Node = page.get_node_or_null(path)
		if node != null:
			(node as CanvasItem).visible = target_visible


# 设置 AB 参数覆盖值：字符串类型直接传字符串，其余按整数解析
func _cmd_ab(args: Array[String]) -> void:
	if args.size() < 2:
		print("[Cheat] ab 用法: ab <key> <value>  例: ab region_color 1")
		return
	var key: String = args[0]
	var cfg: AbConfigBase = ABTestManager.find_config(key)
	if cfg == null:
		print("[Cheat] 未知 AB 参数: ", key)
		return

	var value: Variant = args[1] if typeof(cfg.default_value) == TYPE_STRING else int(args[1])
	cfg.set_debug_override(value)
	print("[Cheat] ab %s = %s" % [key, str(value)])


# 打开 AB 分流调试页
func _cmd_ab_debug(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.AB_DEBUG)


# 打印当前 AB 染色标签
func _cmd_ab_tag(_args: Array[String]) -> void:
	var tag: String = ABTestManager.get_ab_dyeing_tag()
	print('[Cheat] ab_dyeing_tag = "%s"' % tag)


# 点击命中调试开关：on / off / toggle（缺省 toggle）
func _cmd_clickdbg(args: Array[String]) -> void:
	var mode: String = args[0] if args.size() > 0 else "toggle"
	match mode:
		"on":
			_clickdbg_enabled = true
		"off":
			_clickdbg_enabled = false
		_:
			_clickdbg_enabled = not _clickdbg_enabled
	print("[ClickDbg] ", "ON" if _clickdbg_enabled else "OFF")


# iOS 专用：模拟一次广告加载失败回调，验证错误桥接
func _cmd_mock_ad_fail(_args: Array[String]) -> void:
	if not OS.has_feature("ios"):
		print("[cheat] mock_ad_fail: iOS only")
		return
	UniKitManager.debug_mock_ad_load_fail()
	print("[cheat] mock_ad_fail: dispatched")


# 主动弹一次插屏（有填充才弹）
func _cmd_inter(_args: Array[String]) -> void:
	var show_id := UniKitManager.gen_show_id()
	if UniKitManager.is_interstitial_ready("interstitial", "cheat", show_id):
		UniKitManager.try_show_interstitial("interstitial", "cheat", show_id)


# 主动弹一次激励视频（有填充才弹）
func _cmd_reward(_args: Array[String]) -> void:
	var show_id := UniKitManager.gen_show_id()
	if UniKitManager.is_reward_ready("reward", "cheat", show_id):
		UniKitManager.show_reward("reward", "cheat", show_id)


# 模拟激励视频「漏奖补发」：打开开关并补满近 3 天的正常领奖记录（去掉防刷限制）
func _cmd_mock_reward_miss(args: Array[String]) -> void:
	var enabled: bool = (int(args[0]) if args.size() > 0 else 1) != 0
	UniKitManager.set_debug_reward_miss(enabled)

	if enabled:
		var now: int = int(Time.get_unix_time_from_system())
		for _i in 3:
			GameState.record_normal_reward(now)
	print(
		(
			"[Cheat] mock_reward_miss = %d (%s)%s"
			% [
				int(enabled),
				"漏奖补发" if enabled else "正常发奖",
				" | 已补满防刷(近3天3次正常领奖)" if enabled else "",
			]
		)
	)


# 手动推进一次 session（测跨 session 的广告与统计门槛）
func _cmd_add_session(_args: Array[String]) -> void:
	SessionManager.debug_advance_session()
	print("[Cheat] add_session → session 计数 = ", GameState.get_session_count())


# 设置本 session 的激励视频观看次数（inter_prob 门槛用它判断）
func _cmd_inter_prob_count(args: Array[String]) -> void:
	var n: int = int(args[0]) if args.size() > 0 else 3
	GameState.set_session_reward_view_count(n)
	print(
		"[Cheat] inter_prob_count → 本 session 激励视频次数 = ", GameState.get_session_reward_view_count()
	)


# 调对局页自动完成按钮的 Y 偏移（写对局页内部字段）
func _cmd_ac_offset(args: Array[String]) -> void:
	var page: Node = _get_active_game_page()
	if page == null:
		print("[Cheat] ac_offset: 需要在 game/daily_game 页面")
		return
	var offset_val: float = float(args[0]) if args.size() > 0 else 0.0
	page._ac_btn_offset_y = offset_val
	print("[Cheat] ac_offset = ", offset_val)


# ================= 引导与 auto_mark 状态重置 ===================
# 重置「首局降档」：下次进关可再触发一次
func _cmd_reset_first_easy(_args: Array[String]) -> void:
	GameState.cheat_reset_daily_first_easy()
	print("[Cheat] reset_first_easy: 已重置,下次进关可触发首局降档")


# 重置 auto_mark 新手引导标记，下次满足条件会重新弹
func _cmd_reset_auto_mark_tutorial(_args: Array[String]) -> void:
	GameState.reset_auto_mark_tutorial_done()
	print("[Cheat] reset_auto_mark_tutorial: 已重置,下次 game_auto_mark==2 且 lv>30 进关重新触发引导")


# 直接弹每日挑战的 auto_mark 引导弹窗
func _cmd_daily_auto_mark_popup(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.DAILY_AUTO_MARK_POPUP)


# 清掉今日 auto_mark 激活标记，方便反复测该弹窗
func _cmd_reset_daily_auto_mark(_args: Array[String]) -> void:
	GameState.reset_daily_auto_mark_enabled()
	print("[Cheat] reset_daily_auto_mark: 已清今日激活,下次进 daily 重弹引导(需 game_auto_mark==5)")


# 清掉生涯级 FREE 已消费标记，方便反复测「首次免费」
func _cmd_reset_free_auto_mark(_args: Array[String]) -> void:
	GameState.reset_daily_auto_mark_free_consumed()
	print("[Cheat] reset_free_auto_mark: 已清生涯 FREE,下次进 daily(已清今日激活)弹出 FREE 模式")


# ================= 设备标识 / ATT / 存档自检 ===================
# 取 LUID 复制到剪贴板；编辑器里拿不到就给个占位值
func _cmd_luid(_args: Array[String]) -> void:
	var luid: String = UniKitManager.get_luid()
	if luid.is_empty() and OS.has_feature("editor"):
		luid = "luid"
	print("[Cheat] luid: %s" % luid)
	DisplayServer.clipboard_set(luid)
	Toast.popup("LUID: %s (已复制)" % luid, self)


# 取 UUID 复制到剪贴板（同上，编辑器给占位值）
func _cmd_uuid(_args: Array[String]) -> void:
	var uuid: String = UniKitManager.get_uuid()
	if uuid.is_empty() and OS.has_feature("editor"):
		uuid = "uuid"
	print("[Cheat] uuid: %s" % uuid)
	DisplayServer.clipboard_set(uuid)
	Toast.popup("UUID: %s (已复制)" % uuid, self)


# 编辑器专用：强制重走 launcher 的 ATT 流程（重载当前场景）
func _cmd_test_att(_args: Array[String]) -> void:
	if not OS.has_feature("editor"):
		return
	UniKitManager.debug_force_editor_test = true
	print(
		(
			"[Cheat] test_att: 重载主场景重走 launcher 流程,att_dlg_logic = %s"
			% str(ABTestManager.att_dlg_logic.value())
		)
	)
	get_tree().reload_current_scene()


# 存档容错自检：造出 8 种「主/备/旧档 好或坏」的组合，验证 SaveStore 挑档是否正确
func _cmd_savetest(_args: Array[String]) -> void:
	# 自检用的临时目录与文件名（跑完会删掉整个目录）
	var pw := "savetest_pw_0123456789ABCDEF0123"
	var dir := "user://save_test_fi/"
	var path_a := dir + "save_a.cfg"
	var path_b := dir + "save_b.cfg"
	var flag := dir + "flag.txt"
	var legacy := dir + "save_old.cfg"
	var eg := dir + "endgame.cfg"
	DirAccess.make_dir_recursive_absolute(dir)

	# 三个小工具：清场、写一份好档（加密）、写一份坏档
	var clean := func() -> void:
		for p in [path_a, path_b, flag, legacy, eg, path_a + ".tmp", path_b + ".tmp", eg + ".tmp"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	var write_good := func(p: String, marker: String) -> void:
		var c := ConfigFile.new()
		c.set_value("p", "marker", marker)
		c.save_encrypted_pass(p, pw)
	var write_corrupt := func(p: String) -> void:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("XX_garbage_not_encrypted_XX")
		f = null
	var set_flag := func(slot: String) -> void:
		var f := FileAccess.open(flag, FileAccess.WRITE)
		f.store_string(slot)
		f = null

	# 跑一个用例：按 dual 建 SaveStore，读档并比对 marker 是否符合预期
	var results: Array[String] = []
	var pass_count := {"n": 0} # 用字典当计数器：闭包里改不了外部 int
	var run_case := func(name: String, dual: bool, expect: String) -> void:
		var store := (
			SaveStore.new(pw, dir, dual, path_a, path_b, flag, legacy)
			if dual
			else SaveStore.new(pw, dir, false, eg)
		)
		var cfg := store.load_config()
		var got := "null" if cfg == null else str(cfg.get_value("p", "marker", "?"))
		var ok: bool = got == expect
		if ok:
			pass_count.n += 1 # 字典字面量语法，pass_count.n 等价于 pass_count["n"]
		var line := "%s %s got=%s expect=%s" % ["[PASS]" if ok else "[FAIL]", name, got, expect]
		results.append(line)
		print("[savetest] %s" % line)

	# 八个用例：每个都先清场再造文件，避免相互影响
	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_good.call(path_b, "B")
	run_case.call("a坏 b好(flag=A)", true, "B")
	clean.call()
	set_flag.call("A")
	write_good.call(path_a, "A")
	write_corrupt.call(path_b)
	run_case.call("a好 b坏(flag=A)", true, "A")
	clean.call()
	set_flag.call("B")
	write_corrupt.call(path_a)
	write_good.call(path_b, "B")
	run_case.call("a坏 b好(flag=B)", true, "B")
	clean.call()
	set_flag.call("B")
	write_good.call(path_a, "A")
	write_corrupt.call(path_b)
	run_case.call("a好 b坏(flag=B)", true, "A")
	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_corrupt.call(path_b)
	write_good.call(legacy, "OLD")
	run_case.call("ab坏 c好(旧档兜底)", true, "OLD")
	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_corrupt.call(path_b)
	write_corrupt.call(legacy)
	run_case.call("abc 全坏", true, "null")

	clean.call()
	write_good.call(eg, "EG")
	run_case.call("残局 好", false, "EG")
	clean.call()
	write_corrupt.call(eg)
	run_case.call("残局 坏", false, "null")

	clean.call()
	if DirAccess.dir_exists_absolute(dir):
		DirAccess.remove_absolute(dir)

	# 汇总：打印通过数并弹 Toast
	var total := results.size()
	print("[savetest] ===== %d/%d 通过 =====" % [pass_count.n, total])
	Toast.popup("存档容错自检: %d/%d 通过" % [pass_count.n, total], self)


# 设置游戏速度倍率（写 Engine.time_scale，范围 0.1~10 倍）
func _cmd_speed(args: Array[String]) -> void:
	var scale: float = float(args[0]) if args.size() > 0 else 1.0
	scale = clampf(scale, 0.1, 10.0)
	Engine.time_scale = scale # 改全局时间缩放：所有 tween / 计时器都会跟着变快
	Toast.popup("游戏速度: %.1fx" % scale, self)
