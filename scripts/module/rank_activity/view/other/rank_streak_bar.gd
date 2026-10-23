## 连胜倍率条；创建档位格、移动高亮遮罩，并协调升档、闪光和加号动画。

class_name RankStreakBar
extends Control

signal tier_animation_finished

const _CELL_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_streak_cell.tscn"
)
const _RANK_DOUBLE_SCENE: PackedScene = preload("res://assets/prefab/effect_rank_double.tscn")
const SliderMask = preload(
	"res://scripts/module/rank_activity/view/other/rank_streak_slider_mask.gd"
)

const _CELL_HEIGHT: float = 78.0

const _WIDE_MAX_TIERS: int = 3

const _GEOMETRY_NARROW: Dictionary = {
	"widths": [169.94, 167.85, 163.6],
	"start_to_mid": 148.55,
	"mid_pitch": 146.0,
	"mid_to_end": 144.03,
	"label_nudges": [4.0, -0.25, -1.0],
	"tip_fast_share": 130.518 / 146.0,
	"right_pads": [0.0, 0.5, 2.0],
}
const _GEOMETRY_WIDE: Dictionary = {
	"widths": [189.94, 187.85, 185.6],
	"start_to_mid": 168.7,
	"mid_pitch": 164.0,
	"mid_to_end": 164.28,
	"label_nudges": [4.0, 1.75, 5.0],
	"tip_fast_share": 157.0 / 169.0,
	"right_pads": [0.0, 0.5, 0.0],
}

const _SLIDER_TEXEL_SCALE: float = 2.0

const _START_CAP_WIDTH: float = 26.0

const _NOTCH_DEPTH: float = 26.0

const _TIP_FAST_DUR: float = 0.233
const _TIP_SETTLE_DUR: float = 0.3
const _TIP_FAST_BEZ: Vector4 = Vector4(0.0, 0.0, 0.836, 0.916)
const _TIP_SETTLE_BEZ: Vector4 = Vector4(0.055, 0.305, 0.374, 0.911)

const _TAIL_DELAY: float = 0.033
const _TAIL_DUR: float = 0.233
const _TAIL_BEZ: Vector4 = Vector4(0.126, 0.556, 1.0, 1.0)

const _NEW_LABEL_SCALE_KEYS: Array = [
	[0.066, 1.0], [0.2, 1.3], [0.433, 1.35], [0.566, 0.85], [0.666, 1.0]
]

const _NEW_LABEL_WHITE_AT: float = 0.1
const _OLD_LABEL_BROWN_AT: float = 0.2
const _LABEL_COLOR_DUR: float = 0.033

const _SHINE_AT: float = 0.499
const _SHINE_LIFE: float = 1.7

const _FLASH_DUR: float = 0.35

const _PLUS_BASE_SCALE: float = 70.0 / 83.0
const _PLUS_POP_DUR: float = 0.1333
const _PLUS_POP_PEAK: float = 1.3
const _PLUS_SETTLE_DUR: float = 0.25
const _PLUS_RISE_AT: float = 0.383
const _PLUS_RISE_DUR: float = 0.6
const _PLUS_RISE: float = 30.0
const _PLUS_FADE_AT: float = 0.75
const _PLUS_FADE_DUR: float = 0.233

const _PLUS_BOTTOM_Y: float = -3.0

@export_group("窄格（Figma 连胜底5）")
@export var narrow_start_current: Texture2D
@export var narrow_start_normal: Texture2D
@export var narrow_mid_current: Texture2D
@export var narrow_mid_normal: Texture2D
@export var narrow_end_current: Texture2D
@export var narrow_end_normal: Texture2D
@export_group("宽格（Figma 连胜底3）")
@export var wide_start_current: Texture2D
@export var wide_start_normal: Texture2D
@export var wide_mid_current: Texture2D
@export var wide_mid_normal: Texture2D
@export var wide_end_current: Texture2D
@export var wide_end_normal: Texture2D
@export_group("升档外发光遮罩（effect_rank_double 的 Glow）")

@export var narrow_mid_glow: Texture2D
@export var narrow_end_glow: Texture2D
@export var wide_mid_glow: Texture2D
@export var wide_end_glow: Texture2D
@export_group("")

@onready var _track: Control = $Track
@onready var _cell_root: Control = $Track/Cells
@onready var _slider_mask: SliderMask = $Track/SliderMask
@onready var _slider: NinePatchRect = $Track/SliderMask/Slider
@onready var _plus_score: LevelFlowScore = $Track/PlusScore

var _cells: Array[RankStreakCell] = []
var _current_index: int = -1
var _wide: bool = false
var _mid_width: float = 0.0
var _tip_fast_share: float = 1.0

var _right_pads: Array = [0.0, 0.0, 0.0]
var _tween: Tween
var _plus_tween: Tween
var _shine_fx: Node = null

var _pending_table: Variant = null


## 按倍率表建立档位格并选择当前高亮位置，UI 不自行推进连胜数。
func setup(table: Array) -> void:
	if not is_node_ready():
		_pending_table = table.duplicate()
		visible = not table.is_empty()
		return
	_kill_tweens()
	_hide_plus()
	_free_shine()
	for cell in _cells:
		_cell_root.remove_child(cell)
		cell.queue_free()
	_cells.clear()
	_current_index = -1
	_slider.visible = false
	visible = not table.is_empty()
	if table.is_empty():
		return
	var count: int = table.size()
	_wide = count <= _WIDE_MAX_TIERS
	var geometry: Dictionary = _GEOMETRY_WIDE if _wide else _GEOMETRY_NARROW
	var widths: Array = geometry["widths"]
	var nudges: Array = geometry["label_nudges"]
	var lefts: Array[float] = _cell_lefts(count, geometry)
	for i in count:
		var shape: int = _shape_of(i, count)
		var cell := _CELL_SCENE.instantiate() as RankStreakCell
		cell.position = Vector2(lefts[i], 0.0)
		cell.size = Vector2(float(widths[shape]), _CELL_HEIGHT)
		_cell_root.add_child(cell)
		var textures: Array[Texture2D] = _shape_textures(shape, _wide)
		cell.setup(int(table[i]), textures[0], textures[1], float(nudges[shape]))
		_cells.append(cell)
	_mid_width = float(widths[1])
	_tip_fast_share = float(geometry["tip_fast_share"])
	_slider.texture = wide_mid_current if _wide else narrow_mid_current
	_right_pads = geometry["right_pads"]

	var last_shape: int = _shape_of(count - 1, count)
	var track_width: float = (
		lefts[count - 1] + float(widths[last_shape]) - float(_right_pads[last_shape])
	)
	_track.offset_left = -track_width * 0.5
	_track.offset_right = track_width * 0.5
	_apply_slider_outline()


func show_tier(index: int) -> void:
	_kill_tweens()
	_free_shine()
	_slider.visible = false
	_current_index = index
	for cell in _cells:
		cell.stop_flash()
	_apply_states(index)


## 衔接档位升高时的移动与闪光，结束后发送演出完成信号供主流程继续。
func play_tier_up(from_index: int, to_index: int) -> void:
	_kill_tweens()
	_free_shine()
	_current_index = to_index
	if to_index < 0 or to_index >= _cells.size():
		return
	if from_index < 0 or from_index >= to_index:
		_apply_states(to_index)
		_tween = create_tween()
		_tween.tween_callback(func() -> void: flash_tier(to_index))
		_tween.tween_interval(_FLASH_DUR)
		_tween.tween_callback(func() -> void: tier_animation_finished.emit())
		return
	_apply_states(from_index)
	var from_cell: RankStreakCell = _cells[from_index]
	var to_cell: RankStreakCell = _cells[to_index]

	var from_right: float = from_cell.position.x + from_cell.size.x
	var start_left: float = from_right - _mid_width
	var end_left: float = to_cell.position.x
	var end_right: float = to_cell.position.x + to_cell.size.x
	var tip_mid: float = from_right + (end_right - from_right) * _tip_fast_share
	var from_release_x: float = from_cell.position.x + (_START_CAP_WIDTH if from_index == 0 else 0.0)

	var span: Dictionary = {"left": start_left, "right": from_right, "released": false}
	_set_slider_span(start_left, from_right)
	_slider.visible = true
	_tween = create_tween().set_parallel(true)
	_tween.tween_method( func(progress: float) -> void:
		span["right"] = lerpf(from_right, tip_mid, CssBezier.evaluate(progress, _TIP_FAST_BEZ))
		_set_slider_span(span["left"], span["right"])
	, 0.0, 1.0, _TIP_FAST_DUR)
	_tween.tween_method( func(progress: float) -> void:
		span["right"] = lerpf(tip_mid, end_right, CssBezier.evaluate(progress, _TIP_SETTLE_BEZ))
		_set_slider_span(span["left"], span["right"])
	, 0.0, 1.0, _TIP_SETTLE_DUR).set_delay(_TIP_FAST_DUR)
	_tween.tween_method( func(progress: float) -> void:
		span["left"] = lerpf(start_left, end_left, CssBezier.evaluate(progress, _TAIL_BEZ))
		if not span["released"] and span["left"] >= from_release_x:
			span["released"] = true
			from_cell.set_current(false)
		_set_slider_span(span["left"], span["right"])
	, 0.0, 1.0, _TAIL_DUR).set_delay(_TAIL_DELAY)
	_tween_label_color(to_cell, RankStreakCell.FONT_NORMAL, RankStreakCell.FONT_HIGHLIGHT, _NEW_LABEL_WHITE_AT)
	_tween_label_color(from_cell, RankStreakCell.FONT_HIGHLIGHT, RankStreakCell.FONT_NORMAL, _OLD_LABEL_BROWN_AT)
	var label: Control = to_cell.get_label()
	for i in range(1, _NEW_LABEL_SCALE_KEYS.size()):
		var prev_key: Array = _NEW_LABEL_SCALE_KEYS[i - 1]
		var key: Array = _NEW_LABEL_SCALE_KEYS[i]
		var target: float = float(key[1])
		_tween.tween_property(label, "scale", Vector2(target, target), float(key[0]) - float(prev_key[0]))\
.set_delay(float(prev_key[0])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_play_shine.bind(to_index)).set_delay(_SHINE_AT)
	_tween.tween_callback(func() -> void:
		_slider.visible = false
		_apply_states(to_index)
	).set_delay(_TIP_FAST_DUR + _TIP_SETTLE_DUR)
	var last_key: Array = _NEW_LABEL_SCALE_KEYS[_NEW_LABEL_SCALE_KEYS.size() - 1]
	_tween.tween_callback(func() -> void: tier_animation_finished.emit())\
.set_delay(maxf(float(last_key[0]), _TIP_FAST_DUR + _TIP_SETTLE_DUR))



func flash_tier(index: int) -> void:
	if index < 0 or index >= _cells.size():
		return
	_cells[index].flash()


func get_tier_global_center(index: int) -> Vector2:
	if index < 0 or index >= _cells.size():
		return _track.get_global_rect().get_center()
	return _cell_root.get_global_transform() * _cells[index].get_label_center()


func set_plus_z_index(z_in_bar: int) -> void:
	_plus_score.z_index = z_in_bar - _track.z_index


func play_plus(amount: int, index: int) -> void:
	if amount <= 0 or index < 0 or index >= _cells.size():
		return
	_hide_plus()
	_plus_score.set_score(amount)
	var box: Vector2 = _plus_score.size
	var anchor: Vector2 = _cells[index].get_label_center()
	var center_y: float = _PLUS_BOTTOM_Y - box.y * 0.5 * _PLUS_BASE_SCALE
	_plus_score.pivot_offset = box * 0.5
	_plus_score.position = Vector2(anchor.x - box.x * 0.5, center_y - box.y * 0.5)
	_plus_score.scale = Vector2.ZERO
	_plus_score.modulate.a = 1.0
	_plus_score.visible = true
	var peak: Vector2 = Vector2.ONE * (_PLUS_BASE_SCALE * _PLUS_POP_PEAK)
	var rest: Vector2 = Vector2.ONE * _PLUS_BASE_SCALE
	_plus_tween = create_tween().set_parallel(true)
	(
		_plus_tween
		. tween_property(_plus_score, "scale", peak, _PLUS_POP_DUR)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_plus_tween
		. tween_property(_plus_score, "scale", rest, _PLUS_SETTLE_DUR)
		. set_delay(_PLUS_POP_DUR)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_plus_tween
		. tween_property(
			_plus_score, "position:y", _plus_score.position.y - _PLUS_RISE, _PLUS_RISE_DUR
		)
		. set_delay(_PLUS_RISE_AT)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_plus_tween.tween_property(_plus_score, "modulate:a", 0.0, _PLUS_FADE_DUR).set_delay(
		_PLUS_FADE_AT
	)
	_plus_tween.tween_callback(_hide_plus).set_delay(_PLUS_FADE_AT + _PLUS_FADE_DUR)


func snap_to(index: int) -> void:
	show_tier(index)
	_hide_plus()


func _cell_lefts(count: int, geometry: Dictionary) -> Array[float]:
	var lefts: Array[float] = [0.0]
	if count < 2:
		return lefts
	var mid_count: int = count - 2
	var x: float = float(geometry["start_to_mid"])
	for k in mid_count:
		lefts.append(x)
		x += float(geometry["mid_pitch"])
	if mid_count == 0:
		lefts.append(float(geometry["start_to_mid"]))
	else:
		lefts.append(lefts[lefts.size() - 1] + float(geometry["mid_to_end"]))
	return lefts


func _shape_of(index: int, count: int) -> int:
	if index == 0:
		return 0
	if index == count - 1:
		return 2
	return 1


func _shape_textures(shape: int, wide: bool) -> Array[Texture2D]:
	var pair: Array[Texture2D] = []
	match shape:
		0:
			pair.append(wide_start_current if wide else narrow_start_current)
			pair.append(wide_start_normal if wide else narrow_start_normal)
		2:
			pair.append(wide_end_current if wide else narrow_end_current)
			pair.append(wide_end_normal if wide else narrow_end_normal)
		_:
			pair.append(wide_mid_current if wide else narrow_mid_current)
			pair.append(wide_mid_normal if wide else narrow_mid_normal)
	return pair


func _glow_mask(shape: int, wide: bool) -> Texture2D:
	if shape == 2:
		return wide_end_glow if wide else narrow_end_glow
	return wide_mid_glow if wide else narrow_mid_glow


func _apply_states(index: int) -> void:
	for i in _cells.size():
		_cells[i].set_current(i == index)
		_cells[i].set_label_highlight(i == index)


func _apply_slider_outline() -> void:
	var shapes: Array = []
	var bridges: Array[Rect2] = []
	for i in _cells.size():
		var cell: RankStreakCell = _cells[i]
		shapes.append([cell.get_normal_texture(), Rect2(cell.position, cell.size)])
		if i >= 1:
			var prev: RankStreakCell = _cells[i - 1]
			var bridge_left: float = cell.position.x
			var bridge_right: float = maxf(
				prev.position.x + prev.size.x, cell.position.x + _NOTCH_DEPTH
			)
			bridges.append(Rect2(bridge_left, 0.0, bridge_right - bridge_left, _CELL_HEIGHT))
	_slider_mask.set_outline(shapes, bridges)


func _set_slider_span(left: float, right: float) -> void:
	_slider.position = Vector2(left, 0.0)
	_slider.size = Vector2(
		maxf(0.0, right - left) * _SLIDER_TEXEL_SCALE, _CELL_HEIGHT * _SLIDER_TEXEL_SCALE
	)


func _tween_label_color(
	cell: RankStreakCell, from_color: Color, to_color: Color, at_sec: float
) -> void:
	(
		_tween
		. tween_method(
			func(color: Color) -> void: cell.set_label_color(color),
			from_color,
			to_color,
			_LABEL_COLOR_DUR
		)
		. set_delay(at_sec)
	)


func _play_shine(index: int) -> void:
	_free_shine()
	if index < 0 or index >= _cells.size():
		return
	var cell: RankStreakCell = _cells[index]
	var fx := _RANK_DOUBLE_SCENE.instantiate() as Control
	var shine := fx.get_node("Shine") as Sprite2D
	var glow := fx.get_node("Glow") as Sprite2D
	shine.texture = cell.get_current_texture()
	var mask: Texture2D = _glow_mask(_shape_of(index, _cells.size()), _wide)
	if mask != null:
		glow.texture = mask
	fx.z_index = 2
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.position = cell.position + cell.size * 0.5 - shine.position

	glow.position.x -= float(_right_pads[_shape_of(index, _cells.size())]) * 0.5
	_track.add_child(fx)
	var anim := fx.get_node("AnimationPlayer") as AnimationPlayer
	anim.play(&"RankDouble")

	anim.advance(0.0)
	_shine_fx = fx
	var cleanup := fx.create_tween()
	cleanup.tween_interval(_SHINE_LIFE)
	cleanup.tween_callback(_on_shine_done.bind(fx))


func _on_shine_done(fx: Node) -> void:
	if _shine_fx == fx:
		_shine_fx = null
	fx.queue_free()


func _free_shine() -> void:
	if is_instance_valid(_shine_fx):
		_shine_fx.queue_free()
	_shine_fx = null


func _hide_plus() -> void:
	if _plus_tween != null and _plus_tween.is_valid():
		_plus_tween.kill()
	_plus_tween = null
	_plus_score.visible = false
	_plus_score.scale = Vector2.ONE


## 停止尚未结束的条内 Tween，防止重设数据后旧动画继续覆盖新位置和颜色。
func _kill_tweens() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _ready() -> void:
	_plus_score.visible = false
	_slider.visible = false
	if _pending_table != null:
		var table: Array = _pending_table
		_pending_table = null
		setup(table)
