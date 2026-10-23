## 单行字形渲染器：拆分阴影、描边等绘制层，统一字体测量与渐变参数。
@tool
class_name SingleLineGlyphLabel
extends Label

enum LayerKind {
	SHADOW,
	OUTLINE,
	BODY,
}

@export_group("曲线")

@export var curve_enabled: bool = true:
	set(value):
		curve_enabled = value
		_redraw_all_layers()

@export var amplitude: float = 80.0:
	set(value):
		amplitude = value
		_redraw_all_layers()

@export var align_to_tangent: bool = false:
	set(value):
		align_to_tangent = value
		_redraw_all_layers()

@export var curve: Curve:
	set(value):
		if curve != null and curve.changed.is_connected(_redraw_all_layers):
			curve.changed.disconnect(_redraw_all_layers)
		curve = value
		if curve == null:
			curve = _make_default_curve()
		if not curve.changed.is_connected(_redraw_all_layers):
			curve.changed.connect(_redraw_all_layers)
		_redraw_all_layers()

@export_group("")

@export_range(0.0, 1.0) var fade: float = 1.0:
	set(value):
		fade = value
		_sync_fade()

@export var letter_spacing: float = 0.0:
	set(value):
		letter_spacing = value
		_redraw_all_layers()

@export_group("字身")

@export var body_color: Color = Color.WHITE:
	set(value):
		body_color = value
		_redraw_all_layers()

@export var gradient_enabled: bool = false:
	set(value):
		gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var gradient_start_color: Color = Color.WHITE:
	set(value):
		gradient_start_color = value
		_rebuild_paint_layers()

@export var gradient_end_color: Color = Color(0.55, 0.55, 0.55, 1.0):
	set(value):
		gradient_end_color = value
		_rebuild_paint_layers()

@export var gradient_direction: Vector2 = Vector2(0.0, 1.0):
	set(value):
		gradient_direction = value
		_sync_gradient_uniforms()

@export_group("描边")

@export var outline_thickness: int = 0:
	set(value):
		outline_thickness = maxi(value, 0)

		_rebuild_paint_layers()

@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		_rebuild_paint_layers()

@export var outline_gradient_enabled: bool = false:
	set(value):
		outline_gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var outline_gradient_start: Color = Color.WHITE:
	set(value):
		outline_gradient_start = value
		_rebuild_paint_layers()

@export var outline_gradient_end: Color = Color(0.55, 0.55, 0.55, 1.0):
	set(value):
		outline_gradient_end = value
		_rebuild_paint_layers()

@export var outline_gradient_direction: Vector2 = Vector2(0.0, 1.0):
	set(value):
		outline_gradient_direction = value
		_sync_gradient_uniforms()

@export_group("阴影")

@export var shadow_offset: Vector2 = Vector2.ZERO:
	set(value):
		shadow_offset = value
		_redraw_all_layers()

@export var shadow_thickness: int = 0:
	set(value):
		shadow_thickness = maxi(value, 0)
		_redraw_all_layers()

@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		shadow_color = value

		_rebuild_paint_layers()

@export var shadow_gradient_enabled: bool = false:
	set(value):
		shadow_gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var shadow_gradient_start: Color = Color.WHITE:
	set(value):
		shadow_gradient_start = value
		_rebuild_paint_layers()

@export var shadow_gradient_end: Color = Color(0.55, 0.55, 0.55, 1.0):
	set(value):
		shadow_gradient_end = value
		_rebuild_paint_layers()

@export var shadow_gradient_direction: Vector2 = Vector2(0.0, 1.0):
	set(value):
		shadow_gradient_direction = value
		_sync_gradient_uniforms()

@export_group("")

@export var draw_body: bool = true:
	set(value):
		draw_body = value
		notify_property_list_changed()
		_rebuild_paint_layers()

const _GRADIENT_SHADER: Shader = preload("res://assets/shaders/gradient_text_group.gdshader")

var _layer_roots: Array[CanvasItem] = [null, null, null]

var _layer_paints: Array[GlyphPaintLayer] = [null, null, null]


func _enter_tree() -> void:
	visible_characters = 0


func _ready() -> void:
	if curve == null:
		curve = _make_default_curve()

	_rebuild_paint_layers()
	_sync_fade()
	_warn_if_modulate_used()


func _draw() -> void:
	if visible_characters != 0:
		visible_characters = 0

	if not _is_split_into_layers():
		paint(self)


func _is_split_into_layers() -> bool:
	return gradient_enabled or outline_gradient_enabled or shadow_gradient_enabled


func _shadow_visible() -> bool:
	if shadow_gradient_enabled:
		return shadow_gradient_start.a > 0.0 or shadow_gradient_end.a > 0.0
	return shadow_color.a > 0.0


func _outline_visible() -> bool:
	if outline_thickness <= 0:
		return false
	if outline_gradient_enabled:
		return outline_gradient_start.a > 0.0 or outline_gradient_end.a > 0.0
	return outline_color.a > 0.0


func _redraw_all_layers() -> void:
	queue_redraw()
	for paint_node in _layer_paints:
		if paint_node != null:
			paint_node.queue_redraw()


func _rebuild_paint_layers() -> void:
	if not is_node_ready():
		return
	_clear_paint_layers()
	if _is_split_into_layers():
		if _shadow_visible():
			_create_paint_layer(LayerKind.SHADOW, shadow_gradient_enabled)
		if _outline_visible():
			_create_paint_layer(LayerKind.OUTLINE, outline_gradient_enabled)
		if draw_body:
			_create_paint_layer(LayerKind.BODY, gradient_enabled)
		_sync_gradient_uniforms()

		_sync_fade()
	_redraw_all_layers()


func _clear_paint_layers() -> void:
	for i in _layer_roots.size():
		var root_node: CanvasItem = _layer_roots[i]
		if root_node == null:
			continue
		remove_child(root_node)

		root_node.queue_free()
		_layer_roots[i] = null
		_layer_paints[i] = null


func _create_paint_layer(layer_kind: int, use_gradient: bool) -> void:
	var paint_node := GlyphPaintLayer.new()
	paint_node.host = self
	paint_node.layer_kind = layer_kind
	paint_node.name = "_GlyphLayer%d" % layer_kind
	var root_node: CanvasItem = paint_node
	if use_gradient:
		var gradient_material := ShaderMaterial.new()
		gradient_material.shader = _GRADIENT_SHADER
		var gradient_group := CanvasGroup.new()
		gradient_group.name = "_GradientGroup%d" % layer_kind

		gradient_group.fit_margin = 0.0
		gradient_group.material = gradient_material
		gradient_group.add_child(paint_node)
		root_node = gradient_group

	add_child(root_node, false, Node.INTERNAL_MODE_BACK)
	_layer_roots[layer_kind] = root_node
	_layer_paints[layer_kind] = paint_node


func _sync_gradient_uniforms() -> void:
	_apply_gradient_uniforms(
		LayerKind.SHADOW, shadow_gradient_start, shadow_gradient_end, shadow_gradient_direction
	)
	_apply_gradient_uniforms(
		LayerKind.OUTLINE, outline_gradient_start, outline_gradient_end, outline_gradient_direction
	)
	_apply_gradient_uniforms(
		LayerKind.BODY, gradient_start_color, gradient_end_color, gradient_direction
	)


func _apply_gradient_uniforms(
	layer_kind: int, start_color: Color, end_color: Color, direction: Vector2
) -> void:
	var root_node: CanvasItem = _layer_roots[layer_kind]
	if root_node == null:
		return
	var gradient_material := root_node.material as ShaderMaterial

	if gradient_material == null:
		return
	gradient_material.set_shader_parameter("gradient_start", start_color)
	gradient_material.set_shader_parameter("gradient_end", end_color)
	gradient_material.set_shader_parameter("gradient_direction", direction)


func _sync_fade() -> void:
	self_modulate.a = fade
	for root_node in _layer_roots:
		if root_node != null:
			root_node.self_modulate.a = fade


func _warn_if_modulate_used() -> void:
	if Engine.is_editor_hint():
		return
	if not modulate.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)):
		push_warning(
			(
				"SingleLineGlyphLabel(%s): modulate=%s 非默认值,内部渐变层会被 CanvasGroup 二次应用。请改用 fade 属性。"
				% [name, modulate]
			)
		)


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property["name"]

	if property_name == &"body_color":
		if not draw_body or gradient_enabled:
			property["usage"] = PROPERTY_USAGE_NONE
	elif property_name == &"outline_color":
		if outline_gradient_enabled:
			property["usage"] = PROPERTY_USAGE_NONE
	elif property_name == &"shadow_color":
		if shadow_gradient_enabled:
			property["usage"] = PROPERTY_USAGE_NONE
	elif property_name == &"gradient_enabled":
		if not draw_body:
			property["usage"] = PROPERTY_USAGE_NONE
	elif property_name in [&"gradient_start_color", &"gradient_end_color", &"gradient_direction"]:
		if not gradient_enabled or not draw_body:
			property["usage"] = PROPERTY_USAGE_NONE
	elif (
		property_name
		in [&"outline_gradient_start", &"outline_gradient_end", &"outline_gradient_direction"]
	):
		if not outline_gradient_enabled:
			property["usage"] = PROPERTY_USAGE_NONE
	elif (
		property_name
		in [&"shadow_gradient_start", &"shadow_gradient_end", &"shadow_gradient_direction"]
	):
		if not shadow_gradient_enabled:
			property["usage"] = PROPERTY_USAGE_NONE


func paint(target: CanvasItem) -> void:
	_paint_kinds(target, _all_paint_kinds())


func paint_layer(target: CanvasItem, layer_kind: int) -> void:
	_paint_kinds(target, [layer_kind])


func _all_paint_kinds() -> Array[int]:
	var kinds: Array[int] = [LayerKind.SHADOW, LayerKind.OUTLINE]
	if draw_body:
		kinds.append(LayerKind.BODY)
	return kinds


func _paint_kinds(target: CanvasItem, kinds: Array[int]) -> void:
	var display_text: String = atr(text)

	if display_text.is_empty() or (curve_enabled and curve == null):
		return

	var font: Font = _resolve_font()
	if font == null:
		return
	var font_size: int = _resolve_font_size()

	var text_server: TextServer = TextServerManager.get_primary_interface()
	var line := TextLine.new()
	line.add_string(display_text, font, font_size)
	var glyphs: Array = text_server.shaped_text_get_glyphs(line.get_rid())

	var total_advance: float = _measure_total_advance(glyphs)
	if total_advance <= 0.0:
		return

	var effective_font_size: int = font_size
	if size.x > 0.0 and total_advance > size.x:
		effective_font_size = maxi(1, int(float(font_size) * size.x / total_advance))
		line = TextLine.new()
		line.add_string(display_text, font, effective_font_size)
		glyphs = text_server.shaped_text_get_glyphs(line.get_rid())
		total_advance = _measure_total_advance(glyphs)
		if total_advance <= 0.0:
			return

	var v_align_offset: float = 0.0
	if vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		v_align_offset = (
			(font.get_ascent(effective_font_size) - font.get_descent(effective_font_size)) * 0.5
		)
	elif vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		v_align_offset = -font.get_descent(effective_font_size)

	var x_scale: float = size.x if size.x > 0.0 else total_advance

	var fill_scale: float = 1.0
	var offset_x: float = 0.0
	if effective_font_size < font_size and size.x > 0.0 and total_advance > 0.0:
		fill_scale = size.x / total_advance
	else:
		match horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				offset_x = (size.x - total_advance) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				offset_x = size.x - total_advance

	var tilt_to_tangent: bool = align_to_tangent and curve_enabled

	var cumulative: float = 0.0
	for g in glyphs:
		var advance: float = g["advance"]
		var glyph_width: float = advance * fill_scale
		var glyph_x: float = offset_x + cumulative * fill_scale
		var ratio: float = clampf((glyph_x + glyph_width * 0.5) / x_scale, 0.0, 1.0)

		var curve_offset: float = 0.0
		if curve_enabled:
			curve_offset = (curve.sample(ratio) - 0.5) * amplitude * 2.0
		var glyph_y: float = size.y * 0.5 - curve_offset + v_align_offset
		var glyph_offset: Vector2 = g["offset"]
		if tilt_to_tangent:
			var pivot: Vector2 = Vector2(glyph_x + glyph_width * 0.5, glyph_y) + glyph_offset
			target.draw_set_transform(pivot, _tangent_angle(ratio, x_scale))
			_paint_glyph(
				target, g, Vector2(-glyph_width * 0.5, 0.0), effective_font_size, text_server, kinds
			)
		else:
			var glyph_pos: Vector2 = Vector2(glyph_x, glyph_y) + glyph_offset
			_paint_glyph(target, g, glyph_pos, effective_font_size, text_server, kinds)

		cumulative += advance + letter_spacing

	if tilt_to_tangent:
		target.draw_set_transform(Vector2.ZERO)


func _measure_total_advance(glyphs: Array) -> float:
	var total: float = 0.0
	for g in glyphs:
		total += g["advance"]
	if glyphs.size() > 1:
		total += letter_spacing * float(glyphs.size() - 1)
	return total


func _paint_glyph(
	target: CanvasItem,
	glyph: Dictionary,
	glyph_pos: Vector2,
	font_size: int,
	text_server: TextServer,
	kinds: Array[int]
) -> void:
	var canvas: RID = target.get_canvas_item()
	var font_rid: RID = glyph["font_rid"]
	var glyph_index: int = glyph["index"]

	for kind in kinds:
		match kind:
			LayerKind.SHADOW:
				if _shadow_visible():
					_stroke_glyph(
						text_server,
						font_rid,
						canvas,
						font_size,
						glyph_index,
						glyph_pos + shadow_offset,
						_layer_paint_color(shadow_color, shadow_gradient_enabled),
						shadow_thickness
					)

			LayerKind.OUTLINE:
				if _outline_visible():
					text_server.font_draw_glyph_outline(
						font_rid,
						canvas,
						font_size,
						outline_thickness,
						glyph_pos,
						glyph_index,
						_layer_paint_color(outline_color, outline_gradient_enabled)
					)

			LayerKind.BODY:
				text_server.font_draw_glyph(
					font_rid,
					canvas,
					font_size,
					glyph_pos,
					glyph_index,
					_layer_paint_color(body_color, gradient_enabled)
				)


func _layer_paint_color(original: Color, use_gradient: bool) -> Color:
	if not use_gradient:
		return original
	return Color.WHITE


func _stroke_glyph(
	text_server: TextServer,
	font_rid: RID,
	canvas: RID,
	font_size: int,
	glyph_index: int,
	pos: Vector2,
	color: Color,
	outline_thickness: int
) -> void:
	if outline_thickness > 0:
		text_server.font_draw_glyph_outline(
			font_rid, canvas, font_size, outline_thickness, pos, glyph_index, color
		)
	text_server.font_draw_glyph(font_rid, canvas, font_size, pos, glyph_index, color)


func _tangent_angle(ratio: float, x_scale: float) -> float:
	const DELTA: float = 0.01
	var ratio_before: float = clampf(ratio - DELTA, 0.0, 1.0)
	var ratio_after: float = clampf(ratio + DELTA, 0.0, 1.0)
	var height_delta: float = curve.sample(ratio_after) - curve.sample(ratio_before)

	var tangent := Vector2(x_scale * (ratio_after - ratio_before), -height_delta * amplitude * 2.0)
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
	var default_curve := Curve.new()
	default_curve.add_point(Vector2(0.0, 0.5), 0.0, 2.0)
	default_curve.add_point(Vector2(0.5, 1.0), 0.0, 0.0)
	default_curve.add_point(Vector2(1.0, 0.5), -2.0, 0.0)
	return default_curve
