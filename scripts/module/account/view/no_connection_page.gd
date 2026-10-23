## 账号流程断网提示页；保存待重试的操作上下文，再次提交时仍走账号管理器。

extends UIFrameWindow

@onready var _action_btn: Control = %ActionBtn

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _channel: String = ""

var _retry: String = ""


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_action_pressed)


func on_show(params: Dictionary = {}) -> void:
	_channel = params.get("channel", "")
	_retry = params.get("retry", "")
	print("[Account (NoConnectionPage)] 展示 retry=%s ch=%s" % [_retry, _channel])
	_relayout()


func _relayout() -> void:
	_POPUP_LAYOUT.apply(_dialog_root, _info_box, %MsgTxt, _action_btn, 160.0)


func on_hide() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.NETWORK_FAIL


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	super._on_close_btn_pressed()


func _on_action_pressed() -> void:
	print(
		(
			"[Account (NoConnectionPage)] TryAgain 按钮按下 retry=%s busy=%s"
			% [_retry, str(AccountManager.is_busy())]
		)
	)
	Tracker.track_btn_click(Tracker.Btn.TRY_AGAIN, self)
	if _retry != "login" or AccountManager.is_busy():
		UIManager.hide_ui(_ui_name)
		return

	connect_managed(AccountManager.login_flow_finished, _on_retry_finished)

	AccountManager.start_login(_channel)


func _on_retry_finished(ok: bool, _channel_: String, _kind: String, _code: int) -> void:
	UIManager.hide_ui(_ui_name)
	if not ok:
		return
	var conflict: ProgressConflict = AccountManager.get_progress_conflict()
	if conflict != null:
		UIManager.show_ui(UiName.PROGRESS_SELECT, {"conflict": conflict})
