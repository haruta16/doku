# 曲线文字 Label（@tool）：不用内置排版，逐个字形绘制，按 Curve 采样决定每个字的 y 偏移，可选让字沿切线旋转
@tool
class_name CurveLabel
extends Label

# ---- Inspector 参数 ----
# 起伏曲线：采样 x∈[0,1] → y∈[0,1]，0.5 是基线；置空会给一条默认拱形曲线
@export var curve: Curve:
	set(v):
		if curve != null and curve.changed.is_connected(queue_redraw): # 换曲线时先把旧的 changed 连接摘掉
			curve.changed.disconnect(queue_redraw)
		curve = v
		if curve == null:
			curve = _make_default_curve() # curve 为 null 时兜底成默认曲线
		if not curve.changed.is_connected(queue_redraw): # 监听曲线编辑：数据一变就重绘
			curve.changed.connect(queue_redraw)
		queue_redraw()

@export var amplitude: float = 80.0: # 起伏幅度（像素）：y 偏移 = (curve(t) - 0.5) * amplitude * 2
	set(v):
		amplitude = v
		queue_redraw()

@export var align_to_tangent: bool = false: # 是否让每个字形沿曲线切线旋转（做弧形标题用）
	set(v):
		align_to_tangent = v
		queue_redraw()


# ================= 生命周期 =================
# 进树就把可见字数置 0：彻底关掉内置排版，画面全交给 _draw
func _enter_tree() -> void:
	visible_characters = 0


# 保证 curve 不为空
func _ready() -> void:
	if curve == null:
		curve = _make_default_curve()


# ================= 绘制 =================
# 逐个字形绘制：先量总宽，超宽就整体缩字号再拉伸回满宽，然后按曲线算每个字的 y，可选按切线旋转
func _draw() -> void:
	if visible_characters != 0: # 内置绘制已被禁用（visible_characters=0），这里只画自定义部分
		visible_characters = 0
	var display_text: String = atr(text) # 文案走翻译
	if display_text.is_empty() or curve == null:
		return

	var font: Font = _resolve_font()
	if font == null:
		return
	var font_size: int = _resolve_font_size()

	var ts: TextServer = TextServerManager.get_primary_interface() # 直接找 TextServer 拿字形表，才拿得到每个字的 advance 与 offset
	var line := TextLine.new()
	line.add_string(display_text, font, font_size)
	var glyphs: Array = ts.shaped_text_get_glyphs(line.get_rid())

	var total_advance := 0.0
	for g in glyphs:
		total_advance += g["advance"]
	if total_advance <= 0.0:
		return

	var effective_font_size := font_size
	if size.x > 0.0 and total_advance > size.x: # 文本比控件宽：按比例缩小字号，然后重新取一遍字形
		effective_font_size = maxi(1, int(float(font_size) * size.x / total_advance))
		line = TextLine.new()
		line.add_string(display_text, font, effective_font_size)
		glyphs = ts.shaped_text_get_glyphs(line.get_rid())
		total_advance = 0.0
		for g in glyphs:
			total_advance += g["advance"]
		if total_advance <= 0.0:
			return

	var x_scale: float = size.x if size.x > 0.0 else total_advance # 归一化用的总宽；size.x 无效时退回文本自身宽度

	var fill_scale := 1.0 # 缩过字号的情况：把字距按比例拉回控件宽度（等比填充）
	var offset_x := 0.0
	if effective_font_size < font_size and size.x > 0.0 and total_advance > 0.0:
		fill_scale = size.x / total_advance
	else:
		match horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				offset_x = (size.x - total_advance) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				offset_x = size.x - total_advance

	var cumulative := 0.0
	for g in glyphs:
		var adv: float = g["advance"]
		var glyph_w: float = adv * fill_scale
		var x := offset_x + cumulative * fill_scale
		var t := clampf((x + glyph_w * 0.5) / x_scale, 0.0, 1.0) # t = 字形中心在整段文字里的比例，用来采样曲线
		var y := size.y * 0.5 - (curve.sample(t) - 0.5) * amplitude * 2.0 # 曲线 0.5 处为基线，偏离量乘 amplitude*2 换成像素
		var glyph_offset: Vector2 = g["offset"]
		if align_to_tangent: # 沿切线对齐：以字形中心为轴旋转，再以中心为原点绘制
			var pivot := Vector2(x + glyph_w * 0.5, y) + glyph_offset
			draw_set_transform(pivot, _tangent_angle(t, x_scale))
			_draw_glyph(g, Vector2(-glyph_w * 0.5, 0.0), effective_font_size, ts) # 左移半个字宽，让旋转轴落在字形中心
		else:
			var pos := Vector2(x, y) + glyph_offset
			_draw_glyph(g, pos, effective_font_size, ts)
		cumulative += adv

	if align_to_tangent: # 收尾：清掉画布变换，免得影响后续绘制
		draw_set_transform(Vector2.ZERO)


# 画单个字形：按 阴影 → 描边 → 字面 的顺序；样式优先取 label_settings，否则取主题
func _draw_glyph(g: Dictionary, pos: Vector2, font_size: int, ts: TextServer) -> void:
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
			get_theme_constant(&"shadow_offset_x"), get_theme_constant(&"shadow_offset_y")
		)

	var canvas := get_canvas_item()
	var font_rid: RID = g["font_rid"]
	var index: int = g["index"]

	if shadow_color.a > 0.0:
		var shadow_pos := pos + shadow_offset
		if shadow_size > 0:
			ts.font_draw_glyph_outline(
				font_rid, canvas, font_size, shadow_size, shadow_pos, index, shadow_color
			)
		ts.font_draw_glyph(font_rid, canvas, font_size, shadow_pos, index, shadow_color)

	if outline_size > 0 and outline_color.a > 0.0:
		ts.font_draw_glyph_outline(
			font_rid, canvas, font_size, outline_size, pos, index, outline_color
		)

	ts.font_draw_glyph(font_rid, canvas, font_size, pos, index, font_color)


# 用中心差分估算曲线在 t 处的倾角（返回弧度）
func _tangent_angle(t: float, x_scale: float) -> float:
	const DT := 0.01
	var t0 := clampf(t - DT, 0.0, 1.0)
	var t1 := clampf(t + DT, 0.0, 1.0)
	var dy := curve.sample(t1) - curve.sample(t0)

	var tangent := Vector2(x_scale * (t1 - t0), -dy * amplitude * 2.0)
	return tangent.angle()


# 字体：优先 label_settings，其次主题
func _resolve_font() -> Font:
	if label_settings != null and label_settings.font != null:
		return label_settings.font
	return get_theme_font(&"font")


# 字号：同上
func _resolve_font_size() -> int:
	if label_settings != null and label_settings.font_size > 0:
		return label_settings.font_size
	return get_theme_font_size(&"font_size")


# 默认曲线：两端 0.5、中间 1.0 的拱形
func _make_default_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5), 0.0, 2.0)
	c.add_point(Vector2(0.5, 1.0), 0.0, 0.0)
	c.add_point(Vector2(1.0, 0.5), -2.0, 0.0)
	return c
