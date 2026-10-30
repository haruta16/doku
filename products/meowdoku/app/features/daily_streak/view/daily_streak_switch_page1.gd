## 切组说明页 1（HomePage 按 StreakManager.get_pending_switch_page() 弹）：关闭时补发一份切组礼包
extends UIFrameWindow

var _presentation_revision: int = 0 # 领取期间直接刷新也会替换本次关闭请求
var _granted: bool = false # 本次显示是否已经发过礼包（防重复）


## 每次显示重置发放标记
func on_show(_params: Dictionary = {}) -> void:
	_presentation_revision += 1
	_granted = false


## 主按钮：等同关闭
func _on_action_pressed() -> void:
	_close()


## 关闭按钮：关闭
func _on_close_pressed() -> void:
	_close()


## 关闭前先补发切组礼包（同一次显示只发一次），再关页面
func _close() -> void:
	var revision: int = _presentation_revision
	if not _granted:
		var granted: bool = StreakManager.grant_switch_gift()
		if revision != _presentation_revision or not is_showing() or is_queued_for_deletion():
			return
		if not granted:
			Toast.popup("RECOVERY_SAVE_ERROR", self)
			return
		_granted = true
	UIManager.hide_ui(get_ui_name())
