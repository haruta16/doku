## 账号已被删除时的确认弹窗；确认后由 AccountManager 处理会话与本地进度重建。

extends UIFrameWindow

@onready var _action_btn: Control = %ActionBtn

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_confirm_pressed)


func on_show(_params: Dictionary = {}) -> void:
	_close_btn.visible = false
	print("[Account (AccountDeletedPage)] 展示")
	_relayout()


func on_escape() -> bool:
	print("[Account (AccountDeletedPage)] 账号已销毁态：吞掉返回键，只能点确认")
	return true


func _relayout() -> void:
	_POPUP_LAYOUT.apply(_dialog_root, _info_box, %MsgTxt, _action_btn, 320.0)


func get_dlg_name() -> String:
	return Tracker.Dlg.ACCOUNT_DELETED_NOTICE


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	print("[Account (AccountDeletedPage)] ✕ 按下 → 与 Restart 同效")
	AccountManager.confirm_account_deleted()


func _on_confirm_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RESTART_APP, self)
	print("[Account (AccountDeletedPage)] Restart 按下 → 清本地 + 退出进程")
	AccountManager.confirm_account_deleted()
