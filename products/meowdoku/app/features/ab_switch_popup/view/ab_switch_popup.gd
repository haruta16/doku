## 实验切换提示窗：根据参数显示标题、正文和奖励，动态适配文字高度与顶部探头猫。
@tool
class_name AbSwitchPopup
extends UIFrameWindow

const _POPUP_TEXT_MAX_H: float = 550.0

const _POPUP_TEXT_BASE_FS: int = 70

const _POPUP_TEXT_MIN_FS: int = 40

const _CAT_TOP_MARGIN: float = 8.0

## 猫相对背景框顶部的纵向偏移（像素），改完立刻重排
@export var cat_y_offset: float = -350:
	set(v):
		cat_y_offset = v # 写回新值
		_sync_cat() # 立即重排猫的位置

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready
var _popup_text_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Content/Panel/PopUpText # 正文
var _popup_text_probe: Label = null
@onready var _center_container: CenterContainer = $Content/CenterContainer
@onready var _title_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/Text # 标题
@onready var _btn: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Btn # 确认按钮（带 btn_text 属性）
@onready var _bg: PanelContainer = $Content/CenterContainer/BgSizeBox/Bg # 背景框：尺寸变化时要重排猫
@onready var _cat_dialog: Control = $Content/CatDialog # 探头猫
@onready var _cat_img: Control = $Content/CatDialog/CatImg
@onready var _feedback_btn: Button = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/FeedbackBtn
@onready var _tool_group: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup
@onready
var _reveal_btn: ToolButton = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup/RevealBtn
@onready var _hint_btn: ToolButton = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup/HintBtn


# ================= 生命周期 =================
func _ready() -> void:
	# 背景框缺失就没法定位
	if not is_instance_valid(_bg):
		return
	# 背景框尺寸一变就重排猫
	_bg.item_rect_changed.connect(_sync_cat)
	# 编辑器里开每帧刷新，方便所见即所得
	if Engine.is_editor_hint():
		set_process(true)
	# 等布局算完再排第一次
	call_deferred("_sync_cat")


## 编辑器专用：每帧刷新猫的位置（运行时不需要）
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_cat()


func _sync_cat() -> void:
	if not is_node_ready():
		return
	if not is_instance_valid(_bg) or not is_instance_valid(_cat_dialog):
		return

	var overhang: float = _cat_overhang()
	if not is_equal_approx(_center_container.offset_top, overhang):
		_center_container.offset_top = overhang

	var bgsizebox: Control = _bg.get_parent() as Control
	var center_container: Control = bgsizebox.get_parent() as Control
	var bg_top: float = center_container.position.y + bgsizebox.position.y + _bg.position.y
	_cat_dialog.position.y = bg_top + cat_y_offset


func _cat_overhang() -> float:
	if not is_instance_valid(_cat_img):
		return 0.0
	return maxf(0.0, -cat_y_offset - _cat_img.offset_top)


func _top_safe_inset() -> float:
	return UIManager.get_safe_insets().x


func _max_popup_text_height() -> float:
	if not is_instance_valid(_bg) or not is_instance_valid(_popup_text_txt):
		return _POPUP_TEXT_MAX_H
	var visible_h: float = get_viewport().get_visible_rect().size.y
	if visible_h <= 0.0:
		return _POPUP_TEXT_MAX_H
	var bg_other_h: float = _bg.size.y - _popup_text_txt.size.y
	var margin: float = _CAT_TOP_MARGIN + _top_safe_inset()
	return visible_h + _cat_overhang() - 2.0 * margin - bg_other_h


func on_show(params: Dictionary = {}) -> void:
	var body: String = params.get("body", "")
	if not body.is_empty():
		_popup_text_txt.text = body

	call_deferred("_fit_popup_text_height")

	var title: String = params.get("title", "")
	if not title.is_empty():
		_title_txt.text = title

	var btn_text: String = params.get("btn_text", "")
	if not btn_text.is_empty():
		_btn.set("btn_text", btn_text)

	_feedback_btn.visible = str(params.get("feedback", "")) == "1"
	_apply_reward(params.get("reward", {}))


func _apply_reward(reward: Dictionary) -> void:
	_tool_group.visible = not reward.is_empty()

	var order_lead: Control = (
		_hint_btn if ABTestManager.prop_position.is_hint_first() else _reveal_btn
	)
	if order_lead != null:
		_tool_group.move_child(order_lead, 0)
	_apply_reward_slot(_reveal_btn, int(reward.get("locate", 0)))
	_apply_reward_slot(_hint_btn, int(reward.get("hint", 0)))


func _apply_reward_slot(btn: ToolButton, count: int) -> void:
	btn.visible = count > 0
	if count > 0:
		btn.label_text = "x%d" % count


static func parse_param(param_str: String) -> Dictionary:
	var result: Dictionary = {}
	var i: int = 0
	var n: int = param_str.length()
	while i < n:
		var eq: int = param_str.find("=", i)
		if eq == -1:
			break
		var key: String = param_str.substr(i, eq - i).strip_edges()
		var val_start: int = eq + 1
		if val_start < n and param_str[val_start] == "{":
			var close: int = param_str.find("}", val_start)
			var inner: String = param_str.substr(val_start + 1, close - val_start - 1)
			var sub: Dictionary = {}
			var pairs: PackedStringArray = inner.split(",")
			for pair: String in pairs:
				var kv: PackedStringArray = pair.split("=")
				if kv.size() == 2:
					var sub_val: String = kv[1].strip_edges()
					sub[kv[0].strip_edges()] = int(sub_val) if sub_val.is_valid_int() else sub_val
			result[key] = sub
			i = close + 1
			if i < n and param_str[i] == ",":
				i += 1
		else:
			var comma: int = param_str.find(",", val_start)
			if comma == -1:
				comma = n
			result[key] = param_str.substr(val_start, comma - val_start).strip_edges()
			i = comma + 1
	return result


## 点确认按钮：关闭自己
func _on_action_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


## 点关闭按钮：关闭自己
func _on_close_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


func _fit_popup_text_height() -> void:
	if not is_showing() or not is_instance_valid(_popup_text_txt):
		return

	await get_tree().process_frame
	if not is_showing() or not is_instance_valid(_popup_text_txt):
		return
	var txt: String = atr(_popup_text_txt.text)
	if txt.is_empty():
		return
	var font: Font = _popup_text_txt.get_theme_font(&"font")
	if font == null:
		return

	var width: float = _popup_text_txt.size.x
	if width <= 0.0:
		width = 800.0
	var line_spacing: int = _popup_text_txt.get_theme_constant(&"line_spacing")
	var wrap_mode: TextServer.AutowrapMode = _popup_text_txt.autowrap_mode

	var max_h: float = minf(_POPUP_TEXT_MAX_H, _max_popup_text_height())

	var probe: Label = _ensure_popup_text_probe()
	probe.add_theme_font_override(&"font", font)
	probe.add_theme_constant_override(&"line_spacing", line_spacing)
	probe.autowrap_mode = wrap_mode
	probe.text = txt
	probe.size = Vector2(width, 1.0)

	probe.add_theme_font_size_override(&"font_size", _POPUP_TEXT_BASE_FS)
	probe.update_minimum_size()
	if probe.get_minimum_size().y <= max_h:
		_popup_text_txt.add_theme_font_size_override(&"font_size", _POPUP_TEXT_BASE_FS)
		_center_container.queue_sort()
		return

	var lo_fs: int = _POPUP_TEXT_MIN_FS
	var hi_fs: int = _POPUP_TEXT_BASE_FS - 1
	var best_fs: int = lo_fs
	while lo_fs <= hi_fs:
		var mid: int = (lo_fs + hi_fs) >> 1
		probe.add_theme_font_size_override(&"font_size", mid)
		probe.update_minimum_size()
		if probe.get_minimum_size().y <= max_h:
			best_fs = mid
			lo_fs = mid + 1
		else:
			hi_fs = mid - 1
	_popup_text_txt.add_theme_font_size_override(&"font_size", best_fs)
	_center_container.queue_sort()


func _ensure_popup_text_probe() -> Label:
	if is_instance_valid(_popup_text_probe):
		return _popup_text_probe
	_popup_text_probe = Label.new()
	_popup_text_probe.name = &"_PopupTextProbe"
	_popup_text_probe.visible = false
	_popup_text_probe.top_level = true
	_popup_text_probe.position = Vector2(-100000.0, -100000.0)
	add_child(_popup_text_probe)
	return _popup_text_probe


func _on_feedback_pressed() -> void:
	if not UniKitManager.is_online():
		Toast.popup("NETWORK_ERROR", self)
		return
	HelpshiftManager.open_faq()
