



class_name FeedbackPage
extends UIFrameWindow

signal closed

@onready var _text_edit: TextEdit = $Root / Content / Card / ContentArea / InputText
@onready var _submit_btn: Button = $Root / Content / Card / SubmitBtn
@onready var _submit_btn_disabled: Button = $Root / Content / Card / SubmitBtnDisabled
@onready var _anim: AnimationPlayer = $Root / AnimationPlayer

var _closing: bool = false
var _as_dlg: bool = false
var is_submitted: bool = false

func _ready() -> void :
    _text_edit.text_changed.connect(_on_input_text_changed)
    _update_submit_state()
    bind_press_release_scale($Root / Content / Card / CloseBtn)

func on_show(_params: Dictionary = {}) -> void :
    _as_dlg = _params.get("as_dlg", false)
    _text_edit.text = ""
    _update_submit_state()
    _closing = false
    is_submitted = false
    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")



func _input(event: InputEvent) -> void :
    if not _text_edit.has_focus():
        return
    var is_press: bool = (event is InputEventScreenTouch and event.pressed)\
or (event is InputEventMouseButton and event.pressed)
    if not is_press:
        return
    if not _text_edit.get_global_rect().has_point(event.position):
        _text_edit.release_focus()
        if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
            DisplayServer.virtual_keyboard_hide()

func _on_input_text_changed() -> void :
    _update_submit_state()

func _on_submit_pressed() -> void :
    var content: String = _text_edit.text.strip_edges()
    if content.is_empty():
        return
    Tracker.track_btn_click(Tracker.Btn.SUBMIT, self, {"feedback_record": content})
    print("[FeedbackPage] 用户反馈: ", content)

    Toast.popup("%s\n%s" % [tr("FEEDBACK_TOAST_THANKS_TITLE"), tr("FEEDBACK_TOAST_THANKS_DESC")], self)
    is_submitted = true
    await _close_with_anim()
    closed.emit()


func _on_close_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
    await _close_with_anim()
    closed.emit()


func _close_with_anim() -> void :
    if _closing:
        return
    _closing = true
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished



func _update_submit_state() -> void :
    var has_text: bool = not _text_edit.text.strip_edges().is_empty()
    _submit_btn.visible = has_text
    _submit_btn_disabled.visible = not has_text


func get_scr_name() -> String:
    return "" if _as_dlg else Tracker.Scr.FEEDBACK


func get_dlg_name() -> String:
    return Tracker.Dlg.FEEDBACK if _as_dlg else ""
