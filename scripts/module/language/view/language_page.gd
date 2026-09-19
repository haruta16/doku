# 语言选择弹窗：列表 = 系统语言置顶 + 9 个常用语言（系统语言不在其中时共 10 项）；按「确定」立刻切 locale 并写入存档
# 不需要重启：LanguageManager.set_locale 直接改 TranslationServer，各页面收到翻译变化通知后自行刷新
class_name LanguagePage
extends UIFrameWindow

# 选项按钮的场景（LanguageOption：本族语名 + 副标题 + 选中勾）
const _OPTION_SCENE: PackedScene = preload("res://scripts/module/language/ui/language_option.tscn")

# ---- 固定提供的 9 个语言：locale / 本族语名 / 名字翻译 key ----
const _OPTIONS: Array[Dictionary] = [
	{"locale": "en", "native": "English", "key": "LANG_NAME_EN"},
	{"locale": "ja", "native": "日本語", "key": "LANG_NAME_JA"},
	{"locale": "es", "native": "Español", "key": "LANG_NAME_ES"},
	{"locale": "fr", "native": "Français", "key": "LANG_NAME_FR"},
	{"locale": "de", "native": "Deutsch", "key": "LANG_NAME_DE"},
	{"locale": "ru", "native": "Русский", "key": "LANG_NAME_RU"},
	{"locale": "pt", "native": "Português", "key": "LANG_NAME_PT"},
	{"locale": "ko", "native": "한국어", "key": "LANG_NAME_KO"},
	{"locale": "tr", "native": "Türkçe", "key": "LANG_NAME_TR"},
]

# ---- 本族语名查表：只在系统语言不属于上面 9 个时，用来给置顶项取名字 ----
const _NATIVE_NAMES: Dictionary = {
	"en": "English",
	"zh": "简体中文",
	"pt": "Português",
	"hi": "हिन्दी",
	"id": "Bahasa Indonesia",
	"fil": "Filipino",
	"ru": "Русский",
	"ja": "日本語",
	"de": "Deutsch",
	"fr": "Français",
	"ko": "한국어",
	"es": "Español",
	"az": "Azərbaycan",
	"be": "Беларуская",
	"hr": "Hrvatski",
	"cs": "Čeština",
	"da": "Dansk",
	"ar": "العربية",
	"fi": "Suomi",
	"el": "Ελληνικά",
	"hu": "Magyar",
	"fa": "فارسی",
	"he": "עברית",
	"it": "Italiano",
	"lt": "Lietuvių",
	"ms": "Bahasa Melayu",
	"nl": "Nederlands",
	"nb": "Norsk",
	"pl": "Polski",
	"ro": "Română",
	"sk": "Slovenčina",
	"sv": "Svenska",
	"th": "ไทย",
	"tr": "Türkçe",
	"uk": "Українська",
	"uz": "Oʻzbek",
	"vi": "Tiếng Việt",
	"af": "Afrikaans",
	"am": "አማርኛ",
	"bn": "বাংলা",
	"bs": "Bosanski",
	"ca": "Català",
	"gu": "ગુજરાતી",
	"is": "Íslenska",
	"kk": "Қазақ",
	"km": "ខ្មែរ",
	"kn": "ಕನ್ನಡ",
	"lo": "ລາວ",
	"mk": "Македонски",
	"ml": "മലയാളം",
	"mn": "Монгол",
	"mr": "मराठी",
	"ne": "नेपाली",
	"pa": "ਪੰਜਾਬੀ",
	"si": "සිංහල",
	"sl": "Slovenščina",
	"sr": "Српски",
	"sw": "Kiswahili",
	"ta": "தமிழ்",
	"te": "తెలుగు",
	"ur": "اردو",
}

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _scroll: ScrollContainer = $Root/Content/ScrollContainer  # 可滚动的列表容器
@onready var _options_list: VBoxContainer = $Root/Content/ScrollContainer/OptionsList  # 选项按钮的父节点（运行时动态增删）
@onready var _yes_btn: Button = $Root/Content/YesBtn/Bg  # 「确定」按钮

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer  # 弹窗动画（GenericPopup：Mark 之前为开场段，之后为关闭段）

# ---- 运行时状态 ----
var _display: Array[Dictionary] = []  # 本次实际显示的选项列表
var _option_nodes: Array[LanguageOption] = []  # 已实例化的选项节点
var _selected_index: int = -1  # 当前选中的下标，-1 表示没有

var _press_scroll_v: int = 0  # 按下选项时的滚动位置
const _SCROLL_TAP_TOLERANCE: int = 6  # 滚动位移容差（像素），超过就当成滑动

var _confirmed: bool = false  # 是否已按过确定


# ================= 生命周期 =================
# 创建时调用一次：清掉场景里预置的选项节点，并给滚动容器加拖拽助手
func on_create() -> void:
	# 场景里可能留了编辑期占位节点，先全部移除
	for child in _options_list.get_children():
		_options_list.remove_child(child)
		child.queue_free()

	# ScrollDragHelper 让 ScrollContainer 支持拖拽滚动（真机手感）
	ScrollDragHelper.attach(_scroll, true)


# 每次被显示时调用：构建列表、按需建节点、绑信号、定位当前语言
func on_show(_params: Dictionary = {}) -> void:
	# 复位确认标记（上一次的「确定」不影响这次的关闭埋点）
	_confirmed = false
	# 系统语言会被排到第一位
	_display = _build_display()
	# 节点只增不减，先保证够用
	_ensure_option_nodes(_display.size())

	# 逐个绑定：按下先记下滚动位置，抬起时才算点击
	for i in range(_display.size()):
		# 闭包捕获的是循环变量，所以另存一份 idx
		var idx := i

		# 连的信号由 connect_managed 管理，窗口隐藏时自动断开
		connect_managed(
			_option_nodes[i].button_down, func() -> void: _press_scroll_v = _scroll.scroll_vertical
		)
		connect_managed(_option_nodes[i].pressed, func() -> void: _on_option_pressed(idx))
	# 确定按钮的信号同样交给 connect_managed
	connect_managed(_yes_btn.pressed, _on_yes_pressed)
	# 文案：本族语名 + 按当前语言翻译出来的名字
	_refresh_labels()
	# 定位当前生效的语言（存档优先，没选过则跟随系统）
	_selected_index = _resolve_current_index()
	_refresh_selection()

	# 每次打开都回到列表顶部（延后一帧，等布局完成再设）
	_scroll.set_deferred("scroll_vertical", 0)

	# 播开场动画
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


# 每次被隐藏时调用：没点过确定就补一条「取消」埋点，然后播关闭动画
func on_hide() -> void:
	if not _confirmed:
		Tracker.track_btn_click(Tracker.Btn.LANGUAGE_CANCEL, self)
	# 等关闭动画播完（UIManager 会 await on_hide）
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


# 埋点用的弹窗名（Tracker.Dlg.LANGUAGE_PICKER）
func get_dlg_name() -> String:
	return Tracker.Dlg.LANGUAGE_PICKER


# ================= 列表构建 =================
# 拼出要显示的语言列表：系统语言置顶，其余按 _OPTIONS 原顺序
func _build_display() -> Array[Dictionary]:
	# 系统语言的解析结果（不支持的语言会回落成 en）
	var sys: String = LanguageManager.resolve_system_locale()
	# 只取主语言码，用于模糊匹配
	var sys_main: String = sys.split("_")[0]
	# -1 表示没在 _OPTIONS 里命中
	var matched: int = -1
	# 先按完整 locale 精确匹配
	for i in range(_OPTIONS.size()):
		if _OPTIONS[i]["locale"] == sys:
			matched = i
			break
	# 没命中再按主语言码匹配（如 en_US 命中 en）
	if matched == -1:
		for i in range(_OPTIONS.size()):
			if String(_OPTIONS[i]["locale"]).split("_")[0] == sys_main:
				matched = i
				break
	# 命中时：命中项排第一，其余保持原顺序
	var list: Array[Dictionary] = []
	if matched != -1:
		list.append(_OPTIONS[matched])
		for i in range(_OPTIONS.size()):
			if i != matched:
				list.append(_OPTIONS[i])
	# 中文特殊处理：_OPTIONS 里没有 zh，临时补一个 zh_CN 项放最前
	elif sys_main == "zh":
		list.append({"locale": "zh_CN", "native": _NATIVE_NAMES["zh"], "key": "LANG_NAME_ZH_CN"})
		for opt: Dictionary in _OPTIONS:
			list.append(opt)
	# 其它未收录语言：临时补一项，本族语名查表、查不到就用 locale 原文
	else:
		# _NATIVE_NAMES 里没有就退回系统 locale 原文
		var native: String = _NATIVE_NAMES.get(sys_main, sys)
		var name_key: String = "LANG_NAME_" + sys_main.to_upper()
		# 翻译 key 按主语言码拼（如 LANG_NAME_CS）
		list.append({"locale": sys, "native": native, "key": name_key})
		for opt: Dictionary in _OPTIONS:
			list.append(opt)
	return list


# 按需实例化选项节点：缺多少补多少，多余的隐藏
func _ensure_option_nodes(count: int) -> void:
	while _option_nodes.size() < count:
		var opt := _OPTION_SCENE.instantiate() as LanguageOption
		_options_list.add_child(opt)
		_option_nodes.append(opt)
	for i in range(_option_nodes.size()):
		# 节点是复用的，这里只是把多出来的藏起来
		_option_nodes[i].visible = (i < count)


# 刷新每个选项的文案：主标题是本族语名，副标题优先用翻译
func _refresh_labels() -> void:
	for i in range(_display.size()):
		# 显示列表与节点下标一一对应
		var opt: Dictionary = _display[i]
		var key: String = opt["key"]
		var subtitle: String = opt["native"]
		# key 为空表示这项没配翻译
		if key != "":
			var translated: String = tr(key)
			if translated != key:
				# tr 找不到 key 时会原样返回 key，这种情况就退回本族语名
				subtitle = translated
		_option_nodes[i].setup(opt["native"], subtitle)


# 算出当前生效语言在显示列表里的下标
func _resolve_current_index() -> int:
	# 存档里玩家选过的 locale
	var applied: String = GameState.get_apply_locale()
	# 没选过就跟随系统语言
	if applied == "":
		applied = LanguageManager.resolve_system_locale()
	# 先精确匹配（locale 完全相同）
	for i in range(_display.size()):
		if _display[i]["locale"] == applied:
			return i

	# 再按主语言码匹配（如存档 zh_CN、列表里只有 zh_TW）
	var main: String = applied.split("_")[0]
	for i in range(_display.size()):
		if String(_display[i]["locale"]).split("_")[0] == main:
			return i

	# 都没匹配上返回 -1，表示不选中任何一项
	return -1


# ================= 交互 =================
# 点选一项：只改选中态，不立刻生效（要按「确定」）
func _on_option_pressed(idx: int) -> void:
	# 下标越界直接忽略
	if idx < 0 or idx >= _display.size():
		return

	# 按下到抬起之间如果列表滚动了，说明用户在滑动而不是点选
	if absi(_scroll.scroll_vertical - _press_scroll_v) > _SCROLL_TAP_TOLERANCE:
		return
	_selected_index = idx
	_refresh_selection()


# 按「确定」：切换语言并关闭自己
func _on_yes_pressed() -> void:
	# 没有有效选中项就不做任何事
	if _selected_index < 0 or _selected_index >= _display.size():
		return
	var locale: String = _display[_selected_index]["locale"]

	# 埋点：确定切换语言
	Tracker.track_btn_click(Tracker.Btn.LANGUAGE_CONFIRM, self)
	# 把语言作为用户属性上报（用于后台分语言看数据）
	Tracker.track_user_property_ui_language(locale)
	_confirmed = true
	# 立刻生效：换掉 TranslationServer 的 locale，各页面收到通知自行刷新
	LanguageManager.set_locale(locale)
	# 写入存档，下次启动 apply_system_locale 会读它
	GameState.set_apply_locale(locale)
	# 关掉自己（因为 _confirmed 为 true，on_hide 不会再补取消埋点）
	UIManager.hide_ui(get_ui_name())


# 刷新所有选项的选中态
func _refresh_selection() -> void:
	for i in range(_display.size()):
		_option_nodes[i].set_selected(i == _selected_index)
