## 陪伴猫动画视图：驱动交互状态机、Spine 动画与食物飞行，把罐头库存判定交给面板。
extends Control

const Interaction: GDScript = preload(
	"res://scripts/module/home/core/home_companion_interaction.gd"
)

const HOME_ENTRY_HUNGER_GRACE_SECONDS: float = 10.0
const ENTRY_UI_DELAY_SECONDS: float = 0.6667
const ENTRY_SPEECH_DELAY_SECONDS: float = 1.3333
const ENTRY_FOOD_DELAY_SECONDS: float = 1.3333
const FEED_COOLDOWN_SECONDS: float = 0.3

static var _active_sound_kind: int = -1
static var _active_sound_owner: int = 0

signal state_changed(state: int)
signal feeding_requested
signal feeding_started
signal feeding_completed
signal entry_ui_revealed
signal entry_speech_revealed

@export var cat_sprite: SpineSprite
@export var cat_button: Button
@export var food_button: Button
@export var food_icon: TextureRect
@export var food_count_label: Label
@export var satiety_bar: ProgressBar
@export var candy_texture: Texture2D
@export var can_texture: Texture2D
@export var entrance_clip: String = "appear"
@export var normal_idle_clip: String = "idle"
@export var hungry_idle_clip: String = "idle_hungry"
@export var touch_clip: String = "touch"
@export var feed_clip: String = "feed"
@export var default_skin: String = "default"
@export var candy_skin: String = "halloween"
@export_range(0.01, 10.0) var normal_idle_seconds: float = 5.0

@export var food_fly_layer: Control

@export var food_fly_mouth_bone: String = "fadai51"

@export var food_drop_end_offset_y: float = 30.0

@export var food_drop_height: float = 200.0

@export var food_drop_curve: Curve

@export_range(0.05, 2.0) var food_drop_seconds: float = 0.25

@export_range(0.0, 2.0) var food_drop_shrink_start_seconds: float = 0.2

@export_range(0.0, 2.0) var food_drop_fade_start_seconds: float = 0.2

var _interaction: Interaction = Interaction.new()
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _food_count: int = 0
var _food_unlocked: bool = true
var _satiety: float = 60.0
var _satiety_enabled: bool = true
var _input_enabled: bool = true
var _sound_enabled: bool = true
var _clip_generation: int = 0
var _clip: String = ""
var _track: SpineTrackEntry

var _feed_queued: bool = false
var _feed_cooldown: Tween
var _assets_valid: bool = false
var _tutorial_preview: bool = false
var _tutorial_hungry: bool = false
var _satiety_fill: StyleBoxFlat
var _satiety_normal_color: Color
var _satiety_tween: Tween
var _satiety_display_initialized: bool = false
var _satiety_display_target: float = 60.0
var _accessory_center_x: float = NAN

@onready var _satiety_background: Control = (
	satiety_bar.get_node("Background") if satiety_bar != null else null
)

@onready var _satiety_entry_animation: AnimationPlayer = (
	satiety_bar.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if satiety_bar != null
	else null
)

var _entry_hunger_guard: Tween
var _entry_ui_delay: Tween
var _entry_ui_ready: bool = false
var _entry_speech_delay: Tween
var _entry_speech_ready: bool = false
var _entry_food_delay: Tween
var _entry_food_ready: bool = false
var _entry_food_deferred: bool = false
var _entry_animated: bool = false
var _food_entry_played: bool = false
var _satiety_entry_played: bool = false

var _food_flyers: Array[TextureRect] = []
var _food_fly_tweens: Array[Tween] = []


func _ready() -> void:
	_random.randomize()
	_assets_valid = _validate_assets()
	if food_button != null:
		food_button.entry_animation_finished.connect(_refresh_controls)
	if satiety_bar != null:
		_satiety_fill = satiety_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
		if _satiety_fill != null:
			_satiety_normal_color = _satiety_fill.bg_color
			satiety_bar.add_theme_stylebox_override("fill", _satiety_fill)
	_refresh_controls()


func begin_home_entry(
	mode: Interaction.Mode,
	food_count: int = 0,
	satiety: float = 60.0,
	satiety_enabled: bool = true,
	play_entrance: bool = true,
	food_unlocked: bool = true,
	tutorial_entrance: bool = false
) -> void:
	end_home_entry()
	if not _assets_valid:
		return
	_food_count = maxi(0, food_count)
	_food_unlocked = food_unlocked
	_satiety = clampf(satiety, 0.0, 100.0)
	_satiety_enabled = satiety_enabled
	_input_enabled = true
	_interaction.begin_entry(mode)
	visible = mode != Interaction.Mode.NONE
	if mode == Interaction.Mode.NONE:
		return
	_entry_animated = play_entrance
	_entry_food_deferred = tutorial_entrance
	if _interaction.is_unlimited_food() or mode == Interaction.Mode.CANS:
		_entry_hunger_guard = create_tween()
		_entry_hunger_guard.tween_interval(HOME_ENTRY_HUNGER_GRACE_SECONDS)
	var skin_name: String = (
		candy_skin
		if mode == Interaction.Mode.CANDY or mode == Interaction.Mode.COSMETIC
		else default_skin
	)
	cat_sprite.get_skeleton().set_skin_by_name(skin_name)
	if play_entrance:
		_play(entrance_clip)
		_entry_ui_delay = create_tween()
		_entry_ui_delay.tween_interval(ENTRY_UI_DELAY_SECONDS)
		_entry_ui_delay.tween_callback(_reveal_entry_ui)
		_entry_speech_delay = create_tween()
		_entry_speech_delay.tween_interval(ENTRY_SPEECH_DELAY_SECONDS)
		_entry_speech_delay.tween_callback(_reveal_entry_speech)
		if not _entry_food_deferred:
			_entry_food_delay = create_tween()
			_entry_food_delay.tween_interval(ENTRY_FOOD_DELAY_SECONDS)
			_entry_food_delay.tween_callback(_reveal_entry_food)
	else:
		_enter_idle()
		_reveal_entry_ui()
		_reveal_entry_speech()
		if not _entry_food_deferred:
			_reveal_entry_food()


func end_home_entry() -> void:
	_stop_clip_sound()
	_stop_food_flights()
	if _feed_cooldown != null:
		_feed_cooldown.kill()
		_feed_cooldown = null
	if _entry_ui_delay != null:
		_entry_ui_delay.kill()
		_entry_ui_delay = null
	_entry_ui_ready = false
	if _entry_speech_delay != null:
		_entry_speech_delay.kill()
		_entry_speech_delay = null
	_entry_speech_ready = false
	if _entry_food_delay != null:
		_entry_food_delay.kill()
		_entry_food_delay = null
	_entry_food_ready = false
	_entry_food_deferred = false
	_entry_animated = false
	_food_entry_played = false
	_satiety_entry_played = false
	if is_node_ready() and food_button != null:
		food_button.reset_entry_animation()
	if is_node_ready() and satiety_bar != null:
		if _satiety_entry_animation != null:
			_satiety_entry_animation.play(&"RESET")
			_satiety_entry_animation.advance(0.0)
			_satiety_entry_animation.stop()
		satiety_bar.modulate = Color.WHITE
	if _entry_hunger_guard != null:
		_entry_hunger_guard.kill()
		_entry_hunger_guard = null
	_tutorial_preview = false
	_tutorial_hungry = false
	_feed_queued = false
	if _satiety_tween != null:
		_satiety_tween.kill()
	_satiety_display_initialized = false
	_clip_generation += 1
	_track = null
	_clip = ""
	_interaction.end_entry()
	if is_instance_valid(cat_sprite):
		cat_sprite.get_animation_state().clear_tracks()
	if is_node_ready():
		_refresh_controls()
		state_changed.emit(_interaction.state)
	visible = false


func is_entry_ui_ready() -> bool:
	return _entry_ui_ready


func is_entry_animated() -> bool:
	return _entry_animated


func is_entry_speech_ready() -> bool:
	return _entry_speech_ready


func _reveal_entry_speech() -> void:
	_entry_speech_delay = null
	if _interaction.state == Interaction.State.HIDDEN:
		return
	_entry_speech_ready = true
	entry_speech_revealed.emit()


func _reveal_entry_food() -> void:
	_entry_food_delay = null
	if _interaction.state == Interaction.State.HIDDEN:
		return
	_entry_food_ready = true
	_refresh_controls()


func reveal_tutorial_food(play_animation: bool = true) -> void:
	if not _entry_food_deferred or _interaction.state == Interaction.State.HIDDEN:
		return
	_entry_food_deferred = false
	if not play_animation:
		_food_entry_played = true
	_reveal_entry_food()


func _reveal_entry_ui() -> void:
	_entry_ui_delay = null
	if _interaction.state == Interaction.State.HIDDEN:
		return
	_entry_ui_ready = true
	_refresh_controls()
	entry_ui_revealed.emit()


func begin_tutorial_preview(
	mode: Interaction.Mode, food_count: int = 0, satiety: float = 60.0
) -> void:
	begin_home_entry(mode, food_count, satiety, mode == Interaction.Mode.SATIETY, true, true, true)
	_tutorial_preview = true
	set_interaction_enabled(false)


func show_tutorial_hunger() -> void:
	if not _tutorial_preview or _tutorial_hungry:
		return
	_tutorial_hungry = true
	_enter_tutorial_idle()
	reveal_tutorial_food()


func _enter_tutorial_idle() -> void:
	_interaction.enter_idle(
		1.0 if _tutorial_hungry else 0.0, _satiety if _tutorial_hungry else 100.0
	)
	_play(hungry_idle_clip if _tutorial_hungry else normal_idle_clip)


func resume_after_tutorial() -> void:
	if _interaction.state != Interaction.State.HIDDEN:
		_enter_idle()


func refresh_status(
	food_count: int, satiety: float, satiety_enabled: bool = true, food_unlocked: bool = true
) -> void:
	_food_count = maxi(0, food_count)
	_food_unlocked = food_unlocked
	_satiety = clampf(satiety, 0.0, 100.0)
	_satiety_enabled = satiety_enabled
	if _interaction.mode == Interaction.Mode.SATIETY and _is_idle():
		var should_be_hungry: bool = _satiety_enabled and _satiety <= Interaction.HUNGRY_THRESHOLD
		if should_be_hungry != (_interaction.state == Interaction.State.HUNGRY_IDLE):
			_enter_idle()
	_refresh_controls()


func set_interaction_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_feed_queued = false
	_refresh_controls()


## 确认交互仍在等待状态后播放喂食与食物飞行，启动秒级冷却并发出开始信号。
func confirm_feeding(approved: bool) -> void:
	if _interaction.state != Interaction.State.FEED_PENDING:
		return
	if not _interaction.confirm_feed(approved):
		_enter_idle()
		return
	_play(feed_clip, _clip == feed_clip)
	_play_food_flight()
	_feed_cooldown = create_tween()
	_feed_cooldown.tween_interval(FEED_COOLDOWN_SECONDS)
	feeding_started.emit()


func _play_food_flight() -> void:
	if food_fly_layer == null or not food_icon.is_visible_in_tree():
		return
	if cat_sprite.get_skeleton().find_bone(food_fly_mouth_bone) == null:
		push_error("HomeCompanionCat: missing mouth bone %s" % food_fly_mouth_bone)
		return
	var index: int = _acquire_food_flyer()
	var flyer: TextureRect = _food_flyers[index]
	flyer.texture = food_icon.texture
	flyer.size = food_icon.size
	flyer.pivot_offset = food_icon.size * 0.5
	flyer.modulate = Color.WHITE
	var icon_scale: Vector2 = (
		food_icon.get_global_transform().get_scale()
		/ food_fly_layer.get_global_transform().get_scale()
	)
	_food_fly_tweens[index] = _play_food_drop(flyer, icon_scale)


func _food_mouth_position() -> Vector2:
	var mouth_global: Vector2 = cat_sprite.get_global_bone_transform(food_fly_mouth_bone).origin
	return food_fly_layer.get_global_transform().affine_inverse() * mouth_global


func _play_food_drop(flyer: TextureRect, icon_scale: Vector2) -> Tween:
	_step_food_drop(0.0, flyer, icon_scale)
	flyer.show()
	var tween: Tween = create_tween()
	tween.tween_method(
		_step_food_drop.bind(flyer, icon_scale), 0.0, food_drop_seconds, food_drop_seconds
	)
	tween.tween_callback(flyer.hide)
	return tween


func _step_food_drop(elapsed: float, flyer: TextureRect, icon_scale: Vector2) -> void:
	var drop_progress: float = clampf(elapsed / food_drop_seconds, 0.0, 1.0)
	var fall: float = _food_drop_default_fall(drop_progress)
	if food_drop_curve != null:
		fall = food_drop_curve.sample_baked(drop_progress)
	var shrink_progress: float = _food_drop_phase(
		elapsed, food_drop_shrink_start_seconds, food_drop_seconds
	)
	var fade_progress: float = _food_drop_phase(
		elapsed, food_drop_fade_start_seconds, food_drop_seconds
	)
	flyer.scale = icon_scale * (1.0 - shrink_progress)
	flyer.modulate.a = 1.0 - fade_progress
	var offset := Vector2(0.0, food_drop_end_offset_y - food_drop_height * (1.0 - fall))
	flyer.position = _food_mouth_position() + offset - flyer.pivot_offset


func _food_drop_default_fall(progress: float) -> float:
	var lower: float = 0.0
	var upper: float = 1.0
	for i in 24:
		var middle: float = (lower + upper) * 0.5
		if _cubic_bezier(middle, 0.3, 0.85) < progress:
			lower = middle
		else:
			upper = middle
	return _cubic_bezier((lower + upper) * 0.5, 0.0, 0.85)


func _cubic_bezier(param: float, control_a: float, control_b: float) -> float:
	var inverse: float = 1.0 - param
	return (
		3.0 * inverse * inverse * param * control_a
		+ 3.0 * inverse * param * param * control_b
		+ param * param * param
	)


func _food_drop_phase(elapsed: float, start_seconds: float, end_seconds: float) -> float:
	if end_seconds <= start_seconds:
		return 1.0 if elapsed >= end_seconds else 0.0
	return clampf((elapsed - start_seconds) / (end_seconds - start_seconds), 0.0, 1.0)


func _acquire_food_flyer() -> int:
	for i in _food_flyers.size():
		if not _food_flyers[i].visible:
			return i
	var flyer: TextureRect = food_icon.duplicate(0) as TextureRect
	flyer.hide()
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	food_fly_layer.add_child(flyer)
	_food_flyers.append(flyer)
	_food_fly_tweens.append(null)
	return _food_flyers.size() - 1


func _stop_food_flights() -> void:
	for i in _food_flyers.size():
		if _food_fly_tweens[i] != null:
			_food_fly_tweens[i].kill()
			_food_fly_tweens[i] = null
		if is_instance_valid(_food_flyers[i]):
			_food_flyers[i].hide()


func get_interaction_state() -> int:
	return _interaction.state


func _on_cat_pressed() -> void:
	if not _can_receive_input():
		return
	Tracker.track_btn_click(Tracker.Btn.COMPANION_CAT, self)
	if not _interaction.request_touch():
		return
	_play(touch_clip)


func _on_food_pressed() -> void:
	if not _can_receive_input():
		return
	Tracker.track_btn_click(Tracker.Btn.COMPANION_CAT_FEED, self)
	if _feed_queued or (_feed_cooldown != null and _feed_cooldown.is_running()):
		return
	if _interaction.can_interrupt_feed():
		_feed_queued = _interaction.is_unlimited_food() or _food_count > 0
		_cut_feed()
		return
	if not _interaction.request_feed(_food_count):
		return
	_request_feeding()


## 无限食物直接批准；消耗库存的模式发信号向面板请求，未同步批准就回退。
func _request_feeding() -> void:
	_refresh_controls()
	if _interaction.is_unlimited_food():
		confirm_feeding(true)
	else:
		feeding_requested.emit()
		if _interaction.state == Interaction.State.FEED_PENDING:
			confirm_feeding(false)


func _cut_feed() -> void:
	if _track == null:
		return

	_track.set_time_scale(0.0)
	_finish_clip.call_deferred(_clip_generation)


func _enter_idle() -> void:
	var random_roll: float = _random.randf()
	if _entry_hunger_guard != null and _entry_hunger_guard.is_running():
		random_roll = 0.0
	_interaction.enter_idle(random_roll, _satiety if _satiety_enabled else 100.0)
	var animation_name: String = (
		hungry_idle_clip
		if _interaction.state == Interaction.State.HUNGRY_IDLE
		else normal_idle_clip
	)
	_play(animation_name)


func _play(animation_name: String, continue_feeding: bool = false) -> void:
	_clip_generation += 1
	_play_clip_sound(animation_name, _clip)
	_clip = animation_name
	var skeleton: SpineSkeleton = cat_sprite.get_skeleton()
	var animation_state: SpineAnimationState = cat_sprite.get_animation_state()
	if not continue_feeding:
		animation_state.clear_tracks()
		skeleton.set_to_setup_pose()
	_track = animation_state.set_animation(animation_name, false, 0)
	if continue_feeding:
		_track.set_mix_duration(0.0)
	if animation_name == normal_idle_clip:
		_track.set_time_scale(_track.get_animation().get_duration() / normal_idle_seconds)
	cat_sprite.update_skeleton(0.0)
	_refresh_controls()
	state_changed.emit(_interaction.state)


func _play_clip_sound(animation_name: String, previous_clip: String) -> void:
	if not _sound_enabled:
		return
	var sound_kind: int = -1
	if animation_name == entrance_clip:
		sound_kind = SoundManager.Kind.COMPANION_WAVE
	elif animation_name == touch_clip:
		sound_kind = SoundManager.Kind.COMPANION_SURPRISE
	elif animation_name == feed_clip:
		sound_kind = SoundManager.Kind.COMPANION_EAT
	elif animation_name == normal_idle_clip:
		sound_kind = SoundManager.Kind.COMPANION_IDLE
	elif animation_name == hungry_idle_clip and previous_clip != hungry_idle_clip:
		sound_kind = SoundManager.Kind.COMPANION_HUNGRY
	if sound_kind < 0:
		return
	if _active_sound_kind >= 0:
		SoundManager.stop(_active_sound_kind)
	_active_sound_kind = sound_kind
	_active_sound_owner = get_instance_id()
	SoundManager.play(sound_kind)


func set_sound_enabled(enabled: bool) -> void:
	_sound_enabled = enabled
	if not enabled:
		_stop_clip_sound()


func _stop_clip_sound() -> void:
	if _active_sound_owner != get_instance_id():
		return
	SoundManager.stop(_active_sound_kind)
	_active_sound_kind = -1
	_active_sound_owner = 0


func _exit_tree() -> void:
	_stop_clip_sound()


## 只处理当前片段的完成事件，再延迟提交带代际号的收尾，避免旧动画回调干扰新状态。
func _on_animation_completed(_sprite: Object, _animation_state: Object, entry: Object) -> void:
	var completed_entry: SpineTrackEntry = entry as SpineTrackEntry
	if completed_entry == null or completed_entry.get_animation().get_name() != _clip:
		return

	_finish_clip.call_deferred(_clip_generation)


func _finish_clip(generation: int) -> void:
	if generation != _clip_generation or _interaction.state == Interaction.State.HIDDEN:
		return
	var was_feeding: bool = _interaction.state == Interaction.State.FEED
	if was_feeding:
		_interaction.complete_feed()
		var continue_feeding: bool = _feed_queued and _can_receive_input()
		_feed_queued = false
		if continue_feeding and _interaction.request_next_feed(_food_count):
			_request_feeding()
			feeding_completed.emit()
			return
	if _tutorial_preview:
		_enter_tutorial_idle()
	else:
		_enter_idle()
	if was_feeding:
		feeding_completed.emit()


func _can_receive_input() -> bool:
	return (
		_assets_valid
		and _input_enabled
		and is_visible_in_tree()
		and _interaction.state != Interaction.State.HIDDEN
	)


func _is_idle() -> bool:
	return (
		_interaction.state == Interaction.State.NORMAL_IDLE
		or _interaction.state == Interaction.State.HUNGRY_IDLE
	)


func refresh_accessory_layout(layout_center_x: float = NAN) -> void:
	if not is_inside_tree() or cat_sprite == null:
		return
	if not is_nan(layout_center_x):
		_accessory_center_x = layout_center_x
	var parent_scale: Vector2 = get_global_transform().get_scale()
	var accessory_scale := Vector2(
		1.0 / maxf(absf(parent_scale.x), 0.01), 1.0 / maxf(absf(parent_scale.y), 0.01)
	)
	if satiety_bar != null and satiety_bar.get_parent() == self:
		satiety_bar.scale = accessory_scale
		satiety_bar.global_position = cat_sprite.global_position + Vector2(-169.0, 51.0)
		if not is_nan(_accessory_center_x) and _satiety_background != null:
			satiety_bar.global_position.x += (
				_accessory_center_x - _satiety_background.get_global_rect().get_center().x
			)
	if food_button != null and food_button.get_parent() == self:
		food_button.set_layout_scale(accessory_scale)

		var food_origin: Vector2 = (
			get_global_transform().affine_inverse()
			* (cat_sprite.global_position + Vector2(243.0, -550.0))
		)
		var food_pivot: Vector2 = (
			food_button.pivot_offset + food_button.size * food_button.pivot_offset_ratio
		)
		food_button.position = food_origin + food_pivot * (accessory_scale - Vector2.ONE)


func _refresh_controls() -> void:
	refresh_accessory_layout()
	if (
		cat_button == null
		or food_button == null
		or food_icon == null
		or food_count_label == null
		or satiety_bar == null
	):
		return
	var active: bool = _interaction.state != Interaction.State.HIDDEN
	var candy: bool = _interaction.mode == Interaction.Mode.CANDY
	var unlimited: bool = _interaction.is_unlimited_food()

	var feeding: bool = (
		_interaction.can_interrupt_feed()
		or (_interaction.state == Interaction.State.FEED_PENDING and _clip == feed_clip)
	)
	cat_button.disabled = (
		not _can_receive_input() or _interaction.state != Interaction.State.NORMAL_IDLE
	)
	food_button.visible = (
		active
		and _entry_food_ready
		and _food_unlocked
		and _interaction.mode != Interaction.Mode.COSMETIC
	)
	if _tutorial_preview:
		food_button.visible = (
			_entry_food_ready and _tutorial_hungry and _interaction.mode != Interaction.Mode.CANDY
		)
	if food_button.visible and not _food_entry_played:
		_food_entry_played = true
		if _entry_animated:
			food_button.play_entry_animation()
	food_button.disabled = (
		not _can_receive_input()
		or not (_is_idle() or feeding)
		or food_button.is_entry_animation_playing()
	)
	if not unlimited and _food_count <= 0 and not feeding:
		food_button.disabled = true
	food_icon.texture = candy_texture if candy else can_texture
	food_icon.position = Vector2(9.3884535, 18.858315) if candy else Vector2(17.189741, 19.834671)
	food_icon.size = Vector2(132.22311, 110.495045) if candy else Vector2(115.62052, 108.208954)
	food_count_label.visible = food_button.visible and not unlimited
	food_count_label.text = "99+" if _food_count > 99 else str(_food_count)
	satiety_bar.visible = (
		active
		and _entry_ui_ready
		and _interaction.mode == Interaction.Mode.SATIETY
		and _satiety_enabled
	)
	if _tutorial_preview:
		satiety_bar.visible = satiety_bar.visible and _tutorial_hungry
	_refresh_satiety_display()
	if satiety_bar.visible and not _satiety_entry_played:
		_satiety_entry_played = true
		if _entry_animated and _satiety_entry_animation != null:
			_satiety_entry_animation.play(&"appear")
			_satiety_entry_animation.advance(0.0)


func _refresh_satiety_display() -> void:
	if _satiety_fill == null:
		return
	var target_color: Color = (
		Color(0.98039216, 0.68235296, 0.08627451, 1.0)
		if _satiety <= Interaction.HUNGRY_THRESHOLD
		else _satiety_normal_color
	)
	if not _satiety_display_initialized or not satiety_bar.visible:
		if _satiety_tween != null:
			_satiety_tween.kill()
		satiety_bar.value = _satiety
		_satiety_fill.bg_color = target_color
		_satiety_display_initialized = satiety_bar.visible
		_satiety_display_target = _satiety
		return
	if _satiety_tween != null and _satiety_tween.is_running():
		if is_equal_approx(_satiety_display_target, _satiety):
			return
		_satiety_tween.kill()
	if is_equal_approx(satiety_bar.value, _satiety) and _satiety_fill.bg_color == target_color:
		return
	_satiety_display_target = _satiety
	_satiety_tween = create_tween().set_parallel(true)
	_satiety_tween.tween_property(satiety_bar, "value", _satiety, 0.3)
	_satiety_tween.tween_property(_satiety_fill, "bg_color", target_color, 0.3)


func _validate_assets() -> bool:
	if (
		cat_sprite == null
		or cat_button == null
		or food_button == null
		or food_icon == null
		or food_count_label == null
		or satiety_bar == null
		or candy_texture == null
		or can_texture == null
	):
		push_error("HomeCompanionCat: missing scene bindings")
		return false
	var data: SpineSkeletonDataResource = cat_sprite.skeleton_data_res
	var required_clips: Array[String] = [
		entrance_clip, normal_idle_clip, hungry_idle_clip, touch_clip, feed_clip
	]
	for animation_name: String in required_clips:
		if data == null or data.find_animation(animation_name) == null:
			push_error("HomeCompanionCat: missing animation %s" % animation_name)
			return false
	if data.find_skin(default_skin) == null or data.find_skin(candy_skin) == null:
		push_error("HomeCompanionCat: missing skin")
		return false
	return true
