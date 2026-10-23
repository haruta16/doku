## 关卡缩略图：根据区域与格子数据绘制小尺寸盘面预览。
class_name LevelThumbnail
extends Control

const _TILE_COLOR: Color = Color("#f6efe4")
const _TILE_BORDER: Color = Color("#e6d8c4")
const _TILE_BORDER_W: int = 2
const _CELL_GAP: float = 3.0
const _CELL_CORNER_RATIO: float = 0.12
const _OUTER_PAD: float = 8.0

const _MIN_ROUND_PX: float = 1.5

const _PALETTE_SIZE: int = 15

static var _palette: PackedColorArray = _build_palette()


static func _build_palette() -> PackedColorArray:
	var colors := PackedColorArray()
	for i: int in range(_PALETTE_SIZE):
		colors.append(Color.from_hsv(float(i) / float(_PALETTE_SIZE), 0.55, 0.92))
	return colors


var _size: int = 0
var _regions: Array = []


func setup(region_map: Array, sz: int) -> void:
	_size = sz
	_regions = region_map
	queue_redraw()


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = _TILE_COLOR
	box.set_corner_radius_all(10)
	box.set_border_width_all(_TILE_BORDER_W)
	box.border_color = _TILE_BORDER
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if _size <= 0 or _regions.size() != _size:
		return

	var side: float = minf(size.x, size.y) - _OUTER_PAD * 2.0
	if side <= 0.0:
		return
	var slot: float = side / float(_size)
	var origin: Vector2 = (size - Vector2(side, side)) * 0.5
	var inset: float = maxf(0.5, _CELL_GAP * 0.5)
	var corner: float = maxf(0.0, (slot - inset * 2.0) * _CELL_CORNER_RATIO)
	var rounded: bool = corner >= _MIN_ROUND_PX

	var styles: Dictionary = {}

	for r: int in range(_size):
		var row: Array = _regions[r]
		for c: int in range(_size):
			var rid: int = int(row[c])
			var col: Color = _palette[rid % _palette.size()]
			var rect: Rect2 = _cell_rect(origin, slot, inset, r, c)
			if rounded:
				draw_style_box(_cell_style(styles, col, corner), rect)
			else:
				draw_rect(rect, col, true)


func _cell_rect(origin: Vector2, slot: float, inset: float, r: int, c: int) -> Rect2:
	var x0: float = roundf(origin.x + float(c) * slot + inset)
	var y0: float = roundf(origin.y + float(r) * slot + inset)
	var x1: float = roundf(origin.x + float(c + 1) * slot - inset)
	var y1: float = roundf(origin.y + float(r + 1) * slot - inset)
	return Rect2(x0, y0, maxf(1.0, x1 - x0), maxf(1.0, y1 - y0))


static func _cell_style(cache: Dictionary, col: Color, corner: float) -> StyleBoxFlat:
	if cache.has(col):
		return cache[col]
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(roundf(corner)))
	cache[col] = sb
	return sb
