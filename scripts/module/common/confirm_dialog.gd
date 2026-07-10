class_name ConfirmDialog
extends UIFrameWindow

@onready var _title_label: Label = $Root / Content / DialogRoot / TitleLabel
@onready var _content_label: Label = $Root / Content / DialogRoot / ContentLabel
@onready var _action_btn: Button = $Root / Content / DialogRoot / ActionButton
@onready var _anim: AnimationPlayer = $Root / AnimationPlayer

var _on_confirm: Callable
var _on_close: Callable
var _closing: bool = false

func _ready() -> void :
    bind_press_release_scale($Root / Content / DialogRoot / CloseButton)

func on_show(params: Dictionary = {}) -> void :
    open(
        params.get("title", _title_label.text), 
        params.get("content", _content_label.text), 
        params.get("btn_text", _action_btn.text), 
        params.get("on_confirm", Callable()), 
        params.get("on_close", Callable())
    )

func open(title: String, content: String, btn_text: String, on_confirm: Callable, on_close: Callable = Callable()) -> void :

    _title_label.text = tr(title)
    _content_label.text = tr(content)
    _action_btn.text = tr(btn_text)
    _on_confirm = on_confirm
    _on_close = on_close
    _closing = false
    visible = true
    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")

func close() -> void :
    if _closing:
        return
    _closing = true
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished

    visible = false

func _on_action_btn_pressed() -> void :
    close()
    if _on_confirm.is_valid():
        _on_confirm.call()

func _on_close_btn_pressed() -> void :
    close()
    if _on_close.is_valid():
        _on_close.call()
