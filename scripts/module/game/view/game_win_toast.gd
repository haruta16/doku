class_name GameWinToast
extends CanvasLayer















@export var sibling_toast: CanvasLayer = null




@export var highlight_color: Color = Color.WHITE

const _ANIM_NAME: StringName = &"GenericPopup"
const _MARK: StringName = &"Mark"


static var _NUMBER_RE: RegEx = RegEx.create_from_string("\\d+%?")

@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var _msg_txt: RichTextLabel = find_child("MessageTxt", true, false) as RichTextLabel





func set_message(text: String) -> void :
    if _msg_txt == null:
        return
    _msg_txt.text = _wrap_numbers_with_color(text)



func _wrap_numbers_with_color(text: String) -> String:
    if highlight_color == Color.WHITE or _NUMBER_RE == null:
        return text
    var hex: String = "#" + highlight_color.to_html(false)
    var out: String = ""
    var pos: int = 0
    for m: RegExMatch in _NUMBER_RE.search_all(text):
        var s: int = m.get_start()
        var e: int = m.get_end()
        out += text.substr(pos, s - pos)
        out += "[color=%s]%s[/color]" % [hex, text.substr(s, e - s)]
        pos = e
    out += text.substr(pos)
    return out



func show_toast(_params: Dictionary = {}) -> void :
    if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
        if sibling_toast.has_method("hide_toast"):
            sibling_toast.hide_toast()
    visible = true
    if _anim != null and _anim.has_animation(_ANIM_NAME):
        _anim.play_section_with_markers(_ANIM_NAME, &"", _MARK)





func hide_toast() -> void :
    if not visible:
        return
    if _anim != null and _anim.has_animation(_ANIM_NAME):
        _anim.play_section_with_markers(_ANIM_NAME, _MARK, &"")


func is_showing() -> bool:
    return visible
