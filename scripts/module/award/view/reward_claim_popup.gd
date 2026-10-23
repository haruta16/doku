## 通用奖励领取弹窗：显示奖励条目，调用业务发放出口或直接账本后发布领取结果。
@tool
class_name RewardClaimPopup
extends UIFrameWindow

signal claimed(granted: bool)

const _KIND_LOCATE: String = "locate"
const _KIND_HINT: String = "hint"
const _SLOT_KINDS: Array[String] = [_KIND_LOCATE, _KIND_HINT]

const _POPUP_TEXT_MAX_H: float = 650.0

const _POPUP_TEXT_BASE_FS: int = 70

const _POPUP_TEXT_MIN_FS: int = 40

@export var cat_y_offset: float = -347:
	set(v):
		cat_y_offset = v
		_sync_cat()

@onready
var _popup_text_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Content/Panel/PopUpText
var _popup_text_probe: Label = null
@onready var _center_container: CenterContainer = $Content/CenterContainer
@onready var _title_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/Text
@onready var _btn: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Btn
@onready var _bg: PanelContainer = $Content/CenterContainer/BgSizeBox/Bg
@onready var _cat_dialog: Control = $Content/CatDialog
@onready var _tool_group: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup
@onready
var _reveal_btn: ToolButton = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup/RevealBtn
@onready var _hint_btn: ToolButton = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/ToolGroup/HintBtn

var _items: Array = []
var _reason: String = ""

var _claim: Callable = Callable()

var _claiming: bool = false


func _ready() -> void:
	if not is_instance_valid(_bg):
		return
	_bg.item_rect_changed.connect(_sync_cat)
	if Engine.is_editor_hint():
		set_process(true)
	call_deferred("_sync_cat")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_cat()


func _sync_cat() -> void:
	if not is_node_ready():
		return
	if not is_instance_valid(_bg) or not is_instance_valid(_cat_dialog):
		return
	var bgsizebox: Control = _bg.get_parent() as Control
	var center_container: Control = bgsizebox.get_parent() as Control
	var bg_top: float = center_container.position.y + bgsizebox.position.y + _bg.position.y
	_cat_dialog.position.y = bg_top + cat_y_offset


func on_show(params: Dictionary = {}) -> void:
	_claiming = false
	_items = params.get("items", [])
	_reason = str(params.get("reason", ""))
	_claim = params.get("claim", Callable())
	if _items.is_empty():
		push_error("RewardClaimPopup: items 必填（至少要有东西可展示）")

	elif not _claim.is_valid() and _reason.is_empty():
		push_error("RewardClaimPopup: 未传 claim 时 reason 必填（它是 dispatch 的归因参数）")

	var text_key: String = str(params.get("text", ""))
	if not text_key.is_empty():
		_popup_text_txt.text = text_key

	call_deferred("_fit_popup_text_height")

	var title_key: String = str(params.get("title", ""))
	if not title_key.is_empty():
		_title_txt.text = title_key

	var btn_key: String = str(params.get("button", ""))
	if not btn_key.is_empty():
		_btn.set("btn_text", btn_key)

	_apply_items(_items)


func _apply_items(items: Array) -> void:
	var counts: Dictionary = {}
	for kind in _SLOT_KINDS:
		counts[kind] = 0
	for it in items:
		if it == null:
			continue
		if it.category != AwardItem.Category.TOOL:
			push_warning("RewardClaimPopup: 非道具项（category=%d）不参与展示，只会随 items 发出" % it.category)
			continue
		if not counts.has(it.kind):
			push_warning("RewardClaimPopup: 道具 '%s' 没有对应展示槽，只会随 items 发出" % it.kind)
			continue
		counts[it.kind] += it.count

	var order_lead: Control = (
		_hint_btn if ABTestManager.prop_position.is_hint_first() else _reveal_btn
	)
	_tool_group.move_child(order_lead, 0)
	_apply_slot(_reveal_btn, int(counts[_KIND_LOCATE]))
	_apply_slot(_hint_btn, int(counts[_KIND_HINT]))
	_tool_group.visible = int(counts[_KIND_LOCATE]) > 0 or int(counts[_KIND_HINT]) > 0


func _apply_slot(btn: ToolButton, count: int) -> void:
	btn.visible = count > 0
	if count > 0:
		btn.label_text = "x%d" % count


## 用重入标记只领取一次，优先调用业务出口，否则通过 AwardManager 直接发放，再发布结果并关闭。
func _claim_and_close() -> void:
	if _claiming:
		return
	_claiming = true
	var granted: bool = false
	if _claim.is_valid():
		granted = bool(_claim.call())
		if not granted:
			push_error("RewardClaimPopup: 业务发放出口返回 false，奖励未发出")
	elif not _items.is_empty() and not _reason.is_empty():
		var uid: int = AwardManager.dispatch(_items, AwardManager.DisplayType.DIRECT, _reason)
		granted = uid >= 0
		if not granted:
			push_error("RewardClaimPopup: dispatch 被拒（reason=%s），奖励未发出" % _reason)
	claimed.emit(granted)
	UIManager.hide_ui(get_ui_name())


func _on_action_pressed() -> void:
	_claim_and_close()


func _on_close_pressed() -> void:
	_claim_and_close()


func _fit_popup_text_height() -> void:
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

	var probe: Label = _ensure_popup_text_probe()
	probe.add_theme_font_override(&"font", font)
	probe.add_theme_constant_override(&"line_spacing", line_spacing)
	probe.autowrap_mode = wrap_mode
	probe.text = txt
	probe.size = Vector2(width, 1.0)

	probe.add_theme_font_size_override(&"font_size", _POPUP_TEXT_BASE_FS)
	probe.update_minimum_size()
	if probe.get_minimum_size().y <= _POPUP_TEXT_MAX_H:
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
		if probe.get_minimum_size().y <= _POPUP_TEXT_MAX_H:
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
