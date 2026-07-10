@tool
class_name AutoFitLabel
extends Label

















@export var max_font_size: int = 0:
    set(v):
        max_font_size = v
        _base_font_size = 0
        _queue_refit()


@export var min_font_size: int = 12:
    set(v):
        min_font_size = maxi(1, v)
        _queue_refit()


var _base_font_size: int = 0

var _fitting: bool = false
var _refit_queued: bool = false


func _ready() -> void :
    resized.connect(_queue_refit)
    _queue_refit()


func _notification(what: int) -> void :

    if what == NOTIFICATION_TRANSLATION_CHANGED:
        _queue_refit()




func _set(property: StringName, value: Variant) -> bool:
    if property == &"text":
        _queue_refit()
    return false



func refit() -> void :
    _refit_queued = false
    _apply_fit()


func _queue_refit() -> void :
    if _refit_queued:
        return
    _refit_queued = true

    call_deferred("_deferred_refit")


func _deferred_refit() -> void :
    if not _refit_queued:
        return
    _refit_queued = false
    _apply_fit()


func _apply_fit() -> void :
    if _fitting or not is_inside_tree():
        return
    var box: Vector2 = _layout_box()
    if box.x <= 0.0 or box.y <= 0.0:
        return
    var display_text: String = _resolve_display_text()
    if display_text.is_empty():
        return
    var font: Font = get_theme_font(&"font")
    if font == null:
        return

    if _base_font_size <= 0:
        _base_font_size = max_font_size if max_font_size > 0 else get_theme_font_size(&"font_size")
    if _base_font_size <= 0:
        return

    var wrap: bool = autowrap_mode != TextServer.AUTOWRAP_OFF




    var lo_fs: int = min(min_font_size, _base_font_size)
    var hi_fs: int = _base_font_size
    var fs: int = lo_fs
    while lo_fs <= hi_fs:
        var mid: int = (lo_fs + hi_fs) >> 1
        if _text_fits(font, display_text, box, mid, wrap):
            fs = mid
            lo_fs = mid + 1
        else:
            hi_fs = mid - 1

    _fitting = true
    add_theme_font_size_override(&"font_size", fs)
    _fitting = false






func _resolve_display_text() -> String:
    return atr(text)













func _layout_box() -> Vector2:
    var parent_size: Vector2 = Vector2.ZERO
    var pc: = get_parent() as Control
    if pc != null:
        parent_size = pc.size
    var w: float = (anchor_right - anchor_left) * parent_size.x + (offset_right - offset_left)
    var h: float = (anchor_bottom - anchor_top) * parent_size.y + (offset_bottom - offset_top)
    return Vector2(w, h)


func _text_fits(font: Font, txt: String, box: Vector2, fs: int, wrap: bool) -> bool:
    if wrap:









        var probe: Label = _ensure_probe()
        probe.add_theme_font_override(&"font", font)
        probe.add_theme_font_size_override(&"font_size", fs)
        probe.add_theme_constant_override(&"line_spacing", get_theme_constant(&"line_spacing"))
        probe.autowrap_mode = autowrap_mode
        probe.text = txt
        probe.size = Vector2(box.x, 1.0)
        probe.update_minimum_size()
        if probe.get_minimum_size().y > box.y:
            return false




        if autowrap_mode == TextServer.AUTOWRAP_WORD:
            for word: String in txt.split(" ", false):
                if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x > box.x:
                    return false
        return true
    var s: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
    return s.x <= box.x and s.y <= box.y




var _probe: Label = null


func _ensure_probe() -> Label:
    if _probe != null and is_instance_valid(_probe) and _probe.get_parent() == self:
        return _probe
    _probe = Label.new()
    _probe.name = &"_AutoFitProbe"
    _probe.visible = false
    _probe.top_level = true
    _probe.position = Vector2(-100000.0, -100000.0)
    add_child(_probe)
    return _probe


func _exit_tree() -> void :
    if _probe != null and is_instance_valid(_probe):
        _probe.queue_free()
        _probe = null
