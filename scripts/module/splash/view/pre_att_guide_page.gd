extends UIFrameWindow







signal continued

@onready var _anim: AnimationPlayer = $Root / AnimationPlayer

var _closing: bool = false

func on_show(_params: Dictionary = {}) -> void :

    _closing = false




    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")

func _on_continue_btn_pressed() -> void :
    if _closing:
        return
    Tracker.track_btn_click(Tracker.Btn.ATT_CONTINUE, self)
    _closing = true
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished
    continued.emit()

    visible = false


func get_dlg_name() -> String:
    return Tracker.Dlg.PRE_ATT_GUIDE
