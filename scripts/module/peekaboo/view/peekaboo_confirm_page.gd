## 躲猫猫确认弹窗；提供广告领取、普通领取和关闭意图，奖励发放由外部流程协调。

@tool
class_name PeekabooConfirmPage
extends UIFrameWindow

signal ad_requested

signal plain_requested

signal close_requested

const _BODY_PATH := "Content/CenterContainer/BgSizeBox/Bg/BgVBox/Content/Panel/PopUpText"
const _BTN_GROUP_PATH := "Content/CenterContainer/BgSizeBox/Bg/BgVBox/BtnGroup"

@onready var _title: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/Text
@onready var _body: Label = get_node(_BODY_PATH)
@onready var _ad_btn: Button = get_node(_BTN_GROUP_PATH + "/AdBtn")
@onready var _plain_btn: Button = get_node(_BTN_GROUP_PATH + "/PlainBtn")
@onready var _close_btn_ref: Button = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/CloseBtn

@onready var _ad_btn_label: Label = get_node(_BTN_GROUP_PATH + "/AdBtn/Row/Label")
@onready var _plain_btn_label: Label = get_node(_BTN_GROUP_PATH + "/PlainBtn/Row/Label")

@onready var _cat_dialog: Control = $Content/CatDialog
@onready var _cat_img: Control = $Content/CatDialog/CatImg
@onready var _card: PanelContainer = $Content/CenterContainer/BgSizeBox/Bg
@onready var _center_container: CenterContainer = $Content/CenterContainer

@export var cat_y_offset: float = -363.0:
	set(v):
		cat_y_offset = v
		_sync_cat()

var _consumed: bool = false


func _ready() -> void:
	if is_instance_valid(_card):
		_card.item_rect_changed.connect(_sync_cat)

	set_process(true)
	_sync_cat.call_deferred()


func on_show(params: Dictionary = {}) -> void:
	_consumed = false

	_title.text = tr("CAT_HIDE_AND_SEEK_TITLE")
	_body.text = tr("CAT_HIDE_AND_SEEK_BODY")
	_ad_btn_label.text = tr("CAT_HIDE_AND_SEEK_BTN")
	_plain_btn_label.text = tr("CAT_HIDE_AND_SEEK_BTN")
	_ad_btn.visible = bool(params.get("ad_available", false))

	_sync_cat.call_deferred()


func _sync_cat() -> void:
	if not is_node_ready():
		return
	if not is_instance_valid(_card) or not is_instance_valid(_cat_dialog):
		return

	var overhang: float = _cat_overhang()
	if not is_equal_approx(_center_container.offset_top, overhang):
		_center_container.offset_top = overhang

	var bgsizebox: Control = _card.get_parent() as Control
	var center: Control = bgsizebox.get_parent() as Control
	var bg_top: float = center.position.y + bgsizebox.position.y + _card.position.y
	var want_y: float = bg_top + cat_y_offset
	if not is_equal_approx(_cat_dialog.position.y, want_y):
		_cat_dialog.position.y = want_y


func _cat_overhang() -> float:
	if not is_instance_valid(_cat_img):
		return 0.0
	return maxf(0.0, -cat_y_offset - _cat_img.offset_top)


func _process(_delta: float) -> void:
	_sync_cat()


func get_dlg_name() -> String:
	return Tracker.Dlg.PEEKABOO


func _on_ad_btn_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	Tracker.track_btn_click(Tracker.Btn.GET_TRIPLE, self)
	UIManager.hide_ui(_ui_name)
	ad_requested.emit()


func _on_plain_btn_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	Tracker.track_btn_click(Tracker.Btn.GET, self)
	UIManager.hide_ui(_ui_name)
	plain_requested.emit()


func _on_close_btn_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	UIManager.hide_ui(_ui_name)
	close_requested.emit()
