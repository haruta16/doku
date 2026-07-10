@tool
class_name CurveLabel
extends Label





@export var curve: Curve:
    set(v):
        if curve != null and curve.changed.is_connected(queue_redraw):
            curve.changed.disconnect(queue_redraw)
        curve = v
        if curve == null:
            curve = _make_default_curve()
        if not curve.changed.is_connected(queue_redraw):
            curve.changed.connect(queue_redraw)
        queue_redraw()


@export var amplitude: float = 80.0:
    set(v):
        amplitude = v
        queue_redraw()


@export var align_to_tangent: bool = false:
    set(v):
        align_to_tangent = v
        queue_redraw()


func _enter_tree() -> void :


    visible_characters = 0


func _ready() -> void :
    if curve == null:
        curve = _make_default_curve()


func _draw() -> void :


    if visible_characters != 0:
        visible_characters = 0
    var display_text: String = atr(text)
    if display_text.is_empty() or curve == null:
        return

    var font: Font = _resolve_font()
    if font == null:
        return
    var font_size: int = _resolve_font_size()

    var ts: TextServer = TextServerManager.get_primary_interface()
    var line: = TextLine.new()
    line.add_string(display_text, font, font_size)
    var glyphs: Array = ts.shaped_text_get_glyphs(line.get_rid())

    var total_advance: = 0.0
    for g in glyphs:
        total_advance += g["advance"]
    if total_advance <= 0.0:
        return


    var effective_font_size: = font_size
    if size.x > 0.0 and total_advance > size.x:
        effective_font_size = maxi(1, int(float(font_size) * size.x / total_advance))
        line = TextLine.new()
        line.add_string(display_text, font, effective_font_size)
        glyphs = ts.shaped_text_get_glyphs(line.get_rid())
        total_advance = 0.0
        for g in glyphs:
            total_advance += g["advance"]
        if total_advance <= 0.0:
            return



    var x_scale: float = size.x if size.x > 0.0 else total_advance



    var fill_scale: = 1.0
    var offset_x: = 0.0
    if effective_font_size < font_size and size.x > 0.0 and total_advance > 0.0:
        fill_scale = size.x / total_advance
    else:
        match horizontal_alignment:
            HORIZONTAL_ALIGNMENT_CENTER:
                offset_x = (size.x - total_advance) * 0.5
            HORIZONTAL_ALIGNMENT_RIGHT:
                offset_x = size.x - total_advance

    var cumulative: = 0.0
    for g in glyphs:
        var adv: float = g["advance"]
        var glyph_w: float = adv * fill_scale
        var x: = offset_x + cumulative * fill_scale
        var t: = clampf((x + glyph_w * 0.5) / x_scale, 0.0, 1.0)
        var y: = size.y * 0.5 - (curve.sample(t) - 0.5) * amplitude * 2.0
        var glyph_offset: Vector2 = g["offset"]
        if align_to_tangent:

            var pivot: = Vector2(x + glyph_w * 0.5, y) + glyph_offset
            draw_set_transform(pivot, _tangent_angle(t, x_scale))
            _draw_glyph(g, Vector2( - glyph_w * 0.5, 0.0), effective_font_size, ts)
        else:
            var pos: = Vector2(x, y) + glyph_offset
            _draw_glyph(g, pos, effective_font_size, ts)
        cumulative += adv

    if align_to_tangent:

        draw_set_transform(Vector2.ZERO)



func _draw_glyph(g: Dictionary, pos: Vector2, font_size: int, ts: TextServer) -> void :
    var font_color: Color
    var outline_size: int
    var outline_color: Color
    var shadow_color: Color
    var shadow_size: int
    var shadow_offset: Vector2
    if label_settings != null:
        font_color = label_settings.font_color
        outline_size = label_settings.outline_size
        outline_color = label_settings.outline_color
        shadow_color = label_settings.shadow_color
        shadow_size = label_settings.shadow_size
        shadow_offset = label_settings.shadow_offset
    else:
        font_color = get_theme_color(&"font_color")
        outline_size = get_theme_constant(&"outline_size")
        outline_color = get_theme_color(&"font_outline_color")
        shadow_color = get_theme_color(&"font_shadow_color")
        shadow_size = get_theme_constant(&"shadow_outline_size")
        shadow_offset = Vector2(
            get_theme_constant(&"shadow_offset_x"), 
            get_theme_constant(&"shadow_offset_y")
        )

    var canvas: = get_canvas_item()
    var font_rid: RID = g["font_rid"]
    var index: int = g["index"]

    if shadow_color.a > 0.0:
        var shadow_pos: = pos + shadow_offset
        if shadow_size > 0:
            ts.font_draw_glyph_outline(font_rid, canvas, font_size, shadow_size, shadow_pos, index, shadow_color)
        ts.font_draw_glyph(font_rid, canvas, font_size, shadow_pos, index, shadow_color)

    if outline_size > 0 and outline_color.a > 0.0:
        ts.font_draw_glyph_outline(font_rid, canvas, font_size, outline_size, pos, index, outline_color)

    ts.font_draw_glyph(font_rid, canvas, font_size, pos, index, font_color)




func _tangent_angle(t: float, x_scale: float) -> float:
    const DT: = 0.01
    var t0: = clampf(t - DT, 0.0, 1.0)
    var t1: = clampf(t + DT, 0.0, 1.0)
    var dy: = curve.sample(t1) - curve.sample(t0)

    var tangent: = Vector2(x_scale * (t1 - t0), - dy * amplitude * 2.0)
    return tangent.angle()


func _resolve_font() -> Font:
    if label_settings != null and label_settings.font != null:
        return label_settings.font
    return get_theme_font(&"font")


func _resolve_font_size() -> int:
    if label_settings != null and label_settings.font_size > 0:
        return label_settings.font_size
    return get_theme_font_size(&"font_size")


func _make_default_curve() -> Curve:
    var c: = Curve.new()
    c.add_point(Vector2(0.0, 0.5), 0.0, 2.0)
    c.add_point(Vector2(0.5, 1.0), 0.0, 0.0)
    c.add_point(Vector2(1.0, 0.5), -2.0, 0.0)
    return c
