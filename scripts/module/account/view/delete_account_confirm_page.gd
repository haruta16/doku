## 删除账号的二次确认页；提交后锁住按钮，等待管理器的异步删除结果。

extends UIFrameWindow

@onready var _action_btn: Control = %ActionBtn

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_delete_pressed)


func on_show(_params: Dictionary = {}) -> void:
	_relayout()


func _relayout() -> void:
	_POPUP_LAYOUT.apply(_dialog_root, _info_box, %MsgTxt, _action_btn, 700.0)


## 在异步删除期间禁用交互，防止同一弹窗重复提交删号请求。
func set_busy(busy: bool) -> void:
	_action_btn.modulate.a = 0.5 if busy else 1.0
	_action_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP


func on_hide() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.DELETE_ACCOUNT_CONFIRM


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	super._on_close_btn_pressed()


func _on_delete_pressed() -> void:
	if AccountManager.is_busy():
		return
	print("[Account (DeleteAccountConfirmPage)] 确认删号 → 发起删号")
	Tracker.track_btn_click(Tracker.Btn.DELETE_ACCOUNT_CONFIRM, self)
	set_busy(true)
	connect_managed_once(AccountManager.delete_flow_finished, _on_delete_finished)
	AccountManager.start_delete_account()


## 根据最终结果关闭确认页或显示对应错误；不把按钮点击当作删除成功。
func _on_delete_finished(ok: bool, kind: String, code: int) -> void:
	print(
		"[Account (DeleteAccountConfirmPage)] 删号流程结束 ok=%s kind=%s code=%d" % [str(ok), kind, code]
	)
	set_busy(false)
	if ok:
		UIManager.hide_ui(_ui_name)
		UIManager.show_ui(UiName.DELETE_SUCCESS)
		return
	if kind == AccountManager.KIND_NETWORK:
		UIManager.show_ui(UiName.NO_CONNECTION, {"retry": "delete"})
		return

	push_error("DeleteAccount: failed kind=%s code=%d" % [kind, code])
	Toast.popup("DELETE_TOAST_FAILED", self)
