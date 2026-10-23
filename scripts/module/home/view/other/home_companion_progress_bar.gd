## 陪伴猫进度条：随数值和主题更新填充样式，并绘制条纹装饰。
extends ProgressBar

const STRIPE_PERIOD: float = 45.2
const STRIPE_WIDTH: float = 27.0
const STRIPE_SLANT: float = 0.518
const STRIPE_COLOR: Color = Color(0.945098, 0.576471, 0.12549, 0.4)

@export var fill_clip: Control
@export var fill_shape: Panel

@export var stripes: Control

var _source_fill: StyleBoxFlat
var _draw_fill: StyleBoxFlat


func _ready() -> void:
	if stripes != null:
		stripes.draw.connect(_draw_stripes)
	_on_theme_changed()
	_refresh_fill()


func _on_theme_changed() -> void:
	if not is_node_ready() or fill_shape == null:
		return
	var source: StyleBoxFlat = get_theme_stylebox("fill") as StyleBoxFlat
	if source == _source_fill:
		return
	if _source_fill != null and _source_fill.changed.is_connected(_on_fill_style_changed):
		_source_fill.changed.disconnect(_on_fill_style_changed)
	_source_fill = source
	if _source_fill == null:
		push_error("HomeCompanionProgressBar: fill must be StyleBoxFlat")
		return
	_draw_fill = _source_fill.duplicate() as StyleBoxFlat
	_draw_fill.draw_center = true
	fill_shape.add_theme_stylebox_override("panel", _draw_fill)
	_source_fill.changed.connect(_on_fill_style_changed)
	_refresh_fill()


func _on_fill_style_changed() -> void:
	_draw_fill.bg_color = _source_fill.bg_color
	for corner: int in 4:
		_draw_fill.set_corner_radius(corner, _source_fill.get_corner_radius(corner))


func _on_value_changed(_display_value: float) -> void:
	_refresh_fill()


func _refresh_fill() -> void:
	if fill_clip == null or fill_shape == null:
		return
	var fill_width: float = size.x * ratio
	fill_clip.size = Vector2(fill_width, size.y)
	fill_clip.visible = fill_width > 0.0

	fill_shape.size = Vector2(maxf(fill_width, size.y), size.y)


func _draw_stripes() -> void:
	var height: float = stripes.size.y
	var slant: float = STRIPE_SLANT * height
	var left: float = -slant
	while left < stripes.size.x:
		stripes.draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(left + slant, 0.0),
					Vector2(left + slant + STRIPE_WIDTH, 0.0),
					Vector2(left + STRIPE_WIDTH, height),
					Vector2(left, height)
				]
			),
			STRIPE_COLOR
		)
		left += STRIPE_PERIOD
