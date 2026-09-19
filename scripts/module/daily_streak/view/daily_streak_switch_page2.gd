# 切组说明页 2：纯提示，两个按钮都只是关掉页面
extends UIFrameWindow


# 主按钮：关闭页面
func _on_action_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


# 关闭按钮：关闭页面
func _on_close_pressed() -> void:
	UIManager.hide_ui(get_ui_name())
