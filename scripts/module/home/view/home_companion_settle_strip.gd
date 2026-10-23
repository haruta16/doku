## 陪伴猫结算条：展示本局糖果与罐头进度，协调增长动画和奖励预览。
extends Control

const System: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")
const RewardPreview: GDScript = preload(
	"res://scripts/module/home/view/other/home_companion_reward_preview.gd"
)
const Service: GDScript = preload("res://scripts/module/home/home_companion_service.gd")

const ANCHOR_X: float = 326.0

const TOP_GAP: float = 32.0

const _FADE_IN_SEC: float = 0.367
const _GAIN_DELAY: float = 0.233
const _GAIN_POP_UP_SEC: float = 0.133
const _GAIN_POP_SCALE: float = 1.3
const _GAIN_POP_SETTLE_SEC: float = 0.25
const _BAR_GROW_SEC: float = 0.383
const _GAIN_RISE: float = 30.0
const _GAIN_RISE_DELAY: float = 0.383
const _GAIN_RISE_SEC: float = 0.6
const _GAIN_FADE_DELAY: float = 0.75
const _GAIN_FADE_SEC: float = 0.233

const _SEGMENT_FADE_DELAY: float = 0.367
const _SEGMENT_FADE_SEC: float = 0.25

signal candy_gain_finished

@export var candy_state: Control
@export var can_state: Control

@export var candy_gain: Control

@export var progress_bar: ProgressBar
@export var progress_label: Label
@export var reward_button: Button

@export var preview: RewardPreview
@export var countdown_label: Label

@export var can_gain: Control

@export var segments: Control
@export var segment_on: StyleBox
@export var segment_off: StyleBox
@export var segment_on_first: StyleBox
@export var segment_off_first: StyleBox
@export var segment_on_last: StyleBox
@export var segment_off_last: StyleBox

@export var preview_seconds: float = 1.5

var _service: Service = Service.new()
var _preview_timer: Timer
var _rewards_mode: bool = false
var _reward_kind: String = ""

var _gain_from: Dictionary = {}
var _gain_to: Dictionary = {}

var _settled: Dictionary = {}
var _gain_tween: Tween = null
var _gain_pending: bool = false

var _gain_rest_y: float = 0.0
var _can_gain_rest_y: float = 0.0

var _new_segment: int = -1
var _can_badge: bool = false


func _ready() -> void:
	visible = false
	_gain_rest_y = candy_gain.position.y
	_can_gain_rest_y = can_gain.position.y


func show_for(
	strategy: HomeCompanionCatStrategy, before: Dictionary, after: Dictionary, eligible: bool
) -> void:
	_stop_preview()
	_stop_gain()
	var mode: int = strategy.business_mode()
	var system: System = System.new(after)

	var before_system: System = System.new(before)
	var gained_candy: bool = int(after.get("candy_total", 0)) > int(before.get("candy_total", 0))
	_rewards_mode = (
		mode == System.Mode.HALLOWEEN_REWARDS
		and (
			not system.all_rewards_granted()
			or (gained_candy and not before_system.all_rewards_granted())
		)
	)
	var cans_mode: bool = mode == System.Mode.DAILY_CANS or mode == System.Mode.SATIETY
	visible = eligible and (_rewards_mode or cans_mode)
	candy_state.visible = visible and _rewards_mode
	can_state.visible = visible and not _rewards_mode
	if not visible:
		_disconnect_tick()
		return
	if _rewards_mode:
		_settled = system.reward_progress()
		_gain_to = _settled
		_gain_from = _settled
		_gain_pending = gained_candy
		if gained_candy:
			_gain_from = System.progress_for_total(int(before.get("candy_total", 0)))

			if int(_gain_from["tier"]) != int(_settled["tier"]) or system.all_rewards_granted():
				_gain_to = {
					"tier": _gain_from["tier"],
					"kind": _gain_from["kind"],
					"progress": _gain_from["required"],
					"required": _gain_from["required"]
				}
		_reward_kind = str(_gain_to["kind"])
		_set_candy_progress(float(_gain_from["progress"]), int(_gain_from["required"]))
		candy_gain.visible = false

		modulate.a = 0.0 if gained_candy else 1.0
		_refresh_countdown()
		if not ClockTicker.second_tick.is_connected(_refresh_countdown):
			ClockTicker.second_tick.connect(_refresh_countdown)
	else:
		_disconnect_tick()
		var can_progress: int = int(after.get("can_progress", 0))
		var gained_can: bool = int(after.get("cans", 0)) > int(before.get("cans", 0))

		var filled: int = System.WINS_PER_CAN if gained_can else can_progress
		_set_can_segments(filled)
		can_gain.visible = false

		var gained_segment: bool = gained_can or can_progress > int(before.get("can_progress", 0))
		_gain_pending = gained_segment
		_new_segment = filled - 1 if gained_segment else -1
		_can_badge = gained_can
		if gained_segment:
			var segment: Panel = segments.get_child(_new_segment) as Panel
			var lit: StyleBox = segment.get_theme_stylebox(&"panel")
			_set_can_segments(filled - 1)
			var overlay: Panel = _segment_overlay(segment)
			overlay.add_theme_stylebox_override(&"panel", lit)
			overlay.modulate.a = 0.0
			overlay.visible = true
		modulate.a = 0.0 if gained_segment else 1.0


func hide_strip() -> void:
	_stop_preview()
	_disconnect_tick()
	_stop_gain()
	visible = false


func chest_global_center() -> Vector2:
	if reward_button == null or not reward_button.is_visible_in_tree():
		return Vector2.INF
	return reward_button.get_global_rect().get_center()


func has_candy_gain() -> bool:
	return visible and _gain_pending


func gain_badge() -> Control:
	if _rewards_mode:
		return candy_gain
	return can_gain if _can_badge else null


func is_gain_playing() -> bool:
	return _gain_tween != null


func play_candy_gain() -> void:
	if not has_candy_gain():
		return
	_gain_pending = false
	_gain_tween = create_tween()
	_gain_tween.set_parallel(true)
	_gain_tween.tween_property(self, ^"modulate:a", 1.0, _FADE_IN_SEC).from(0.0)
	if _rewards_mode:
		(
			_gain_tween
			. tween_method(
				_on_gain_step,
				float(_gain_from["progress"]),
				float(_gain_to["progress"]),
				_BAR_GROW_SEC
			)
			. set_delay(_GAIN_DELAY)
			. set_ease(Tween.EASE_OUT)
		)
	else:
		(
			_gain_tween
			. tween_property(
				_segment_overlay(segments.get_child(_new_segment) as Panel),
				^"modulate:a",
				1.0,
				_SEGMENT_FADE_SEC
			)
			. from(0.0)
			. set_delay(_SEGMENT_FADE_DELAY)
		)
	var badge: Control = gain_badge()
	if badge == null:
		_gain_tween.finished.connect(_on_gain_finished, CONNECT_ONE_SHOT)
		return
	var rest_y: float = _badge_rest_y(badge)
	var rise_from: float = rest_y + _GAIN_RISE
	badge.visible = false
	badge.modulate.a = 1.0
	badge.pivot_offset = badge.size * 0.5
	badge.scale = Vector2.ZERO
	badge.position.y = rise_from
	_gain_tween.tween_callback(badge.show).set_delay(_GAIN_DELAY)
	(
		_gain_tween
		. tween_property(badge, ^"scale", Vector2.ONE * _GAIN_POP_SCALE, _GAIN_POP_UP_SEC)
		. from(Vector2.ZERO)
		. set_delay(_GAIN_DELAY)
	)
	(
		_gain_tween
		. tween_property(badge, ^"scale", Vector2.ONE, _GAIN_POP_SETTLE_SEC)
		. from(Vector2.ONE * _GAIN_POP_SCALE)
		. set_delay(_GAIN_DELAY + _GAIN_POP_UP_SEC)
	)
	(
		_gain_tween
		. tween_property(badge, ^"position:y", rest_y, _GAIN_RISE_SEC)
		. from(rise_from)
		. set_delay(_GAIN_DELAY + _GAIN_RISE_DELAY)
	)
	_gain_tween.tween_property(badge, ^"modulate:a", 0.0, _GAIN_FADE_SEC).from(1.0).set_delay(
		_GAIN_DELAY + _GAIN_FADE_DELAY
	)
	_gain_tween.finished.connect(_on_gain_finished, CONNECT_ONE_SHOT)


func _badge_rest_y(badge: Control) -> float:
	return _gain_rest_y if badge == candy_gain else _can_gain_rest_y


func settle_candy() -> void:
	_stop_gain()
	if not visible or not _rewards_mode:
		return
	if System.new(GameState.get_home_companion_data()).all_rewards_granted():
		hide_strip()
		return
	_reward_kind = str(_settled["kind"])
	_set_candy_progress(float(_settled["progress"]), int(_settled["required"]))


func _on_gain_step(progress: float) -> void:
	_set_candy_progress(progress, int(_gain_to["required"]))


func _on_gain_finished() -> void:
	_gain_tween = null
	if _rewards_mode:
		_set_candy_progress(float(_gain_to["progress"]), int(_gain_to["required"]))
	_reset_gain_visual()
	candy_gain_finished.emit()


func _stop_gain() -> void:
	_gain_pending = false
	_reset_gain_visual()
	if _gain_tween == null:
		return
	_gain_tween.kill()
	_gain_tween = null
	candy_gain_finished.emit()


func _reset_gain_visual() -> void:
	modulate.a = 1.0
	if _new_segment >= 0:
		_set_can_segments(_new_segment + 1)
		_segment_overlay(segments.get_child(_new_segment) as Panel).visible = false
		_new_segment = -1
	var badges: Array[Control] = [candy_gain, can_gain]
	for badge: Control in badges:
		badge.visible = false
		badge.scale = Vector2.ONE
		badge.modulate.a = 1.0
		badge.position.y = _badge_rest_y(badge)


func _set_candy_progress(progress: float, required: int) -> void:
	progress_label.text = "%d/%d" % [roundi(progress), required]

	progress_bar.max_value = maxi(required, 1)
	progress_bar.value = clampf(progress, 0.0, float(required))


func filled_segments() -> int:
	var filled: int = 0
	var count: int = segments.get_child_count()
	for index: int in count:
		var style: StyleBox = (segments.get_child(index) as Panel).get_theme_stylebox(&"panel")
		if style == segment_on or style == segment_on_first or style == segment_on_last:
			filled += 1
	return filled


func _segment_overlay(segment: Panel) -> Panel:
	var overlay: Panel = segment.get_node_or_null(^"GainOverlay") as Panel
	if overlay == null:
		overlay = Panel.new()
		overlay.name = &"GainOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.visible = false
		segment.add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return overlay


func _set_can_segments(filled: int) -> void:
	var count: int = segments.get_child_count()
	for index: int in count:
		var on: bool = index < filled
		var style: StyleBox = segment_on if on else segment_off
		if index == 0:
			style = segment_on_first if on else segment_off_first
		elif index == count - 1:
			style = segment_on_last if on else segment_off_last
		(segments.get_child(index) as Panel).add_theme_stylebox_override(&"panel", style)


func _refresh_countdown() -> void:
	if not visible or not _rewards_mode:
		return
	countdown_label.text = System.format_countdown(System.EVENT_END - _service.current_time())


func _on_reward_pressed() -> void:
	if not _rewards_mode:
		return

	Tracker.track_btn_click(Tracker.Btn.COMPANION_CAT_TREASURE_BOX, self)
	if _preview_timer == null:
		_preview_timer = Timer.new()
		_preview_timer.one_shot = true
		_preview_timer.timeout.connect(_on_preview_timeout)
		add_child(_preview_timer)
	_preview_timer.wait_time = preview_seconds
	preview.show_reward(_reward_kind)
	preview.set_shown(true)
	_preview_timer.start()


func _on_preview_timeout() -> void:
	preview.set_shown(false)


func _stop_preview() -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	if preview != null:
		preview.set_shown(false, false)


func _disconnect_tick() -> void:
	if ClockTicker.second_tick.is_connected(_refresh_countdown):
		ClockTicker.second_tick.disconnect(_refresh_countdown)


func _exit_tree() -> void:
	_disconnect_tick()
