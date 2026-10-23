## 登录结果弹窗；根据成功或失败状态切换文案、图标与重试动作。

extends UIFrameWindow

const TYPE_SUCCESS: String = "login_success"

const TYPE_FAIL: String = "login_fail"

const _COLOR_SUCCESS: Color = Color(0.2784314, 0.7019608, 0.34117648, 1.0)

const _COLOR_FAIL: Color = Color(0.85096157, 0.28229013, 0.28229013, 1.0)

const _ICON_CORNER_RADIUS: int = 100

@export var tex_check: Texture2D

@export var tex_cross: Texture2D

@onready var _title: Label = %TitleTxt

@onready var _icon_bg: Panel = %IconBg

@onready var _icon_mark: TextureRect = %IconMark

@onready var _msg: Label = %MsgTxt

@onready var _action_btn: Control = %ActionBtn

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _channel: String = ""

var _is_success: bool = true


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_action_pressed)


func on_show(params: Dictionary = {}) -> void:
	var kind: String = params.get("type", TYPE_SUCCESS)
	_is_success = kind != TYPE_FAIL
	_channel = params.get("channel", "")
	print("[Account (AccountResultPage)] 展示 type=%s ch=%s" % [kind, _channel])
	var channel_name: String = AccountDefine.display_name(_channel)

	_title.text = tr("LOGIN_RESULT_TITLE_SUCCESS" if _is_success else "LOGIN_RESULT_TITLE_FAIL")
	_msg.text = (
		tr("LOGIN_RESULT_MSG_SUCCESS" if _is_success else "LOGIN_RESULT_MSG_FAIL") % channel_name
	)
	_action_btn.btn_text = tr("LOGIN_BTN_CONTINUE" if _is_success else "LOGIN_BTN_TRY_AGAIN")
	_apply_state_icon()
	_relayout()


func _relayout() -> void:
	_POPUP_LAYOUT.apply(_dialog_root, _info_box, _msg, _action_btn, 80.0)


func _apply_state_icon() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = _COLOR_SUCCESS if _is_success else _COLOR_FAIL
	box.corner_radius_top_left = _ICON_CORNER_RADIUS
	box.corner_radius_top_right = _ICON_CORNER_RADIUS
	box.corner_radius_bottom_right = _ICON_CORNER_RADIUS
	box.corner_radius_bottom_left = _ICON_CORNER_RADIUS
	_icon_bg.add_theme_stylebox_override(&"panel", box)
	_icon_mark.texture = tex_check if _is_success else tex_cross


func on_hide() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.LOGIN_SUCCESS if _is_success else Tracker.Dlg.LOGIN_FAIL


func get_dlg_extra() -> Dictionary:
	return {"login_channel": _channel}


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	super._on_close_btn_pressed()


func _on_action_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CONTINUE if _is_success else Tracker.Btn.TRY_AGAIN, self)
	if _is_success:
		UIManager.hide_ui(_ui_name)
		return
	if AccountManager.is_busy():
		return

	if not AccountManager.login_flow_finished.is_connected(_on_retry_finished):
		AccountManager.login_flow_finished.connect(_on_retry_finished, CONNECT_ONE_SHOT)
	var retry_channel: String = _channel
	UIManager.hide_ui(_ui_name)

	AccountManager.start_login(retry_channel)


func _on_retry_finished(ok: bool, channel: String, kind: String, code: int) -> void:
	if ok:
		var conflict: ProgressConflict = AccountManager.get_progress_conflict()
		if conflict != null:
			UIManager.show_ui(UiName.PROGRESS_SELECT, {"conflict": conflict})
		return
	print("[Account (AccountResultPage)] 重试仍失败 kind=%s code=%d" % [kind, code])
	if kind == AccountManager.KIND_NETWORK:
		UIManager.show_ui(UiName.NO_CONNECTION, {"retry": "login", "channel": channel})
		return
	UIManager.show_ui(UiName.ACCOUNT_RESULT, {"type": TYPE_FAIL, "channel": channel})
