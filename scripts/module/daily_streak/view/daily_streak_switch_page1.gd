# 切组说明页 1（HomePage 按 StreakManager.get_pending_switch_page() 弹）：关闭时补发一份切组礼包
extends UIFrameWindow

var _granted: bool = false # 本次显示是否已经发过礼包（防重复）


# 每次显示重置发放标记
func on_show(_params: Dictionary = {}) -> void:
	_granted = false


# 主按钮：等同关闭
func _on_action_pressed() -> void:
	_close()


# 关闭按钮：关闭
func _on_close_pressed() -> void:
	_close()


# 关闭前先补发切组礼包（同一次显示只发一次），再关页面
func _close() -> void:
	if not _granted:
		_granted = true
		StreakManager.grant_switch_gift()
	UIManager.hide_ui(get_ui_name())
