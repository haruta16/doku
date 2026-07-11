extends Control
class_name ComboFeedbackView

const SCORE_BUBBLE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_flow_score.tscn"
)
const ENCOURAGE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_encourage.tscn"
)

const IQ_BASELINE: int = 40
const BUBBLE_HEIGHT: float = 83.0
const BUBBLE_GAP: float = 10.0
const CAT_TOP_UNSCALED: float = 40.0
const ENCOURAGE_Y_OFFSET_ABOVE_SCORE: float = 50.0
const ENCOURAGE_HALF_WIDTHS: Array[float] = [
	128.0,
	149.0,
	180.0,
	220.0,
	212.0,
	225.0,
]

@onready var _combo_label: Label = $ComboLabel
var _board_view: Node
var _score_display: Control
var _iq_display: Control
var _level_label: Label
var _level_display: Control
var _level_value_label: Label
var _hard_tag: Control
var _score_value_label: Label
var _iq_value_label: Label

var _encourage_instance: Node2D = null
var _displayed_score: int = 0
var _is_hard: bool = false


func _ready() -> void:
	z_index = 10
	_combo_label.visible = false
	_board_view = get_node_or_null("../BoardContainer/BoardView")
	_score_display = get_node_or_null("../Header/ScoreDisplay")
	_iq_display = get_node_or_null("../Header/IQDisplay")
	_level_label = get_node_or_null("../Header/LevelLabel") as Label
	_level_display = get_node_or_null("../Header/LevelDisplay")
	if _score_display != null:
		_score_value_label = _score_display.get_node("Value") as Label
	if _iq_display != null:
		_iq_value_label = _iq_display.get_node("Value") as Label
	if _level_display != null:
		_level_value_label = _level_display.get_node("Value") as Label
	var header: Control = get_node_or_null("../Header")
	if header != null:
		_hard_tag = Control.new()
		_hard_tag.layout_mode = 1
		_hard_tag.anchor_top = 0.5
		_hard_tag.anchor_bottom = 0.5
		_hard_tag.offset_left = 685.0
		_hard_tag.offset_right = 835.0
		_hard_tag.offset_top = -72.0
		_hard_tag.offset_bottom = 46.0
		_hard_tag.visible = false
		_hard_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hard_tag.z_index = 10
		header.add_child(_hard_tag)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/sprites/game/hard.png")
		icon.expand_mode = 1
		icon.stretch_mode = 5
		icon.layout_mode = 1
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -22.0
		icon.offset_right = 22.0
		icon.offset_top = 14.0
		icon.offset_bottom = 62.0
		_hard_tag.add_child(icon)
		var lbl := Label.new()

		lbl.text = "GAME_HARD_TAG"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.576, 0.353, 0.353, 1.0))
		lbl.add_theme_font_size_override("font_size", 58)
		if _level_value_label != null:
			lbl.add_theme_font_override("font", _level_value_label.get_theme_font("font"))
		lbl.layout_mode = 1
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		lbl.offset_top = -60.0
		_hard_tag.add_child(lbl)
	_update_display_visibility()
	if ABTestManager.combo_encourage.is_iq_mode():
		_displayed_score = IQ_BASELINE
	else:
		_displayed_score = 0
	_set_score_text_immediate(_displayed_score)


func show_combo(combo_count: int, cell_global_pos: Vector2, total_score: int, gain: int) -> void:
	var has_score: bool = ABTestManager.combo_encourage.has_score_display()
	var base_off: float = _score_bubble_y_offset()
	if ABTestManager.combo_encourage.is_follow_cat():
		if has_score:
			_show_encourage_at_position(
				combo_count, cell_global_pos, base_off + ENCOURAGE_Y_OFFSET_ABOVE_SCORE
			)
		else:
			_show_encourage_at_position(combo_count, cell_global_pos, base_off)
	else:
		_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)
	if has_score:
		_update_score_label(total_score)
		_show_score_bubble(cell_global_pos, gain)


func show_combo_text_only(combo_count: int, cell_global_pos: Vector2) -> void:
	if ABTestManager.combo_encourage.is_follow_cat():
		var has_score: bool = ABTestManager.combo_encourage.has_score_display()
		var base_off: float = _score_bubble_y_offset()
		var y_off: float = base_off + ENCOURAGE_Y_OFFSET_ABOVE_SCORE if has_score else base_off
		_show_encourage_at_position(combo_count, cell_global_pos, y_off)
	else:
		_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)


func _play_combo_feedback_voice(combo_count: int) -> void:
	if ABTestManager.combo_voice.is_enabled():
		SoundManager.play_combo_voice_by_path(
			ABTestManager.combo_voice.get_combo_voice(combo_count)
		)
		return
	if ABTestManager.combo_encourage.should_play_voice():
		SoundManager.play_combo_voice(combo_count, ABTestManager.combo_encourage.is_female_voice())


func show_score_only(cell_global_pos: Vector2, gain: int, total_score: int) -> void:
	_update_score_label(total_score)
	_show_score_bubble(cell_global_pos, gain)


func reset(initial_score: int = 0) -> void:
	_combo_label.visible = false
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null
	_update_display_visibility()
	if ABTestManager.combo_encourage.is_iq_mode():
		_displayed_score = IQ_BASELINE + initial_score
	else:
		_displayed_score = initial_score
	_set_score_text_immediate(_displayed_score)


func _show_encourage_fixed(combo_count: int) -> void:
	_kill_encourage()
	var instance: Node2D = ENCOURAGE_SCENE.instantiate()
	add_child(instance)
	var board_top_y: float = 200.0
	if _board_view != null and _board_view is CanvasItem:
		board_top_y = (_board_view as CanvasItem).global_position.y - global_position.y
	instance.position = Vector2(size.x * 0.5, board_top_y * 0.5 + 11)
	_play_encourage_anim(instance, combo_count, 1)


func _show_encourage_at_position(combo_count: int, global_pos: Vector2, y_offset: float) -> void:
	_kill_encourage()
	var instance: Node2D = ENCOURAGE_SCENE.instantiate()
	add_child(instance)
	var local_pos: Vector2 = global_pos - global_position
	var level_idx: int = clampi(combo_count - 3, 0, 5)
	var half_w: float = ENCOURAGE_HALF_WIDTHS[level_idx]
	var clamped_x: float = clampf(local_pos.x, half_w, size.x - half_w)
	instance.position = Vector2(clamped_x, local_pos.y - y_offset)
	_play_encourage_anim(instance, combo_count, 2)


func _play_encourage_anim(instance: Node2D, combo_count: int, anim_set: int) -> void:
	_encourage_instance = instance
	var level: int = clampi(combo_count - 2, 1, 6)
	var anim_name: String = "Encourage%02d_%d" % [anim_set, level]
	var anim: AnimationPlayer = instance.get_node("AnimationPlayer")
	anim.play(anim_name)
	anim.animation_finished.connect(
		func(_name: StringName) -> void:
			instance.queue_free()
			if _encourage_instance == instance:
				_encourage_instance = null
	)


func _kill_encourage() -> void:
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null


func _score_bubble_y_offset() -> float:
	var board_scale: float = _board_view.scale.x if _board_view != null else 1.0
	return BUBBLE_HEIGHT + BUBBLE_GAP + CAT_TOP_UNSCALED * board_scale


func _show_score_bubble(global_pos: Vector2, gain: int) -> void:
	var bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(bubble)
	bubble.set_score(gain)
	bubble.position = (
		global_pos - global_position - Vector2(bubble.size.x * 0.5, _score_bubble_y_offset())
	)
	var anim: AnimationPlayer = bubble.get_node("AnimationPlayer")
	anim.play("Appear")
	anim.animation_finished.connect(func(_name: StringName) -> void: bubble.queue_free())


func set_hard(is_hard: bool) -> void:
	_is_hard = is_hard
	_update_display_visibility()


func _update_display_visibility() -> void:
	var has_score: bool = ABTestManager.combo_encourage.has_score_display()
	var is_iq: bool = ABTestManager.combo_encourage.is_iq_mode()
	if _score_display != null:
		_score_display.visible = has_score and not is_iq
	if _iq_display != null:
		_iq_display.visible = has_score and is_iq
	if _level_label != null:
		_level_label.visible = not has_score
	if _level_display != null:
		_level_display.visible = has_score
	if _hard_tag != null:
		_hard_tag.visible = has_score and _is_hard
	var three_cols: bool = has_score and _is_hard
	if _level_display != null:
		_level_display.offset_left = 245.0 if three_cols else 302.0
		_level_display.offset_right = 395.0 if three_cols else 502.0
	var score_node: Control = _iq_display if is_iq else _score_display
	if score_node != null:
		score_node.offset_left = -615.0 if three_cols else -502.0
		score_node.offset_right = -465.0 if three_cols else -302.0


func set_level(level_num: int) -> void:
	if _level_value_label != null:
		_level_value_label.text = "%d" % level_num


func _set_score_text_immediate(value: int) -> void:
	if ABTestManager.combo_encourage.is_iq_mode():
		if _iq_value_label != null:
			_iq_value_label.text = "%d" % value
	else:
		if _score_value_label != null:
			_score_value_label.text = "%d" % value


func _update_score_label(total_score: int) -> void:
	var target: int
	if ABTestManager.combo_encourage.is_iq_mode():
		target = IQ_BASELINE + total_score
		if _iq_value_label != null:
			RollingNumber.roll(_iq_value_label, _displayed_score, target, 0.35)
	else:
		target = total_score
		if _score_value_label != null:
			RollingNumber.roll(_score_value_label, _displayed_score, target, 0.35)
	_displayed_score = target
