## 批量文字绘制控件：计算行布局后直接绘制，减少逐字节点带来的开销。
class_name BatchedTextLabel
extends Label

var _para := TextParagraph.new() # 复用的段落排版对象；每次绘制清空内容后按当前字体与宽度重排


## 保留 Label 的排版属性，但关闭内置字形显示；后续由 _draw 收集并绘制所有行。
func _ready() -> void:
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	visible_characters = 0


## 尺寸、主题或语言变化都会改变字形布局，统一标记下一次重绘。
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_RESIZED
		or what == NOTIFICATION_THEME_CHANGED
		or what == NOTIFICATION_TRANSLATION_CHANGED
	):
		queue_redraw()


## 先用 TextParagraph 完成换行，再计算各行基线和整体对齐，最后交给 GlyphBatch 按层与字体纹理分组绘制。
func _draw() -> void:
	var txt: String = atr(text)
	if txt.is_empty():
		return
	var font: Font = get_theme_font(&"font")
	var fs: int = get_theme_font_size(&"font_size")
	if font == null or fs <= 0:
		return
	var style: StyleBox = get_theme_stylebox(&"normal")
	# 先减去 StyleBox 左右边距，剩余宽度才是文字实际可换行的区域。
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
		# 某行只有较矮字形时仍补足字体行高，避免不同文字组合导致相邻行上下跳动。
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
	# 一项保存一个已排版字形的位置与样式；这里不为每个字创建场景节点。
	var items: Array = []
	var color: Color = get_theme_color(&"font_color")
	for entry: Array in lines:
		var i: int = entry[0]
		var asc: float = entry[1]
		var dsc: float = entry[2]
		# 字体绘制坐标是基线，不是行盒左上角；先加 ascent，到下一行再加 descent 和行距。
		y += asc
		var rid: RID = _para.get_line_rid(i)
		GlyphBatch.append_shaped(
			items, rid, Vector2(_line_x(rid, style), y), color, GlyphBatch.Layer.BODY
		)
		y += dsc + line_spacing
	GlyphBatch.draw(get_canvas_item(), items, get_viewport().get_oversampling(), fs)


## 按水平对齐方式返回一行的起点；左/右对齐考虑主题 StyleBox 的边距。
func _line_x(rid: RID, style: StyleBox) -> float:
	var w: float = TextServerManager.get_primary_interface().shaped_text_get_size(rid).x
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return int(size.x - w) / 2
		HORIZONTAL_ALIGNMENT_RIGHT:
			return int(size.x - style.get_margin(SIDE_RIGHT) - w)
	return style.get_offset().x


## 把 Label 的换行模式翻译成 TextServer 的断行标志，并保留强制换行和首尾空白裁剪设置。
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
