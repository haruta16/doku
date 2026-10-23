## 退出账号的确认页；等待管理器登出结果，并根据消息长度调整弹窗布局。

extends UIFrameWindow

const _DIALOG_W: float = 900.0

const _TITLE_H: float = 130.0

const _TITLE_GAP: float = 70.0

const _INFO_W: float = 800.0

const _TXT_PAD_V: float = 30.0

const _MSG_H_BASE: float = 160.0

const _INFO_GAP: float = 60.0

const _BTN_H: float = 160.0

const _BTN_GAP: float = 40.0

const _BOTTOM: float = 90.0

const _BTN_PAD_TOP: float = 68.0

const _BTN_INST_H: float = 258.0

@onready var _msg: Label = %MsgTxt

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox

@onready var _yes_btn: Control = %YesBtn

@onready var _no_btn: Control = %NoBtn

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _channel: String = ""


func _ready() -> void:
	_yes_btn.tag_pressed.connect(_on_yes_pressed)
	_no_btn.tag_pressed.connect(_on_cancel)


func on_show(params: Dictionary = {}) -> void:
	_channel = params.get("channel", "")
	print("[Account (SignOutConfirmPage)] 展示 ch=%s" % _channel)
	_msg.text = tr("LOGOUT_CONFIRM_MSG") % AccountDefine.display_name(_channel)

	_relayout()


func _relayout() -> void:
	var y: float = _TITLE_H + _TITLE_GAP
	var msg_h: float = _msg_height()
	_info_box.offset_top = y
	_info_box.offset_bottom = y + _TXT_PAD_V + msg_h + _TXT_PAD_V

	_msg.offset_top = _TXT_PAD_V
	_msg.offset_bottom = _TXT_PAD_V + msg_h
	y = _info_box.offset_bottom + _INFO_GAP

	_place_btn(_yes_btn, y)
	y += _BTN_H + _BTN_GAP
	_place_btn(_no_btn, y)
	y += _BTN_H + _BOTTOM
	_dialog_root.offset_top = -y * 0.5
	_dialog_root.offset_bottom = y * 0.5
	_dialog_root.offset_left = -_DIALOG_W * 0.5
	_dialog_root.offset_right = _DIALOG_W * 0.5


func _place_btn(btn: Control, visual_top: float) -> void:
	btn.offset_top = visual_top - _BTN_PAD_TOP
	btn.offset_bottom = btn.offset_top + _BTN_INST_H


func _msg_height() -> float:
	return _POPUP_LAYOUT.msg_height(_msg, _MSG_H_BASE)


func on_hide() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.SIGN_OUT_CONFIRM


func _on_yes_pressed() -> void:
	print("[Account (SignOutConfirmPage)] YES → 发起登出 ch=%s" % _channel)
	Tracker.track_btn_click(Tracker.Btn.SIGN_OUT_CONFIRM, self)
	UIManager.hide_ui(_ui_name)

	AccountManager.start_logout()


func _on_cancel() -> void:
	Tracker.track_btn_click(Tracker.Btn.SIGN_OUT_CANCEL, self)
	UIManager.hide_ui(_ui_name)


func _on_close_pressed() -> void:
	_on_cancel()
