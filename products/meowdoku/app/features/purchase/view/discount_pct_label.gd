## 折扣百分比的自绘标签；分别绘制数值和百分号，控制它们的字号与基线位置。

class_name DiscountPctLabel
extends Control

const SIGN_SIZE := 40
const DIGIT_SIZE := 50

@export var font: Font
@export var percent: int = 90:
	set(v):
		percent = v
		queue_redraw()

@export var text_color: Color = Color.WHITE:
	set(v):
		text_color = v
		queue_redraw()
@export var shadow_color: Color = Color(0.6, 0.108, 0.505, 1):
	set(v):
		shadow_color = v
		queue_redraw()
@export var shadow_offset: Vector2 = Vector2(0, 3)
@export var shadow_outline_size: int = 1

var _line := TextLine.new()


func _draw() -> void:
	var f: Font = font if font != null else get_theme_default_font()
	_line.clear()
	_line.add_string("-", f, SIGN_SIZE)
	_line.add_string(str(percent), f, DIGIT_SIZE)
	_line.add_string("%", f, SIGN_SIZE)
	var line_size: Vector2 = _line.get_size()
	var origin := Vector2(
		int((size.x - line_size.x) / 2.0),
		int((size.y - line_size.y) / 2.0) + _line.get_line_ascent()
	)
	var items: Array = []
	var rid: RID = _line.get_rid()
	if shadow_color.a > 0.0:
		if shadow_outline_size > 0:
			GlyphBatch.append_shaped(
				items,
				rid,
				origin + shadow_offset,
				shadow_color,
				GlyphBatch.Layer.SHADOW_OUTLINE,
				shadow_outline_size
			)
		GlyphBatch.append_shaped(
			items, rid, origin + shadow_offset, shadow_color, GlyphBatch.Layer.SHADOW
		)
	GlyphBatch.append_shaped(items, rid, origin, text_color, GlyphBatch.Layer.BODY)
	GlyphBatch.draw(get_canvas_item(), items, get_viewport().get_oversampling(), DIGIT_SIZE)
