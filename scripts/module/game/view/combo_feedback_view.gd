## 连击反馈控件：协调分数、鼓励文字和语音，重置时清理残留特效。
extends Control
class_name ComboFeedbackView

# ---- 场景与数值常量 ----
const SCORE_BUBBLE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_flow_score.tscn"
)
const ENCOURAGE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_encourage.tscn"
)
const AUTO_X_BANNER_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/auto_x_fill_mode_banner.tscn"
)

const FULL_MARK_TEXT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/full_mark_text.tscn"
)

const CAT_TOAST_TEXT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/cat_toast_text.tscn"
)

const NEAR_DEATH_TEXT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/near_death_text.tscn"
)
const GOOD_EYE_TEXT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/good_eye_text.tscn"
)
const _SE_TRAIL_SCENE: PackedScene = preload("res://assets/prefab/effect_score_trail.tscn")
const _SE_BURST_SCENE: PackedScene = preload("res://assets/prefab/effect_score_burst.tscn")
const _HARD_ICON_TEXTURE: Texture2D = preload("res://assets/sprites/game/hard.png")

const BUBBLE_HEIGHT: float = 83.0 # 气泡高度（像素）
const BUBBLE_GAP: float = 10.0 # 气泡与猫之间的间隙（像素）
const CAT_TOP_UNSCALED: float = 50.0
const ENCOURAGE_Y_OFFSET_ABOVE_SCORE: float = 50.0 # 有分数板时鼓励再往上抬的偏移（像素）
const SE_MULTIPLIER_BUBBLE_HEIGHT: float = 83.0
const ENCOURAGE_VISUAL_BOTTOM: float = 60.0

const ENCOURAGE_INK_CENTER_OFFSET: float = 3.0
const AUTO_X_TOTAL_Y_BELOW: float = 120.0
const AUTO_X_TOTAL_BANNER_GAP: float = 20.0
const AUTO_X_TOTAL_BANNER_Y_UP: float = 300.0
const AUTO_X_BUBBLE_APPEAR_HOLD_SEC: float = 0.483
const AUTO_X_BUBBLE_FADE_SEC: float = 0.3

const AUTO_X_BANNER_HOLD_AT_SEC: float = 1.05

const _SE_FLY_DURATION: float = 0.57
const _SE_BOUNCE_SCALE: float = 1.2
const _SE_BOUNCE_UP_DURATION: float = 0.1
const _SE_BOUNCE_DOWN_DURATION: float = 0.2
const _SE_TRAIL_Z: int = 41
const _SE_TRAIL_LINGER: float = 0.067

const _SE_FLY_DELAY: float = 0.8

# ---- 子节点与兄弟节点引用 ----
@onready var _combo_label: Label = $ComboLabel # COMBO 文字
var _board_view: Node # 棋盘视图
var _score_display: Control # 分数板
var _level_label: Label # 关卡号文本
var _level_display: Control # 关卡号面板
var _level_value_label: Label # 关卡号数值
var _hard_tag: Control # 困难标记

var _hard_tag_icon: TextureRect
var _hard_tag_lbl: Label
var _level_title_label: Label
var _level_fire: TextureRect
var _score_value_label: Label # 分数数值

# ---- 运行时状态 ----
var _encourage_instance: Node2D = null # 当前在播的鼓励实例
var _auto_x_banner_instance: Control = null
var _displayed_score: int = 0 # 当前显示的分数（IQ 模式含基础分）
var _is_hard: bool = false # 本关是否困难

var _is_super_hard: bool = false

var _is_inserted_level: bool = false

var _level_value_num: int = -1
var _reset_generation: int = 0
var _last_clamped_center_x: float = -1.0

var _last_clamped_source_pos: Vector2 = Vector2(-1.0, -1.0)

var _share_center_with_text: bool = false


func get_score_display() -> Control:
	return _score_display


func get_encourage_instance() -> Node2D:
	return _encourage_instance


func _ready() -> void:
	z_index = 10
	_combo_label.visible = false
	_board_view = get_node_or_null("../BoardContainer/BoardView")
	_score_display = get_node_or_null("../Header/ScoreDisplay")
	_level_label = get_node_or_null("../Header/LevelLabel") as Label
	_level_display = get_node_or_null("../Header/LevelDisplay")
	if _score_display != null:
		_score_value_label = _score_display.get_node("Value") as Label

		if _score_value_label != null:
			_score_base_color = _score_value_label.get_theme_color("font_color")
	if _level_display != null:
		_level_value_label = _level_display.get_node("Value") as Label
		_level_title_label = _level_display.get_node("Title") as Label

		_level_fire = TextureRect.new()
		_level_fire.texture = _HARD_ICON_TEXTURE
		_level_fire.expand_mode = 1
		_level_fire.stretch_mode = 5
		_level_fire.visible = false
		_level_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_level_fire.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_level_display.add_child(_level_fire)
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
		icon.texture = _HARD_ICON_TEXTURE
		icon.expand_mode = 1
		icon.stretch_mode = 5
		icon.layout_mode = 1
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -22.0
		icon.offset_right = 22.0
		icon.offset_top = 14.0
		icon.offset_bottom = 62.0
		_hard_tag.add_child(icon)
		_hard_tag_icon = icon
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
		_hard_tag_lbl = lbl
	_update_display_visibility()
	_displayed_score = 0
	_set_score_text_immediate(_displayed_score)


func show_combo(combo_count: int, cell_global_pos: Vector2, total_score: int, gain: int) -> void:
	_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)
	_update_score_label(total_score)
	show_score_bubble(cell_global_pos, gain)


func show_combo_text_only(combo_count: int, _cell_global_pos: Vector2) -> void:
	_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)


func _play_combo_feedback_voice(combo_count: int) -> void:
	SoundManager.play_people_voice(ABTestManager.combo_voice.get_combo_voice(combo_count))


func show_score_only(
	cell_global_pos: Vector2, gain: int, total_score: int, like_hand_hw: float = 0.0
) -> void:
	_update_score_label(total_score)
	var local_x: float = cell_global_pos.x - global_position.x
	var tmp: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(tmp)
	tmp.set_score(gain)
	var half_widths: Array[float] = [tmp.get_content_width() * 0.5]
	if like_hand_hw > 0.0:
		half_widths.append(like_hand_hw)
	tmp.queue_free()
	var local_pos: Vector2 = cell_global_pos - global_position
	var cx: float = compute_clamped_center_x(local_pos, half_widths, like_hand_hw > 0.0)
	show_score_bubble(cell_global_pos, gain, cx)


func reset(score: int = 0) -> void:
	_reset_generation += 1

	_last_clamped_source_pos = Vector2(-1.0, -1.0)
	_clear_pending_score_stage()
	_last_clamped_center_x = -1.0
	_combo_label.visible = false
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null
	if _auto_x_banner_instance != null and is_instance_valid(_auto_x_banner_instance):
		_auto_x_banner_instance.queue_free()
	_auto_x_banner_instance = null
	_cleanup_residual_effects()
	_update_display_visibility()
	_displayed_score = score
	_set_score_text_immediate(_displayed_score)


func _cleanup_residual_effects() -> void:
	for child in get_children():
		if child is LevelFlowScore:
			child.queue_free()
	var host: Node = _get_effect_host()
	if host != null:
		for child in host.get_children():
			if (
				child.get_node_or_null("ScoreTrail") != null
				or child.get_node_or_null("GlowAlp") != null
			):
				child.queue_free()
	if _score_value_label != null:
		_score_value_label.scale = Vector2.ONE

	if _score_fx_root != null:
		_score_fx_root.scale = Vector2.ONE


func show_encourage_for_combo(combo_count: int) -> void:
	_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)


func _show_encourage_fixed(combo_count: int) -> void:
	_kill_encourage()
	var instance: Node2D = ENCOURAGE_SCENE.instantiate()
	instance.position = Vector2(size.x * 0.5, _encourage_center_y())
	add_child(instance)
	_play_encourage_anim(instance, combo_count)


func _encourage_center_y() -> float:
	var bar_top_y: float = _fused_progress_bar_top_y()
	if bar_top_y >= 0.0:
		return bar_top_y * 0.5 + ENCOURAGE_INK_CENTER_OFFSET
	var board_top_y: float = 200.0
	if _board_view != null and _board_view is CanvasItem:
		board_top_y = (_board_view as CanvasItem).global_position.y - global_position.y
	return board_top_y * 0.5 + 11


func _fused_progress_bar_top_y() -> float:
	var bar: CanvasItem = get_node_or_null("../BoardContainer/CatProgressBar") as CanvasItem
	if bar == null or not bar.is_visible_in_tree():
		return -1.0
	return bar.global_position.y - global_position.y


func show_auto_x_banner() -> void:
	prepare_auto_x_banner()
	play_auto_x_banner_appear()


func prepare_auto_x_banner(title_key: String = "WIN_X_FREE_BONUS") -> void:
	if _auto_x_banner_instance != null and is_instance_valid(_auto_x_banner_instance):
		return
	_kill_encourage()
	var banner: Control = AUTO_X_BANNER_SCENE.instantiate()
	add_child(banner)
	_auto_x_banner_instance = banner
	banner.z_index = 0

	var inner: Control = banner.get_node_or_null("Control")
	var content_w: float = inner.size.x if inner != null else banner.size.x
	banner.position.x = (size.x - content_w) * 0.5
	banner.position.y -= 150.0

	var label: Label = banner.get_node_or_null("Control/SpineSprite/SpineBoneNode/Label") as Label
	if label != null:
		label.text = tr(title_key).replace("✕", "x")
	var anim: AnimationPlayer = banner.get_node_or_null("AnimationPlayer")
	if anim != null:
		anim.play("RESET")
		anim.advance(0.0)

	var spine: SpineSprite = banner.get_node_or_null("Control/SpineSprite") as SpineSprite
	if spine != null:
		var spine_anim: AnimationPlayer = (
			banner.get_node_or_null("Control/SpineSprite/SpineAnimationTrack/SpineSprite Track 0")
			as AnimationPlayer
		)
		if spine_anim != null:
			spine_anim.stop()
			spine_anim.play("Appear")
			spine_anim.advance(0.0)
		var state := spine.get_animation_state()
		if state != null:
			state.set_time_scale(0.0)


func play_auto_x_banner_appear(pause_at: float = -1.0) -> void:
	prepare_auto_x_banner()
	var anim: AnimationPlayer = _get_auto_x_banner_anim()
	if anim == null:
		return
	var spine: SpineSprite = (
		_auto_x_banner_instance.get_node_or_null("Control/SpineSprite") as SpineSprite
	)
	if spine != null:
		var state := spine.get_animation_state()
		if state != null:
			state.set_time_scale(1.0)
	anim.speed_scale = 1.0
	anim.play("Appear")
	anim.advance(0.0)

	SoundManager.play(SoundManager.Kind.AUTO_X_BANNER_APPEAR)
	if pause_at <= 0.0:
		return
	await get_tree().create_timer(pause_at).timeout
	anim = _get_auto_x_banner_anim()
	if anim == null:
		return
	anim.seek(pause_at, true)

	anim.speed_scale = 0.0


func resume_auto_x_banner_appear() -> void:
	var anim: AnimationPlayer = _get_auto_x_banner_anim()
	if anim != null:
		anim.speed_scale = 1.0


func _get_auto_x_banner_anim() -> AnimationPlayer:
	if _auto_x_banner_instance == null or not is_instance_valid(_auto_x_banner_instance):
		return null
	return _auto_x_banner_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer


func spawn_auto_x_total_bubble(total: int, roll_duration: float) -> LevelFlowScore:
	if total <= 0:
		return null

	var center_x: float = size.x * 0.5
	var center_y: float
	if _auto_x_banner_instance != null and is_instance_valid(_auto_x_banner_instance):
		var banner_inner: Control = _auto_x_banner_instance.get_node_or_null("Control")
		if banner_inner != null:
			var inner_bottom_local: float = (
				(banner_inner.global_position.y - global_position.y) + banner_inner.size.y
			)
			center_y = inner_bottom_local + AUTO_X_TOTAL_BANNER_GAP - AUTO_X_TOTAL_BANNER_Y_UP
		else:
			center_y = (
				(_auto_x_banner_instance.position.y)
				+ AUTO_X_TOTAL_BANNER_GAP
				- AUTO_X_TOTAL_BANNER_Y_UP
			)
	else:
		var board_top_y: float = 200.0
		if _board_view != null and _board_view is CanvasItem:
			board_top_y = (_board_view as CanvasItem).global_position.y - global_position.y
		center_y = board_top_y * 0.5 + 11 + AUTO_X_TOTAL_Y_BELOW
	var center: Vector2 = Vector2(center_x, center_y)

	var bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(bubble)
	bubble.z_index = 51
	bubble.get_node("HBox").modulate.a = 0.0

	bubble.set_score(total if roll_duration <= 0.0 else 0)
	bubble.position = Vector2(center.x - bubble.size.x * 0.5, center.y - bubble.size.y * 0.5)
	var anim: AnimationPlayer = bubble.get_node("AnimationPlayer")

	anim.play("Appear")
	anim.seek(AUTO_X_BUBBLE_APPEAR_HOLD_SEC, true)
	anim.pause()

	if roll_duration > 0.0:
		var tw: Tween = bubble.create_tween()
		(
			tw
			. tween_method(
				func(v: int) -> void:
					if is_instance_valid(bubble):
						bubble.set_score(v),
				0,
				total,
				roll_duration
			)
			. set_ease(Tween.EASE_OUT)
			. set_trans(Tween.TRANS_QUAD)
		)
		bubble.set_meta("roll_tween", tw)
	return bubble


func roll_auto_x_total_bubble(
	bubble: LevelFlowScore, from_value: int, to_value: int, duration: float
) -> void:
	if bubble == null or not is_instance_valid(bubble):
		return
	if duration <= 0.0:
		bubble.set_score(to_value)
		return
	var tw: Tween = bubble.create_tween()
	(
		tw
		. tween_method(
			func(v: int) -> void:
				if is_instance_valid(bubble):
					bubble.set_score(v),
			from_value,
			to_value,
			duration
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	bubble.set_meta("roll_tween", tw)
	await tw.finished


func fly_auto_x_total_score(bubble: LevelFlowScore, on_arrive: Callable, pause_sec: float) -> void:
	if bubble == null or not is_instance_valid(bubble):
		if on_arrive.is_valid():
			on_arrive.call()
		return

	var roll_tw: Variant = bubble.get_meta("roll_tween", null)

	if roll_tw != null and (roll_tw as Tween).is_running():
		await (roll_tw as Tween).finished

	if pause_sec > 0.0:
		await get_tree().create_timer(pause_sec).timeout
	if not is_instance_valid(bubble):
		if on_arrive.is_valid():
			on_arrive.call()
		return

	var from_global: Vector2 = bubble.global_position + bubble.size * 0.5
	var hbox: Control = bubble.get_node("HBox")
	var fade_tw: Tween = bubble.create_tween()
	fade_tw.tween_property(hbox, "modulate:a", 0.0, AUTO_X_BUBBLE_FADE_SEC)
	fade_tw.tween_callback(bubble.queue_free)
	var fly_tw: Tween = _play_auto_x_score_fly(from_global, on_arrive)
	if fly_tw != null:
		await fly_tw.finished


func _play_auto_x_score_fly(from_global_pos: Vector2, on_arrive: Callable = Callable()) -> Tween:
	if _score_value_label == null:
		return null
	var to_pos: Vector2 = _score_value_label.global_position + _score_value_label.size * 0.5
	var trail: Node = _SE_TRAIL_SCENE.instantiate()
	_get_effect_host().add_child(trail)
	trail.z_index = _SE_TRAIL_Z
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return null
	sprite.global_position = from_global_pos
	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from_global_pos
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false
	for child in sprite.get_children():
		if child is CPUParticles2D:
			sprite.remove_child(child)
			fly_target.add_child(child)
			(child as CPUParticles2D).visible = true
			(child as CPUParticles2D).emitting = true
	var tw: Tween = trail.create_tween()
	tw.tween_method(
		func(t: float) -> void:
			if is_instance_valid(fly_target):
				fly_target.global_position = _se_fly_pos(t, from_global_pos, to_pos)
				sprite.notify_target_moved(),
		0.0,
		1.0,
		_SE_FLY_DURATION
	)
	tw.tween_callback(_on_auto_x_trail_arrived.bind(trail, to_pos, _reset_generation, on_arrive))
	return tw


func _on_auto_x_trail_arrived(
	trail: Node, pos: Vector2, gen: int, on_arrive: Callable = Callable()
) -> void:
	if is_instance_valid(trail):
		trail.queue_free()
	if gen != _reset_generation:
		return

	if on_arrive.is_valid():
		on_arrive.call()

	var burst: Node = _SE_BURST_SCENE.instantiate()
	_get_effect_host().add_child(burst)
	burst.z_index = _SE_TRAIL_Z
	burst.global_position = pos
	for child_name: String in ["GlowAlp", "StarAlp", "StarAdd"]:
		var p: Node = burst.get_node_or_null(child_name)
		if p != null and p is CPUParticles2D:
			(p as CPUParticles2D).emitting = true
	var burst_tw: Tween = burst.create_tween()
	burst_tw.tween_interval(1.5)
	burst_tw.tween_callback(burst.queue_free)
	_play_se_score_bar_bounce()


func _play_encourage_anim(instance: Node2D, combo_count: int) -> void:
	_encourage_instance = instance
	var level: int = clampi(combo_count - 2, 1, ComboTextConfig.ENCOURAGE_LEVEL_MAX)
	var anim: AnimationPlayer = instance.get_node(ComboTextConfig.ENCOURAGE_PLAYER)
	var animation_name: StringName = instance.prepare_animation(
		level, ABTestManager.combo_text.uses_japanese_text()
	)
	anim.animation_finished.connect(
		func(_name: StringName) -> void:
			if not is_instance_valid(instance):
				return
			instance.queue_free()
			if _encourage_instance == instance:
				_encourage_instance = null
	)
	anim.play(animation_name)
	anim.advance(0.0)


## 杀掉当前鼓励实例
func _kill_encourage() -> void:
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null


func get_score_bubble_y_offset() -> float:
	var board_scale: float = _board_view.scale.x if _board_view != null else 1.0
	return BUBBLE_HEIGHT + BUBBLE_GAP + CAT_TOP_UNSCALED * board_scale


func compute_clamped_center_x(
	cell_local_pos: Vector2, half_widths: Array[float], share_with_text: bool = false
) -> float:
	var max_half_width: float = 0.0
	for half_width: float in half_widths:
		max_half_width = maxf(max_half_width, half_width)
	_last_clamped_source_pos = cell_local_pos
	_last_clamped_center_x = clampf(cell_local_pos.x, max_half_width, size.x - max_half_width)
	_share_center_with_text = share_with_text
	if share_with_text:
		_realign_text_lines_x(cell_local_pos)
	return _last_clamped_center_x


func get_last_clamped_center_x() -> float:
	return _last_clamped_center_x


func clear_last_clamped_center_x() -> void:
	_last_clamped_center_x = -1.0
	_last_clamped_source_pos = Vector2(-1.0, -1.0)
	_share_center_with_text = false


func _collect_se_half_widths(gain: int, like_hand_hw: float = 0.0) -> Array[float]:
	var hws: Array[float] = []
	if like_hand_hw > 0.0:
		hws.append(like_hand_hw)
	var score_bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(score_bubble)
	score_bubble.set_score(gain)
	var score_cw: float = score_bubble.get_content_width()
	score_bubble.queue_free()
	hws.append(score_cw * 0.5)
	return hws


func _clamp_bubble_x(bubble: Control) -> void:
	var cw: float = (
		bubble.get_content_width() if bubble.has_method("get_content_width") else bubble.size.x
	)
	var inset: float = (bubble.size.x - cw) * 0.5
	bubble.position.x = clampf(bubble.position.x, -inset, size.x - cw - inset)


func show_score_bubble(global_pos: Vector2, gain: int, clamped_x: float = -1.0) -> void:
	var bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(bubble)

	bubble.get_node("HBox").modulate.a = 0.0
	bubble.set_score(gain)
	var local_pos: Vector2 = global_pos - global_position
	var center_x: float = clamped_x if clamped_x >= 0.0 else local_pos.x
	bubble.position = Vector2(
		center_x - bubble.size.x * 0.5, local_pos.y - get_score_bubble_y_offset()
	)
	_clamp_bubble_x(bubble)
	var anim: AnimationPlayer = bubble.get_node("AnimationPlayer")
	anim.play("Appear")
	anim.animation_finished.connect(
		func(_name: StringName) -> void:
			if is_instance_valid(bubble):
				bubble.queue_free()
	)


func show_full_mark_text(cell_global_pos: Vector2, is_perfect: bool) -> void:
	var text_node: FullMarkText = FULL_MARK_TEXT_SCENE.instantiate()
	add_child(text_node)
	var local_pos: Vector2 = cell_global_pos - global_position
	var base_y: float = local_pos.y + get_full_mark_text_y_offset()
	text_node.position.y = base_y

	text_node.play(is_perfect, ABTestManager.combo_text.uses_japanese_text())
	_register_text_line(text_node, base_y, local_pos)


@export var cat_toast_texts: CatToastTextPool = null

const CAT_TOAST_LINE_GAP: float = 4.0

var _text_lines: Array[Control] = []


func _register_text_line(node: Control, base_y: float, source_pos: Vector2) -> void:
	_text_lines = _text_lines.filter(_is_live_line)
	node.set_meta(&"feedback_source_pos", source_pos)
	node.set_meta(&"feedback_base_y", base_y)

	var insert_index: int = _line_insert_index(node, source_pos)
	_text_lines.insert(insert_index, node)

	node.tree_exited.connect(_on_text_line_gone.bind(node), CONNECT_ONE_SHOT)
	_relayout_text_lines(source_pos)

	_realign_text_lines_x(source_pos)
	_retract_clear_when_crowded()


func _retract_clear_when_crowded() -> void:
	var has_perfect: bool = false
	var has_bottom_row: bool = false
	var clears: Array[FullMarkText] = []
	for line: Control in _text_lines:
		if not _is_live_line(line):
			continue
		if _is_bottom_row_line(line):
			has_bottom_row = true
		elif line is FullMarkText:
			var full_mark: FullMarkText = line as FullMarkText
			if full_mark.is_perfect():
				has_perfect = true
			elif full_mark.is_clear():
				clears.append(full_mark)
	if not (has_perfect and has_bottom_row):
		return
	var regroup_sources: Array[Vector2] = []
	for clear_text: FullMarkText in clears:
		clear_text.retract()
		_text_lines.erase(clear_text)
		var clear_source: Vector2 = clear_text.get_meta(&"feedback_source_pos", Vector2(-1.0, -1.0))
		if not regroup_sources.has(clear_source):
			regroup_sources.append(clear_source)
	for source_pos: Vector2 in regroup_sources:
		_relayout_text_lines(source_pos)
		_realign_text_lines_x(source_pos)


func _line_insert_index(node: Control, source_pos: Vector2) -> int:
	var rank: int = _line_rank(node)
	for i in _text_lines.size():
		var line: Control = _text_lines[i]
		var line_source_pos: Vector2 = line.get_meta(&"feedback_source_pos", Vector2(-1.0, -1.0))
		if line_source_pos.is_equal_approx(source_pos) and _line_rank(line) > rank:
			return i
	return _text_lines.size()


func _line_rank(node: Control) -> int:
	if node is FullMarkText:
		return 0
	if node is NearDeathText:
		return 2
	if node is GoodEyeText:
		return 3
	return 1


const SAME_ROW_INK_GAP: float = 10.0


func _shares_row(left: Control, right: Control) -> bool:
	return _is_bottom_row_line(left) and _is_bottom_row_line(right)


func _is_bottom_row_line(node: Control) -> bool:
	return node is NearDeathText or node is GoodEyeText


func _rows_for(source_pos: Vector2) -> Array[Array]:
	var rows: Array[Array] = []
	for node: Control in _text_lines:
		if not _is_live_line(node):
			continue
		var node_source_pos: Vector2 = node.get_meta(&"feedback_source_pos", Vector2(-1.0, -1.0))
		if not node_source_pos.is_equal_approx(source_pos):
			continue
		if not rows.is_empty():
			var last_row: Array = rows[rows.size() - 1]
			if _shares_row(last_row[last_row.size() - 1], node):
				last_row.append(node)
				continue
		rows.append([node])
	return rows


func _relayout_text_lines(source_pos: Vector2) -> void:
	var rows: Array[Array] = _rows_for(source_pos)
	if rows.is_empty():
		return
	var first_line: Control = rows[0][0]
	var next_y: float = float(first_line.get_meta(&"feedback_base_y", 0.0))
	for i: int in rows.size():
		var row: Array = rows[i]
		var row_bottom: float = next_y
		for node: Control in row:
			node.position.y = next_y if i == 0 else next_y - _content_top_inset_of(node)
			row_bottom = maxf(row_bottom, node.position.y + _content_bottom_of(node))
		next_y = row_bottom + CAT_TOAST_LINE_GAP


func _realign_text_lines_x(source_pos: Vector2) -> void:
	_text_lines = _text_lines.filter(_is_live_line)
	var rows: Array[Array] = _rows_for(source_pos)
	for row: Array in rows:
		if row.size() == 1:
			_position_text_line_x(row[0], source_pos)
		else:
			_position_shared_row_x(row, source_pos)
	_align_group_to_edge(rows)


func _position_shared_row_x(row: Array, source_pos: Vector2) -> void:
	var center_x: float = source_pos.x
	if (
		_share_center_with_text
		and _last_clamped_center_x >= 0.0
		and _last_clamped_source_pos.is_equal_approx(source_pos)
	):
		center_x = _last_clamped_center_x
	var ink_width: float = SAME_ROW_INK_GAP * float(row.size() - 1)
	for node: Control in row:
		var side: Vector2 = _content_side_inset_of(node)
		ink_width += node.size.x - side.x - side.y
	var bounds: Vector2 = _text_align_bounds()
	var ink_left: float = clampf(
		center_x - ink_width * 0.5, bounds.x, maxf(bounds.y - ink_width, bounds.x)
	)
	for node: Control in row:
		var side: Vector2 = _content_side_inset_of(node)
		node.position.x = ink_left - side.x
		ink_left += node.size.x - side.x - side.y + SAME_ROW_INK_GAP


func _align_group_to_edge(rows: Array[Array]) -> void:
	if rows.size() < 2:
		return
	var has_shared_row: bool = false
	for row: Array in rows:
		if row.size() > 1 or _is_bottom_row_line(row[0]):
			has_shared_row = true
	if not has_shared_row:
		return
	var bounds: Vector2 = _text_align_bounds()
	var touches_left: bool = false
	var touches_right: bool = false
	for row: Array in rows:
		var first: Control = row[0]
		var last: Control = row[row.size() - 1]
		if _ink_left_of(first) <= bounds.x + _EDGE_EPSILON:
			touches_left = true
		if _ink_right_of(last) >= bounds.y - _EDGE_EPSILON:
			touches_right = true
	if touches_left == touches_right:
		return
	for row: Array in rows:
		var shift: float = (
			bounds.x - _ink_left_of(row[0])
			if touches_left
			else bounds.y - _ink_right_of(row[row.size() - 1])
		)
		for node: Control in row:
			node.position.x += shift


const _EDGE_EPSILON: float = 0.5


func _text_align_bounds() -> Vector2:
	if _board_view == null or not (_board_view is BoardView):
		return Vector2(0.0, size.x)
	var board: BoardView = _board_view as BoardView
	var bg_rect: Rect2 = board.get_board_background_rect_local()
	var to_self: Transform2D = (
		get_global_transform().affine_inverse() * board.get_global_transform()
	)
	var left: float = (to_self * bg_rect.position).x
	var right: float = (to_self * bg_rect.end).x
	return Vector2(minf(left, right), maxf(left, right))


func _ink_left_of(node: Control) -> float:
	return node.position.x + _content_side_inset_of(node).x


func _ink_right_of(node: Control) -> float:
	return node.position.x + node.size.x - _content_side_inset_of(node).y


func _content_side_inset_of(node: Control) -> Vector2:
	if node.has_method("get_content_side_inset"):
		return node.get_content_side_inset()
	return Vector2.ZERO


func _position_text_line_x(node: Control, source_pos: Vector2) -> void:
	var center_x: float = source_pos.x
	if (
		_share_center_with_text
		and _last_clamped_center_x >= 0.0
		and _last_clamped_source_pos.is_equal_approx(source_pos)
	):
		center_x = _last_clamped_center_x
	node.position.x = center_x - node.size.x * 0.5
	_clamp_bubble_x(node)


func _on_text_line_gone(node: Control) -> void:
	_text_lines.erase(node)


func _is_live_line(node: Control) -> bool:
	return node != null and is_instance_valid(node)


func _content_bottom_of(node: Control) -> float:
	if node.has_method("get_content_bottom_offset"):
		return node.get_content_bottom_offset()
	return node.size.y


func _content_top_inset_of(node: Control) -> float:
	if node.has_method("get_content_top_inset"):
		return node.get_content_top_inset()
	return 0.0


func show_cat_toast_text(cell_global_pos: Vector2, group: int, scene: int) -> void:
	if cat_toast_texts == null:
		push_error("ComboFeedbackView: cat_toast_texts 未绑定,cat_toast 文案无法显示")
		return
	var texture: Texture2D = cat_toast_texts.pick(group, scene)
	if texture == null:
		push_error("ComboFeedbackView: cat_toast 贴图缺失 group=%d scene=%d(池子没配齐)" % [group, scene])
		return
	var text_node: CatToastText = CAT_TOAST_TEXT_SCENE.instantiate()
	add_child(text_node)
	text_node.play(texture)
	var local_pos: Vector2 = cell_global_pos - global_position
	var base_y: float = local_pos.y + get_full_mark_text_y_offset()
	text_node.position.y = base_y
	_register_text_line(text_node, base_y, local_pos)


func show_near_death_text(cell_global_pos: Vector2) -> void:
	var text_node: NearDeathText = NEAR_DEATH_TEXT_SCENE.instantiate()
	add_child(text_node)
	text_node.play(ABTestManager.combo_text.uses_japanese_text())
	var local_pos: Vector2 = cell_global_pos - global_position
	var base_y: float = local_pos.y + get_full_mark_text_y_offset()
	text_node.position.y = base_y
	_register_text_line(text_node, base_y, local_pos)


func show_good_eye_text(cell_global_pos: Vector2) -> void:
	var text_node: GoodEyeText = GOOD_EYE_TEXT_SCENE.instantiate()
	add_child(text_node)
	text_node.play(ABTestManager.combo_text.uses_japanese_text())
	var local_pos: Vector2 = cell_global_pos - global_position
	var base_y: float = local_pos.y + get_full_mark_text_y_offset()
	text_node.position.y = base_y
	_register_text_line(text_node, base_y, local_pos)


func get_full_mark_text_y_offset() -> float:
	var board_scale: float = _board_view.scale.x if _board_view != null else 1.0
	return CAT_TOP_UNSCALED * board_scale + BUBBLE_GAP


func set_inserted_level(on: bool) -> void:
	_is_inserted_level = on


func set_level_value(level_num: int) -> void:
	_level_value_num = level_num


func set_super_hard(on: bool) -> void:
	_is_super_hard = on


## 设置是否困难（影响分数板布局）
func set_hard(is_hard: bool) -> void:
	_is_hard = is_hard
	_update_display_visibility()


func refresh_display_visibility() -> void:
	_update_display_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_display_visibility()


func _update_display_visibility() -> void:
	if _score_display != null:
		_score_display.visible = true
	if _level_label != null:
		_level_label.visible = false

	if _level_display != null:
		_level_display.visible = not _is_inserted_level

	var top_ui: NormalTopUiConfig = ABTestManager.normal_top_ui

	var hard_stacked: bool = _is_hard and not _is_inserted_level
	var show_hard_tag: bool = hard_stacked and top_ui.shows_hard_tag()
	if _hard_tag != null:
		_hard_tag.visible = show_hard_tag

	if _hard_tag_lbl != null:
		_hard_tag_lbl.text = "GAME_SUPER_HARD_TAG" if _is_super_hard else "GAME_HARD_TAG"

	var three_cols: bool = show_hard_tag
	if _level_display != null:
		_level_display.offset_left = 220.0 if three_cols else 274.0
		_level_display.offset_right = 420.0 if three_cols else 530.0

	if _score_display != null:
		if _is_inserted_level:
			_score_display.anchor_left = 0.5
			_score_display.anchor_right = 0.5
			_score_display.offset_left = -100.0
			_score_display.offset_right = 100.0
		else:
			_score_display.anchor_left = 1.0
			_score_display.anchor_right = 1.0
			_score_display.offset_left = -615.0 if three_cols else -502.0
			_score_display.offset_right = -465.0 if three_cols else -302.0

	_apply_hard_tag_layout(top_ui.is_swap_fire())
	_apply_level_title(hard_stacked, top_ui)


const _HARD_TAG_LBL_OVERFLOW: float = 110.0

const _HARD_TAG_SUPER_FONT_DELTA: int = 10


func _apply_hard_tag_layout(swap: bool) -> void:
	if _hard_tag_icon == null or _hard_tag_lbl == null:
		return

	if swap:
		if _level_title_label != null:
			var title_font: Font = _level_title_label.get_theme_font("font")
			if title_font != null:
				_hard_tag_lbl.add_theme_font_override("font", title_font)
		_hard_tag_lbl.add_theme_font_size_override("font_size", _hard_tag_font_size(50))
		_hard_tag_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_hard_tag_lbl.offset_top = 3.0
		_hard_tag_lbl.offset_bottom = 76.0
		_apply_hard_tag_lbl_overflow()

		_hard_tag_icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hard_tag_icon.offset_left = -22.0
		_hard_tag_icon.offset_right = 22.0
		_hard_tag_icon.offset_top = 76.0
		_hard_tag_icon.offset_bottom = 124.0
	else:
		if _level_value_label != null:
			var value_font: Font = _level_value_label.get_theme_font("font")
			if value_font != null:
				_hard_tag_lbl.add_theme_font_override("font", value_font)
		_hard_tag_lbl.add_theme_font_size_override("font_size", _hard_tag_font_size(58))
		_hard_tag_icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hard_tag_icon.offset_left = -22.0
		_hard_tag_icon.offset_right = 22.0
		_hard_tag_icon.offset_top = 14.0
		_hard_tag_icon.offset_bottom = 62.0
		_hard_tag_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_hard_tag_lbl.offset_top = -60.0
		_hard_tag_lbl.offset_bottom = 0.0
		_apply_hard_tag_lbl_overflow()


func _apply_hard_tag_lbl_overflow() -> void:
	_hard_tag_lbl.offset_left = -_HARD_TAG_LBL_OVERFLOW
	_hard_tag_lbl.offset_right = _HARD_TAG_LBL_OVERFLOW


func _hard_tag_font_size(base: int) -> int:
	return base - _HARD_TAG_SUPER_FONT_DELTA if _is_super_hard else base


func _apply_level_title(hard_stacked: bool, top_ui: NormalTopUiConfig) -> void:
	var fire_prefix: bool = hard_stacked and top_ui.is_fire_prefix()

	var shift: float = (_LEVEL_FIRE_ICON_W + _LEVEL_FIRE_GAP) if fire_prefix else 0.0

	if _level_title_label != null:
		if hard_stacked and top_ui.is_merge_level():
			_level_title_label.text = (
				"GAME_SUPER_HARD_TAG" if _is_super_hard else "GAME_HEADER_HARD_LEVEL"
			)
		else:
			_level_title_label.text = "GAME_HEADER_LEVEL"
		_level_title_label.offset_left = shift
	if _level_value_label != null:
		if _level_value_num >= 0:
			_level_value_label.text = "%d" % _level_value_num
		_level_value_label.offset_left = 0.0
	if _level_fire != null:
		_level_fire.visible = fire_prefix
		if fire_prefix:
			_align_level_fire()


const _LEVEL_DISPLAY_TWO_COL_WIDTH: float = 256.0
const _LEVEL_FIRE_ICON_W: float = 40.0
const _LEVEL_FIRE_GAP: float = 6.0


func _align_level_fire() -> void:
	if _level_fire == null or _level_title_label == null:
		return

	var afl := _level_title_label as AutoFitLabel
	if afl != null:
		afl.refit()
	var font: Font = _level_title_label.get_theme_font("font")
	var fs: int = _level_title_label.get_theme_font_size("font_size")

	var text_w: float = (
		font
		. get_string_size(
			_level_title_label.atr(_level_title_label.text), HORIZONTAL_ALIGNMENT_CENTER, -1, fs
		)
		. x
	)

	var text_center: float = (
		_LEVEL_DISPLAY_TWO_COL_WIDTH * 0.5 + (_LEVEL_FIRE_ICON_W + _LEVEL_FIRE_GAP) * 0.5
	)
	var text_left: float = text_center - text_w * 0.5
	_level_fire.offset_right = text_left - _LEVEL_FIRE_GAP
	_level_fire.offset_left = _level_fire.offset_right - _LEVEL_FIRE_ICON_W

	_level_fire.offset_top = 18.0
	_level_fire.offset_bottom = 60.0


## 设置关卡号
func set_level(level_num: int) -> void:
	if _level_value_label != null:
		_level_value_label.text = "%d" % level_num


func _set_score_text_immediate(value: int) -> void:
	RollingNumber.kill_existing(_score_value_label)
	if _score_value_label != null:
		_score_value_label.text = "%d" % value
	_layout_score_fx_by_digits(value)


func _update_score_label(total_score: int) -> void:
	if _score_value_label != null:
		RollingNumber.roll(_score_value_label, _displayed_score, total_score, 0.35)
	_displayed_score = total_score

	_layout_score_fx_by_digits(total_score)


func update_se_score(total: int) -> void:
	if _score_value_label != null:
		RollingNumber.roll(_score_value_label, _displayed_score, total, 0.35)
	_displayed_score = total
	_layout_score_fx_by_digits(total)


const _STAGE_COLORS: Dictionary = {
	3: [Color("#4B9DFA"), Color("#F17E11"), Color("#DC2DE5")],
	5: [Color("#5FB960"), Color("#4B9DFA"), Color("#F17E11"), Color("#ED595B"), Color("#DC2DE5")],
}

const _SCORE_EFFECT_SCENE: PackedScene = preload("res://assets/prefab/score_effect.tscn")

const _STAGE_EFFECT_INDEX: Dictionary = {
	3: [2, 3, 5],
	5: [1, 2, 3, 4, 5],
}

const _PARTICLE_X_NEAR_4DIGIT: float = 65.0
const _PARTICLE_X_FAR_4DIGIT: float = 85.0
const _PARTICLE_X_PER_DIGIT: float = 15.0

const _FAR_PARTICLE_PREFIX: String = "ShineStar"

var _score_fx_root: Control = null

var _score_fx_digits: int = -1

var _score_base_color: Color = Color.WHITE

var _score_stage: int = 0
var _score_stage_count: int = 0

var _pending_stage: int = -1
var _pending_stage_count: int = 0


func apply_score_stage(stage: int, stage_count: int) -> void:
	if _score_value_label == null:
		return
	_clear_pending_score_stage()
	if _score_stage == stage and _score_stage_count == stage_count:
		return
	if stage <= 0:
		_score_stage = stage
		_score_stage_count = stage_count
		_score_value_label.add_theme_color_override("font_color", _score_base_color)
		_apply_score_stage_effect(0, 0)
		return
	var colors: Array = _STAGE_COLORS.get(stage_count, [])
	if stage > colors.size():
		_score_stage = stage
		_score_stage_count = stage_count
		push_error(
			(
				"ComboFeedbackView: score_performance 档位越界 stage=%d stage_count=%d"
				% [stage, stage_count]
			)
		)
		return
	_score_stage = stage
	_score_stage_count = stage_count
	_score_value_label.add_theme_color_override("font_color", colors[stage - 1])
	_apply_score_stage_effect(stage, stage_count)


func get_applied_score_stage() -> int:
	return _score_stage


func latch_score_stage(stage: int, stage_count: int) -> void:
	_pending_stage = stage
	_pending_stage_count = stage_count


func _flush_pending_score_stage() -> void:
	if _pending_stage < 0:
		return
	var stage: int = _pending_stage
	var stage_count: int = _pending_stage_count
	_clear_pending_score_stage()
	apply_score_stage(stage, stage_count)


func _clear_pending_score_stage() -> void:
	_pending_stage = -1
	_pending_stage_count = 0


func _apply_score_stage_effect(stage: int, stage_count: int) -> void:
	if stage <= 0:
		if _score_fx_root != null:
			_set_active_effect(0)
		return
	_ensure_score_fx()
	if _score_fx_root == null:
		return
	var indices: Array = _STAGE_EFFECT_INDEX.get(stage_count, [])
	if stage > indices.size():
		push_error(
			(
				"ComboFeedbackView: score_performance 特效档位越界 stage=%d stage_count=%d"
				% [stage, stage_count]
			)
		)
		_set_active_effect(0)
		return

	_layout_score_fx_by_digits(_displayed_score)
	_set_active_effect(int(indices[stage - 1]))


func _ensure_score_fx() -> void:
	if _score_fx_root != null or _score_value_label == null:
		return
	var fx: Control = _SCORE_EFFECT_SCENE.instantiate() as Control
	if fx == null:
		push_error("ComboFeedbackView: score_effect.tscn 根节点不是 Control")
		return
	fx.anchor_left = 0.5
	fx.anchor_top = 0.5
	fx.anchor_right = 0.5
	fx.anchor_bottom = 0.5
	fx.offset_left = 0.0
	fx.offset_top = 0.0
	fx.offset_right = 0.0
	fx.offset_bottom = 0.0
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(1, _STAGE_EFFECT_INDEX[5].size() + 1):
		var container: Node = fx.get_node_or_null("Effect%d" % i)
		if container is Control:
			_toggle_effect_container(container as Control, false)

	fx.add_to_group(StaticLayerCache.AMBIENT_GROUP)
	_score_value_label.add_child(fx)
	_score_fx_root = fx

	_score_fx_digits = -1


func _set_active_effect(index: int) -> void:
	if _score_fx_root == null:
		return
	for i in range(1, _STAGE_EFFECT_INDEX[5].size() + 1):
		var container: Node = _score_fx_root.get_node_or_null("Effect%d" % i)
		if container is Control:
			_toggle_effect_container(container as Control, i == index)


func _toggle_effect_container(container: Control, on: bool) -> void:
	container.visible = on
	for child in container.get_children():
		if child is CPUParticles2D:
			(child as CPUParticles2D).emitting = on


func _layout_score_fx_by_digits(score: int) -> void:
	if _score_fx_root == null:
		return
	var digits: int = str(absi(score)).length()
	if digits == _score_fx_digits:
		return
	_score_fx_digits = digits
	var shift: float = _PARTICLE_X_PER_DIGIT * float(digits - 4)
	var near_x: float = _PARTICLE_X_NEAR_4DIGIT + shift
	var far_x: float = _PARTICLE_X_FAR_4DIGIT + shift
	for i in range(1, _STAGE_EFFECT_INDEX[5].size() + 1):
		var container: Node = _score_fx_root.get_node_or_null("Effect%d" % i)
		if container == null:
			continue
		for child: Node in container.get_children():
			if not (child is CPUParticles2D):
				continue
			var particle: CPUParticles2D = child

			var base_name: String = String(particle.name).trim_suffix(str(i))
			if base_name.is_empty():
				continue
			var is_left: bool = base_name.right(1) == "L"
			var target_x: float = far_x if base_name.begins_with(_FAR_PARTICLE_PREFIX) else near_x
			particle.position.x = -target_x if is_left else target_x


func show_se_bubble(cell_global_pos: Vector2, params: Dictionary) -> Control:
	var gain: int = params.get("gain", 0)
	var local_pos: Vector2 = cell_global_pos - global_position

	var like_hand_hw: float = float(params.get("like_hand_hw", 0.0))
	var half_widths: Array[float] = _collect_se_half_widths(gain, like_hand_hw)
	var cx: float = compute_clamped_center_x(local_pos, half_widths, like_hand_hw > 0.0)

	var score_bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(score_bubble)
	score_bubble.set_score(gain)

	var top_y: float = local_pos.y - get_score_bubble_y_offset()
	score_bubble.position = Vector2(cx - score_bubble.size.x * 0.5, top_y)
	_clamp_bubble_x(score_bubble)

	var score_anim: AnimationPlayer = score_bubble.get_node("AnimationPlayer")
	score_anim.play("Appear")
	score_anim.animation_finished.connect(
		func(_n: StringName) -> void:
			if is_instance_valid(score_bubble):
				score_bubble.queue_free(),
		CONNECT_ONE_SHOT
	)
	return score_bubble


func get_se_fly_delay() -> float:
	return _SE_FLY_DELAY


static func _cubic_bezier_ease(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	var cx := 3.0 * x1
	var bx := 3.0 * (x2 - x1) - cx
	var ax := 1.0 - cx - bx
	var cy := 3.0 * y1
	var by := 3.0 * (y2 - y1) - cy
	var ay := 1.0 - cy - by
	var guess := t
	for _i in 8:
		var x_val := ((ax * guess + bx) * guess + cx) * guess
		var dx := (3.0 * ax * guess + 2.0 * bx) * guess + cx
		if absf(dx) < 1e-07:
			break
		guess -= (x_val - t) / dx
	return ((ay * guess + by) * guess + cy) * guess


func _se_fly_pos(t: float, from: Vector2, to: Vector2) -> Vector2:
	var px := _cubic_bezier_ease(t, 0.2, 0.0, 0.8, 1.0)
	var py := _cubic_bezier_ease(t, 0.5, -0.343, 1.0, 1.0)
	return Vector2(lerpf(from.x, to.x, px), lerpf(from.y, to.y, py))


func _get_effect_host() -> Node:
	return get_parent().get_parent()


func play_se_fly_effect(from_global_pos: Vector2, final_gain: int, se_score: int) -> void:
	if _score_value_label == null:
		return
	var to_pos: Vector2 = _score_value_label.global_position + _score_value_label.size * 0.5
	var trail: Node = _SE_TRAIL_SCENE.instantiate()
	_get_effect_host().add_child(trail)
	trail.z_index = _SE_TRAIL_Z
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return
	sprite.global_position = from_global_pos
	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from_global_pos
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false
	var particles_to_move: Array[CPUParticles2D] = []
	for child in sprite.get_children():
		if child is CPUParticles2D:
			particles_to_move.append(child as CPUParticles2D)
	for p in particles_to_move:
		sprite.remove_child(p)
		fly_target.add_child(p)
		p.visible = true
		p.emitting = true
	var from := from_global_pos

	var tw: Tween = trail.create_tween()
	tw.tween_method(
		func(t: float) -> void:
			if is_instance_valid(fly_target):
				fly_target.global_position = _se_fly_pos(t, from, to_pos)
				sprite.notify_target_moved(),
		0.0,
		1.0,
		_SE_FLY_DURATION
	)
	tw.tween_callback(_on_se_trail_arrived.bind(trail, to_pos, se_score, _reset_generation))


func _on_se_trail_arrived(trail: Node, pos: Vector2, se_score: int, gen: int) -> void:
	if gen != _reset_generation:
		if is_instance_valid(trail):
			trail.queue_free()
		return
	if is_instance_valid(trail):
		var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
		if sprite != null:
			for child in sprite.get_children():
				if child is CPUParticles2D:
					(child as CPUParticles2D).emitting = false
		var fly_target: Node = trail.get_node_or_null("ScoreTrail/FlyTarget")
		if fly_target == null:
			fly_target = trail.find_child("FlyTarget", true, false)
		if fly_target != null:
			for child in fly_target.get_children():
				if child is CPUParticles2D:
					(child as CPUParticles2D).emitting = false
					(child as CPUParticles2D).visible = false

		var trail_tw: Tween = trail.create_tween()
		trail_tw.tween_interval(_SE_TRAIL_LINGER)
		trail_tw.tween_callback(trail.queue_free)
	var burst: Node = _SE_BURST_SCENE.instantiate()
	_get_effect_host().add_child(burst)
	burst.z_index = _SE_TRAIL_Z
	burst.global_position = pos
	for child_name: String in ["GlowAlp", "StarAlp", "StarAdd"]:
		var p: Node = burst.get_node_or_null(child_name)
		if p != null and p is CPUParticles2D:
			(p as CPUParticles2D).emitting = true

	_flush_pending_score_stage()

	var burst_tw: Tween = burst.create_tween()
	burst_tw.tween_interval(1.5)
	burst_tw.tween_callback(burst.queue_free)

	if se_score > _displayed_score:
		update_se_score(se_score)
		_play_se_score_bar_bounce()


func _play_se_score_bar_bounce() -> void:
	if _score_value_label == null:
		return
	_score_value_label.pivot_offset = _score_value_label.size * 0.5
	var tw: Tween = create_tween()
	(
		tw
		. tween_method(_apply_se_bounce_scale, 1.0, _SE_BOUNCE_SCALE, _SE_BOUNCE_UP_DURATION)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		tw
		. tween_method(_apply_se_bounce_scale, _SE_BOUNCE_SCALE, 1.0, _SE_BOUNCE_DOWN_DURATION)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)


func _apply_se_bounce_scale(factor: float) -> void:
	if _score_value_label == null:
		return
	_score_value_label.scale = Vector2(factor, factor)
	if _score_fx_root != null and factor > 0.0:
		var inverse: float = 1.0 / factor
		_score_fx_root.scale = Vector2(inverse, inverse)


func get_current_effects_height() -> float:
	return BUBBLE_HEIGHT
