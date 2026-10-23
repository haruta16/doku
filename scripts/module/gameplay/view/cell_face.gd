## 格子底面的自绘控件：用圆角查找纹理拼接四角与实心区域，再叠加可选图案。
@tool
class_name CellFace
extends Control

const CORNER_TABLE_PATH: String = "res://assets/sprites/game/cell_face/cell_corner_table.png"
const TABLE_MAX_RADIUS: int = 64
const TABLE_WIDTH: int = 512
const TABLE_GAP: int = 1
const SOLID_TEXEL: Rect2 = Rect2(1, 1, 1, 1)
const PATTERN_OFFSET: Vector2 = Vector2(-47.0, -47.0)
const PATTERN_SIZE: Vector2 = Vector2(95.0, 95.0)

const RADIUS_REFERENCE_PX: float = 95.0

@export var color: Color = Color.WHITE:
	set(value):
		if color == value:
			return
		color = value
		queue_redraw()

var _radii: Vector4 = Vector4(10.0, 10.0, 10.0, 10.0)
var _hard: bool = false
var _pattern_tex: Texture2D = null
var _pattern_color: Color = Color.WHITE
var _pattern_visible: bool = false
var _drawn_scale_key: int = -1

static var _layout: Dictionary = {}
static var _corner_table: Texture2D = null


## 计算并缓存软边、硬边两套半径纹理在查找表中的矩形位置。
static func table_layout() -> Dictionary:
	if not _layout.is_empty():
		return _layout
	var entries: Array = [[], []]
	var x: int = 3 + TABLE_GAP
	var y: int = 0
	var row_h: int = 3
	for set_idx in 2:
		var rects: Array[Rect2i] = [Rect2i()]
		for r in range(1, TABLE_MAX_RADIUS + 1):
			if x + r > TABLE_WIDTH:
				x = 0
				y += row_h + TABLE_GAP
				row_h = 0
			rects.append(Rect2i(x, y, r, r))
			x += r + TABLE_GAP
			row_h = maxi(row_h, r)
		entries[set_idx] = rects
	_layout = {
		"soft": entries[0],
		"hard": entries[1],
		"size": Vector2i(TABLE_WIDTH, y + row_h),
	}
	return _layout


## 按像素中心到圆边的距离计算覆盖率，硬边模式只返回 0 或 1。
static func corner_coverage(x: int, y: int, r: int, hard: bool) -> float:
	var d: float = Vector2(float(r) - (x + 0.5), float(r) - (y + 0.5)).length() - float(r)
	if hard:
		return 1.0 if d <= 0.0 else 0.0
	return clampf(0.5 - d, 0.0, 1.0)


## 更新四角半径及软硬边模式，变化后请求重绘。
func set_corner_radii(radii: Vector4, hard: bool) -> void:
	if _radii == radii and _hard == hard:
		return
	_radii = radii
	_hard = hard
	queue_redraw()


## 返回左上、右上、右下、左下四角的参考半径。
func get_corner_radii() -> Vector4:
	return _radii


## 返回当前是否使用硬边圆角纹理。
func is_hard() -> bool:
	return _hard


## 更换图案纹理及显示开关，变化后请求重绘。
func set_pattern(texture: Texture2D, shown: bool) -> void:
	if _pattern_tex == texture and _pattern_visible == shown:
		return
	_pattern_tex = texture
	_pattern_visible = shown
	queue_redraw()


## 更新图案色；只有图案可见时需要重绘。
func set_pattern_color(value: Color) -> void:
	if _pattern_color == value:
		return
	_pattern_color = value
	if _pattern_visible:
		queue_redraw()


## 返回图案当前使用的颜色。
func get_pattern_color() -> Color:
	return _pattern_color


## 图案开关开启且已有纹理时才实际绘制。
func is_pattern_drawn() -> bool:
	return _pattern_visible and _pattern_tex != null


## 启用变换通知，让缩放变化可以触发圆角纹理重选。
func _ready() -> void:
	set_notify_transform(true)


## 尺寸变化或屏幕缩放档位变化时请求重绘。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		if _scale_key() != _drawn_scale_key:
			queue_redraw()


## 将屏幕缩放量化为八分之一档，作为重绘判断键。
func _scale_key() -> int:
	return roundi(_screen_scale() * 8.0)


## 解析普通纹理或图集区域，依次绘制底色与图案。
func _draw() -> void:
	_drawn_scale_key = _scale_key()
	var table: Texture2D = _get_corner_table()
	if table == null:
		return
	var base: Texture2D = table
	var origin: Vector2 = Vector2.ZERO
	if table is AtlasTexture:
		base = (table as AtlasTexture).atlas
		origin = (table as AtlasTexture).region.position
	if color.a > 0.0:
		_draw_face(base, origin, color)
	if is_pattern_drawn():
		_draw_pattern()


## 按格子宽度缩放四角半径，用实心块和四张角纹理拼成底面。
func _draw_face(base: Texture2D, origin: Vector2, tint: Color) -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var limit: float = minf(w, h) * 0.5
	var k: float = w / RADIUS_REFERENCE_PX
	var tl: float = clampf(_radii.x * k, 0.0, limit)
	var tr: float = clampf(_radii.y * k, 0.0, limit)
	var br: float = clampf(_radii.z * k, 0.0, limit)
	var bl: float = clampf(_radii.w * k, 0.0, limit)
	var solid: Rect2 = Rect2(origin + SOLID_TEXEL.position, SOLID_TEXEL.size)
	var top: float = maxf(tl, tr)
	var bottom: float = maxf(bl, br)
	_solid(base, solid, tint, Rect2(tl, 0.0, w - tl - tr, top))
	if tl < tr:
		_solid(base, solid, tint, Rect2(0.0, tl, tl, tr - tl))
	elif tr < tl:
		_solid(base, solid, tint, Rect2(w - tr, tr, tr, tl - tr))
	_solid(base, solid, tint, Rect2(0.0, top, w, h - top - bottom))
	_solid(base, solid, tint, Rect2(bl, h - bottom, w - bl - br, bottom))
	if bl < br:
		_solid(base, solid, tint, Rect2(0.0, h - br, bl, br - bl))
	elif br < bl:
		_solid(base, solid, tint, Rect2(w - br, h - bl, br, bl - br))
	var scale_px: float = _screen_scale()
	_corner(base, origin, tint, Rect2(0.0, 0.0, tl, tl), tl * scale_px, false, false)
	_corner(base, origin, tint, Rect2(w - tr, 0.0, tr, tr), tr * scale_px, true, false)
	_corner(base, origin, tint, Rect2(w - br, h - br, br, br), br * scale_px, true, true)
	_corner(base, origin, tint, Rect2(0.0, h - bl, bl, bl), bl * scale_px, false, true)


## 绘制非空实心矩形，复用查找表中的纯色像素。
func _solid(base: Texture2D, src: Rect2, tint: Color, dst: Rect2) -> void:
	if dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return
	draw_texture_rect_region(base, dst, src, tint, false, true)


## 按屏幕半径选取查找表切片，通过翻转得到四个方向的圆角。
func _corner(
	base: Texture2D,
	origin: Vector2,
	tint: Color,
	dst: Rect2,
	screen_radius: float,
	flip_h: bool,
	flip_v: bool
) -> void:
	if dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return
	var r: int = clampi(roundi(screen_radius), 1, TABLE_MAX_RADIUS)
	var entry: Rect2i = (table_layout()["hard" if _hard else "soft"] as Array)[r]
	var src: Rect2 = Rect2(origin + Vector2(entry.position), Vector2(entry.size))
	if flip_h:
		src.size.x = -src.size.x
	if flip_v:
		src.size.y = -src.size.y
	draw_texture_rect_region(base, dst, src, tint, false, true)


## 在格子中心放置图案，兼容图集切片并按像素吸附。
func _draw_pattern() -> void:
	var anchor: Vector2 = position + size * 0.5
	var pattern_pos: Vector2 = _snapped(anchor + PATTERN_OFFSET) - _snapped(position)
	var dst: Rect2 = Rect2(pattern_pos, PATTERN_SIZE)
	if _pattern_tex is AtlasTexture:
		var at: AtlasTexture = _pattern_tex as AtlasTexture
		draw_texture_rect_region(
			at.atlas, _fit_keep_aspect(dst, at.region.size), at.region, _pattern_color, false, true
		)
	else:
		draw_texture_rect(
			_pattern_tex, _fit_keep_aspect(dst, _pattern_tex.get_size()), false, _pattern_color
		)


## 在给定矩形中居中等比缩放纹理，保持原始长宽比。
func _fit_keep_aspect(dst: Rect2, tex_size: Vector2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return dst
	var k: float = minf(dst.size.x / tex_size.x, dst.size.y / tex_size.y)
	var fit: Vector2 = tex_size * k
	return Rect2(dst.position + (dst.size - fit) * 0.5, fit)


## 视口启用控件像素吸附时，将位置舍入到整数像素。
func _snapped(p: Vector2) -> Vector2:
	if is_inside_tree() and get_viewport().is_snap_controls_to_pixels_enabled():
		return (p + Vector2(0.5, 0.5)).floor()
	return p


## 合并视口与节点变换，以横纵缩放的平均值估算屏幕像素比例。
func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var xf: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var s: Vector2 = xf.get_scale().abs()
	return (s.x + s.y) * 0.5


## 首次需要时加载并缓存圆角查找纹理。
static func _get_corner_table() -> Texture2D:
	if _corner_table == null and ResourceLoader.exists(CORNER_TABLE_PATH):
		_corner_table = load(CORNER_TABLE_PATH) as Texture2D
	return _corner_table
