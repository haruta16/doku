extends UIFrameWindow




func _on_action_pressed() -> void :
    UIManager.hide_ui(get_ui_name())

func _on_close_pressed() -> void :
    UIManager.hide_ui(get_ui_name())
