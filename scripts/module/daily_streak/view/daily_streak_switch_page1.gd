extends UIFrameWindow




var _granted: bool = false

func on_show(_params: Dictionary = {}) -> void :
    _granted = false

func _on_action_pressed() -> void :
    _close()

func _on_close_pressed() -> void :
    _close()

func _close() -> void :
    if not _granted:
        _granted = true
        StreakManager.grant_switch_gift()
    UIManager.hide_ui(get_ui_name())
