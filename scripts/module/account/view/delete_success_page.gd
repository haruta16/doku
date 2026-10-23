## 删除成功后的提示页；把重新开始的动作交给 AccountManager.restart_app。

extends UIFrameWindow

@onready var _action_btn: Control = %ActionBtn

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_restart_pressed)


func on_show(_params: Dictionary = {}) -> void:
	print("[Account (DeleteSuccessPage)] 展示")
	_relayout()


func _relayout() -> void:
	_POPUP_LAYOUT.apply(_dialog_root, _info_box, %MsgTxt, _action_btn, 320.0)


func get_dlg_name() -> String:
	return Tracker.Dlg.DELETE_ACCOUNT_SUCCESS


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	print("[Account (DeleteSuccessPage)] ✕ 按下 → 与 Restart 同效，走软重载")
	AccountManager.restart_app()


func _on_restart_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RESTART_APP, self)
	print("[Account (DeleteSuccessPage)] Restart 按钮按下 → 软重载")
	AccountManager.restart_app()
