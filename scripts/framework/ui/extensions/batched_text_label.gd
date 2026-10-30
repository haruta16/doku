## 批量文字绘制控件：计算行布局后直接绘制，减少逐字节点带来的开销。
class_name BatchedTextLabel
extends Label

var _para := TextParagraph.new()


func _ready() -> void:
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	visible_characters = 0


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_RESIZED
		or what == NOTIFICATION_THEME_CHANGED
		or what == NOTIFICATION_TRANSLATION_CHANGED
	):
		queue_redraw()


func _draw() -> void:
	var txt: String = atr(text)
	if txt.is_empty():
		return
	var font: Font = get_theme_font(&"font")
	var fs: int = get_theme_font_size(&"font_size")
	if font == null or fs <= 0:
		return
	var style: StyleBox = get_theme_stylebox(&"normal")
	var width: float = size.x - style.get_minimum_size().x
	_para.clear()
	_para.width = width
	_para.break_flags = _break_flags()
	_para.add_string(txt, font, fs, language)
	var font_h: float = font.get_height(fs)
	var line_spacing: int = get_theme_constant(&"line_spacing")
	var lines: Array = []
	var total_h: float = 0.0
	for i in _para.get_line_count():
		var asc: float = _para.get_line_ascent(i)
		var dsc: float = _para.get_line_descent(i)
		if asc + dsc < font_h:
			var diff: float = font_h - (asc + dsc)
			asc += diff / 2.0
			dsc += diff - diff / 2.0
		lines.append([i, asc, dsc])
		total_h += asc + dsc + line_spacing
	total_h += style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
	var y: float = style.get_offset().y
	match vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y += int((size.y - (total_h - line_spacing)) / 2.0)
		VERTICAL_ALIGNMENT_BOTTOM:
			y += int(size.y - (total_h - line_spacing))
	var items: Array = []
	var color: Color = get_theme_color(&"font_color")
	for entry: Array in lines:
		var i: int = entry[0]
		var asc: float = entry[1]
		var dsc: float = entry[2]
		y += asc
		var rid: RID = _para.get_line_rid(i)
		GlyphBatch.append_shaped(
			items, rid, Vector2(_line_x(rid, style), y), color, GlyphBatch.Layer.BODY
		)
		y += dsc + line_spacing
	GlyphBatch.draw(get_canvas_item(), items, get_viewport().get_oversampling(), fs)


func _line_x(rid: RID, style: StyleBox) -> float:
	var w: float = TextServerManager.get_primary_interface().shaped_text_get_size(rid).x
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return int(size.x - w) / 2
		HORIZONTAL_ALIGNMENT_RIGHT:
			return int(size.x - style.get_margin(SIDE_RIGHT) - w)
	return style.get_offset().x


func _break_flags() -> int:
	var flags: int = TextServer.BREAK_MANDATORY
	match autowrap_mode:
		TextServer.AUTOWRAP_WORD_SMART:
			flags |= TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		TextServer.AUTOWRAP_WORD:
			flags |= TextServer.BREAK_WORD_BOUND
		TextServer.AUTOWRAP_ARBITRARY:
			flags |= TextServer.BREAK_GRAPHEME_BOUND
	return flags | autowrap_trim_flags
