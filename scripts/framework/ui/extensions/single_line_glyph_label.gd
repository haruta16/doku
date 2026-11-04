## 单行字形渲染器：拆分阴影、描边等绘制层，统一字体测量与渐变参数。
@tool
class_name SingleLineGlyphLabel
extends Label

# 枚举值同时用作两个层数组的下标；顺序从背景阴影到前景字身。
enum LayerKind {
	SHADOW,
	OUTLINE,
	BODY,
}

@export_group("曲线")

@export var curve_enabled: bool = true: # 是否应用曲线高度；false 时沿一条水平基线绘制
	set(value):
		curve_enabled = value
		_redraw_all_layers()

@export var amplitude: float = 80.0: # 曲线半幅（像素）；curve=0.5 为基线，偏移按 amplitude×2 换算
	set(value):
		amplitude = value
		_redraw_all_layers()

@export var align_to_tangent: bool = false: # 曲线开启时让字形沿切线旋转；关闭曲线后此开关无效
	set(value):
		align_to_tangent = value
		_redraw_all_layers()

@export var curve: Curve: # 横轴为整行位置比例，纵轴相对 0.5 决定起伏；替换时重接 changed 信号
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

@export_range(0.0, 1.0) var fade: float = 1.0: # 整段淡入淡出入口；分别同步各层，不用父级 modulate 混色
	set(value):
		fade = value
		_sync_fade()

@export var letter_spacing: float = 0.0: # 相邻字形的额外推进距离（像素），独立于字体自身 advance
	set(value):
		letter_spacing = value
		_redraw_all_layers()

@export_group("字身")

@export var body_color: Color = Color.WHITE: # 纯色字身颜色；开启字身渐变后不参与绘制
	set(value):
		body_color = value
		_redraw_all_layers()

@export var gradient_enabled: bool = false: # 字身渐变开关；开启后使用独立合成层
	set(value):
		gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var gradient_start_color: Color = Color.WHITE: # 字身渐变起点 RGBA，alpha 参与渐隐
	set(value):
		gradient_start_color = value
		_rebuild_paint_layers()

@export var gradient_end_color: Color = Color(0.55, 0.55, 0.55, 1.0): # 字身渐变终点 RGBA
	set(value):
		gradient_end_color = value
		_rebuild_paint_layers()

@export var gradient_direction: Vector2 = Vector2(0.0, 1.0): # 渐变方向非负分量；默认上到下，反向效果交换端点色
	set(value):
		gradient_direction = value
		_sync_gradient_uniforms()

@export_group("描边")

@export var outline_thickness: int = 0: # 描边厚度（像素）；0 不画描边
	set(value):
		outline_thickness = maxi(value, 0)

		_rebuild_paint_layers()

@export var outline_color: Color = Color.BLACK: # 纯色描边颜色；描边渐变开启时忽略
	set(value):
		outline_color = value
		_rebuild_paint_layers()

@export var outline_gradient_enabled: bool = false: # 让描边单独渐变，不与字身共用颜色
	set(value):
		outline_gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var outline_gradient_start: Color = Color.WHITE: # 描边渐变起点 RGBA
	set(value):
		outline_gradient_start = value
		_rebuild_paint_layers()

@export var outline_gradient_end: Color = Color(0.55, 0.55, 0.55, 1.0): # 描边渐变终点 RGBA
	set(value):
		outline_gradient_end = value
		_rebuild_paint_layers()

@export var outline_gradient_direction: Vector2 = Vector2(0.0, 1.0): # 描边层独立的渐变方向
	set(value):
		outline_gradient_direction = value
		_sync_gradient_uniforms()

@export_group("阴影")

@export var shadow_offset: Vector2 = Vector2.ZERO: # 阴影相对字形基线位置的偏移（像素）
	set(value):
		shadow_offset = value
		_redraw_all_layers()

@export var shadow_thickness: int = 0: # 阴影额外扩张的描边厚度；0 仍可绘制实心字形阴影
	set(value):
		shadow_thickness = maxi(value, 0)
		_redraw_all_layers()

@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.0): # 纯色阴影 RGBA；默认全透明，不建可见阴影层
	set(value):
		shadow_color = value

		_rebuild_paint_layers()

@export var shadow_gradient_enabled: bool = false: # 阴影使用独立渐变时，shadow_color 不参与绘制
	set(value):
		shadow_gradient_enabled = value
		notify_property_list_changed()
		_rebuild_paint_layers()

@export var shadow_gradient_start: Color = Color.WHITE: # 阴影渐变起点 RGBA
	set(value):
		shadow_gradient_start = value
		_rebuild_paint_layers()

@export var shadow_gradient_end: Color = Color(0.55, 0.55, 0.55, 1.0): # 阴影渐变终点 RGBA
	set(value):
		shadow_gradient_end = value
		_rebuild_paint_layers()

@export var shadow_gradient_direction: Vector2 = Vector2(0.0, 1.0): # 阴影层独立的渐变方向
	set(value):
		shadow_gradient_direction = value
		_sync_gradient_uniforms()

@export_group("")

@export var draw_body: bool = true: # 是否画字身；可只保留阴影/描边作为其他文字的底层
	set(value):
		draw_body = value
		notify_property_list_changed()
		_rebuild_paint_layers()

const _GRADIENT_SHADER: Shader = preload("res://scripts/framework/ui/shaders/gradient_text_group.gdshader")

var _layer_roots: Array[CanvasItem] = [null, null, null] # 按 LayerKind 索引的层根；纯色是绘制节点，渐变是包裹它的 CanvasGroup

var _layer_paints: Array[GlyphPaintLayer] = [null, null, null] # 对应层真正发出绘制命令的子节点；宿主负责创建和释放


## 关闭 Label 的内置字形显示；保留其主题、文本和对齐属性供自绘读取。
func _enter_tree() -> void:
	visible_characters = 0


## 补默认曲线、建立所需绘制层并同步透明度；运行时提示会导致渐变重复染色的 modulate 用法。
func _ready() -> void:
	if curve == null:
		curve = _make_default_curve()

	_rebuild_paint_layers()
	_sync_fade()
	_warn_if_modulate_used()


## 没有渐变时在自身画布顺序绘制全部层；启用渐变后交给内部独立层，避免重复画字。
func _draw() -> void:
	if visible_characters != 0:
		visible_characters = 0

	if not _is_split_into_layers():
		paint(self)


## 任一层启用渐变就使用分层路径；每层可独立选择纯色或 CanvasGroup 渐变。
func _is_split_into_layers() -> bool:
	return gradient_enabled or outline_gradient_enabled or shadow_gradient_enabled


## 按当前颜色来源判断阴影是否有可见 alpha；渐变时只看两端色，不看 shadow_color。
func _shadow_visible() -> bool:
	if shadow_gradient_enabled:
		return shadow_gradient_start.a > 0.0 or shadow_gradient_end.a > 0.0
	return shadow_color.a > 0.0


## 描边必须有正厚度，并且当前纯色或渐变端点中存在非零 alpha。
func _outline_visible() -> bool:
	if outline_thickness <= 0:
		return false
	if outline_gradient_enabled:
		return outline_gradient_start.a > 0.0 or outline_gradient_end.a > 0.0
	return outline_color.a > 0.0


## 同时请求自身和现存绘制子层重绘，让文字、曲线及样式变化在两种渲染路径中一致生效。
func _redraw_all_layers() -> void:
	queue_redraw()
	for paint_node in _layer_paints:
		if paint_node != null:
			paint_node.queue_redraw()


## 按当前开关拆掉旧层，再以阴影、描边、字身顺序重建；ready 前只保存属性，不创建内部节点。
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


## 先把内部层移出树，再排队释放并清数组引用，避免新旧层在下一帧同时参与绘制。
func _clear_paint_layers() -> void:
	for i in _layer_roots.size():
		var root_node: CanvasItem = _layer_roots[i]
		if root_node == null:
			continue
		remove_child(root_node)

		root_node.queue_free()
		_layer_roots[i] = null
		_layer_paints[i] = null


## 创建一种字形绘制层；启用渐变时外包独立 CanvasGroup，让 shader 对这一层的合成像素染色。
func _create_paint_layer(layer_kind: int, use_gradient: bool) -> void:
	var paint_node := GlyphPaintLayer.new()
	paint_node.host = self
	paint_node.layer_kind = layer_kind
	paint_node.name = "_GlyphLayer%d" % layer_kind
	var root_node: CanvasItem = paint_node
	# 旋转后的字形先画进离屏层，再对合成像素染色；这样渐变不会随逐字 draw_set_transform 断开。
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


## 分别同步阴影、描边和字身的渐变参数；未创建或使用纯色的层由下层入口跳过。
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


## 给指定层的 ShaderMaterial 写两端颜色和方向；参数属于该层，不改共享 shader 资源。
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


## 把 fade 写到自身及各层根节点的 self_modulate，避免父级 modulate 经 CanvasGroup 重复乘色。
func _sync_fade() -> void:
	self_modulate.a = fade
	for root_node in _layer_roots:
		if root_node != null:
			root_node.self_modulate.a = fade


## 运行时检查非默认 modulate 并提示改用 fade；这里只诊断，不改调用方设置。
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


## 在 Inspector 隐藏当前不参与绘制的颜色与渐变参数，防止编辑无效属性产生误解。
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


## 在 target 的绘制回调中按阴影→描边→字身绘制；通常由无渐变路径调用。
func paint(target: CanvasItem) -> void:
	_paint_kinds(target, _all_paint_kinds())


## 供 GlyphPaintLayer 回调，只绘制指定的一层；布局算法与完整绘制路径共用。
func paint_layer(target: CanvasItem, layer_kind: int) -> void:
	_paint_kinds(target, [layer_kind])


## 返回绘制顺序；阴影/描边的可见性在画字时检查，draw_body=false 时完全省略字身。
func _all_paint_kinds() -> Array[int]:
	var kinds: Array[int] = [LayerKind.SHADOW, LayerKind.OUTLINE]
	if draw_body:
		kinds.append(LayerKind.BODY)
	return kinds


## 翻译并排版文本，必要时缩小字号，再将字形映射到直线/曲线并画到 target。
## 位置由排版 advance 与 letter_spacing 累积，曲线旋转围绕每个字形槽的中心。
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

	# 缩小字号后要重新向 TextServer 排版，不能只缩放旧 advance，否则回退字形与实际宽度可能不匹配。
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

	# 整数缩字号后通过推进距离补齐剩余宽度；不直接把字体纹理横向拉伸。
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
		# 曲线横坐标取当前字形槽中心相对整行的比例，保证字号变化后仍沿同一条曲线分布。
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

	# 最后恢复目标画布变换，避免外部后续绘制继承最后一个字形的旋转。
	if tilt_to_tangent:
		target.draw_set_transform(Vector2.ZERO)


## 累加排版推进距离，并在相邻字形之间加入额外字距；最后一个字后不多算一份间距。
func _measure_total_advance(glyphs: Array) -> float:
	var total: float = 0.0
	for g in glyphs:
		total += g["advance"]
	if glyphs.size() > 1:
		total += letter_spacing * float(glyphs.size() - 1)
	return total


## 按 kinds 顺序画同一个字形的阴影、描边和字身；使用字形自带 font_rid，保留回退字体选择。
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


## 纯色层直接用原色；渐变层先画白色覆盖率，最终颜色与 alpha 交给该层 shader。
func _layer_paint_color(original: Color, use_gradient: bool) -> Color:
	if not use_gradient:
		return original
	return Color.WHITE


## 用描边加实心字形组成阴影轮廓；厚度为 0 时只绘制实心字形。
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


## 在 ratio 两侧采样，用局部像素宽高估算切线方向并返回弧度；边缘采样钳在 0..1。
func _tangent_angle(ratio: float, x_scale: float) -> float:
	const DELTA: float = 0.01
	var ratio_before: float = clampf(ratio - DELTA, 0.0, 1.0)
	var ratio_after: float = clampf(ratio + DELTA, 0.0, 1.0)
	var height_delta: float = curve.sample(ratio_after) - curve.sample(ratio_before)

	var tangent := Vector2(x_scale * (ratio_after - ratio_before), -height_delta * amplitude * 2.0)
	return tangent.angle()


## 优先使用 LabelSettings 显式字体，否则读取主题字体。
func _resolve_font() -> Font:
	if label_settings != null and label_settings.font != null:
		return label_settings.font
	return get_theme_font(&"font")


## 优先使用 LabelSettings 的正字号，否则读取主题字号。
func _resolve_font_size() -> int:
	if label_settings != null and label_settings.font_size > 0:
		return label_settings.font_size
	return get_theme_font_size(&"font_size")


## 创建两端位于基线 0.5、中间抬到 1.0 的默认拱形曲线。
func _make_default_curve() -> Curve:
	var default_curve := Curve.new()
	default_curve.add_point(Vector2(0.0, 0.5), 0.0, 2.0)
	default_curve.add_point(Vector2(0.5, 1.0), 0.0, 0.0)
	default_curve.add_point(Vector2(1.0, 0.5), -2.0, 0.0)
	return default_curve
