## 首页陪伴猫面板：协调业务策略、交互猫、引导和奖励预览，并响应喂食请求。
extends Control

const Service: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
const System: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")
const Interaction: GDScript = preload(
	"res://scripts/module/home/core/home_companion_interaction.gd"
)
const RewardPreview: GDScript = preload(
	"res://scripts/module/home/view/other/home_companion_reward_preview.gd"
)

const ENTRY_PREVIEW_SECONDS: float = 3.0
const MANUAL_PREVIEW_SECONDS: float = 1.5

signal explanation_requested

@export var cat: Control
@export var logo: Control
@export var logo_visual_anchor: Node2D
@export var layout_top_anchor: Control
@export var start_button: Control
@export var hud: Control
@export var reward_button: Button
@export var progress_bar: ProgressBar
@export var progress_label: Label
@export var countdown_label: Label
@export var food_bubble: Control
@export var progress_fill: Control
@export var preview: RewardPreview
@export var hud_gap: float = 191.0
@export var food_bubble_offset: Vector2 = Vector2(243.0, -771.0)
@export_range(0.1, 1.0) var cat_scale: float = 0.65

@export var cat_visual_center_x: float = 351.0

@export var cat_visual_offset_y: float = 10.0

@export_range(0.1, 1.0) var logo_scale: float = 0.86769366

@export_range(0.1, 1.0) var non_companion_logo_scale: float = 0.87988822

@export var non_companion_start_offset_y: float = -52.0

@export var companion_bottom_margin: float = 16.0

@export var cat_gap: float = 572.0

@export var logo_layout_rect: Rect2 = Rect2(40, 40, 530, 420)

@export var cat_layout_rect: Rect2 = Rect2(110, -330, 525, 890)
@export var logo_cat_gap: float = 72.0889
@export var layout_top_margin: float = 220.0
@export_range(0.1, 1.0) var minimum_layout_scale: float = 0.5

var _service: Service = Service.new()
var _strategy: HomeCompanionCatStrategy = HomeCompanionCatStrategy.new()
var _requested_strategy: HomeCompanionCatStrategy = HomeCompanionCatStrategy.new()
var _active: bool = false
var _entry_prepared: bool = false
var _logo_original: Dictionary = {}
var _preview_timer: Timer
var _entry_progress: Dictionary = {}
var _entry_rewards_visible: bool = false
var _entry_tutorial_pending: bool = false
var _layout_queued: bool = false

@onready var _entry_animation: AnimationPlayer = $AnimationPlayer

@onready var _home_logo_scale: Vector2 = logo.scale

@onready
var _home_start_offsets: Vector2 = Vector2(start_button.offset_top, start_button.offset_bottom)


func _ready() -> void:
	cat.entry_ui_revealed.connect(_on_entry_ui_revealed)
	var progress_button: BaseButton = progress_bar.get_parent() as BaseButton
	var feedback_buttons: Array[BaseButton] = [
		food_bubble as BaseButton, progress_button, reward_button
	]
	for button in feedback_buttons:
		UIHelper.bind_press_release_scale(button)
		button.visibility_changed.connect(_on_feedback_visibility_changed.bind(button))
	_service.connect_victories()
	GameState.home_companion_changed.connect(_on_data_changed)
	resized.connect(_queue_layout)
	if start_button != null:
		start_button.item_rect_changed.connect(_queue_layout)
	if layout_top_anchor != null:
		layout_top_anchor.item_rect_changed.connect(_queue_layout)
	visible = false


func _on_feedback_visibility_changed(button: BaseButton) -> void:
	if not button.is_visible_in_tree():
		UIHelper.reset_press_scale(button)


func _exit_tree() -> void:
	_service.disconnect_victories()
	if GameState.home_companion_changed.is_connected(_on_data_changed):
		GameState.home_companion_changed.disconnect(_on_data_changed)


func prepare_entry(requested: HomeCompanionCatStrategy) -> void:
	end_entry()
	_entry_prepared = true
	_requested_strategy = requested
	if not requested.has_companion():
		logo.scale = _home_logo_scale * non_companion_logo_scale
		start_button.offset_top = _home_start_offsets.x + non_companion_start_offset_y
		start_button.offset_bottom = _home_start_offsets.y + non_companion_start_offset_y
	_strategy = _service.enter_home(requested, _service.current_time())

	if _strategy.earned_currency() == &"candy":
		_service.grant_pending_rewards()
	var system: System = System.new(_service.snapshot())
	_entry_progress = system.reward_progress()
	_entry_rewards_visible = (
		_strategy.earned_currency() == &"candy" and not system.all_rewards_granted()
	)


## 把业务策略映射成交互模式，将库存、饱食度和引导状态传给猫视图。
func begin_entry() -> void:
	if not _strategy.has_companion():
		return
	_active = true
	_entry_tutorial_pending = tutorial_needed()
	visible = true
	refresh_layout()
	var data: Dictionary = _service.snapshot()
	var presentation_mode: int = Interaction.Mode.COSMETIC
	if _strategy.earned_currency() == &"candy":
		presentation_mode = Interaction.Mode.CANDY
	elif _strategy.business_mode() == System.Mode.DAILY_INTERACT:
		presentation_mode = Interaction.Mode.INTERACT
	elif _strategy.has_satiety():
		presentation_mode = Interaction.Mode.SATIETY
	elif _strategy.allows_feeding():
		presentation_mode = Interaction.Mode.CANS
	cat.begin_home_entry(
		presentation_mode,
		int(data["cans"]),
		float(data["satiety"]),
		bool(data["satiety_enabled"]),
		not _strategy.has_satiety(),
		_food_bubble_unlocked(data),
		_entry_tutorial_pending
	)
	_refresh_hud()


func _on_entry_ui_revealed() -> void:
	if not _active:
		return
	_refresh_hud()
	if hud.visible and cat.is_entry_animated():
		_entry_animation.play(&"appear")
		_entry_animation.advance(0.0)
	show_preview(ENTRY_PREVIEW_SECONDS)


func end_entry() -> void:
	stop_presentation()
	restore_logo_layout()
	logo.scale = _home_logo_scale
	start_button.offset_top = _home_start_offsets.x
	start_button.offset_bottom = _home_start_offsets.y


func stop_presentation() -> void:
	_active = false
	_entry_prepared = false
	_entry_tutorial_pending = false
	visible = false
	_entry_animation.stop()
	hud.modulate = Color.WHITE
	hud.hide()
	if preview != null:
		preview.hide()
	cat.end_home_entry()
	if _preview_timer != null:
		_preview_timer.stop()


func restore_logo_layout() -> void:
	if not _logo_original.is_empty():
		logo.position = _logo_original["position"]
		logo.scale = _logo_original["scale"]
		_logo_original.clear()


func fit_start_button(bottom_edge: float) -> void:
	if not _entry_prepared or not _requested_strategy.has_companion():
		return
	var baseline_delta: float = _home_start_offsets.x - start_button.offset_top
	var safe_bottom: float = get_viewport_rect().end.y - UIManager.get_safe_insets().y
	var compensation: float = minf(
		0.0, safe_bottom - companion_bottom_margin - bottom_edge - baseline_delta
	)
	var target_top: float = _home_start_offsets.x + compensation
	if absf(start_button.offset_top - target_top) < 0.01:
		return
	start_button.offset_top = target_top
	start_button.offset_bottom = _home_start_offsets.y + compensation


func refresh_layout() -> void:
	if not _active:
		return
	if _logo_original.is_empty():
		_logo_original = {
			"position": logo.position,
			"scale": logo.scale,
			"visual_offset_x":
			logo_visual_anchor.global_position.x - global_position.x - size.x * 0.5
		}
	var original_logo_scale: Vector2 = _logo_original["scale"]
	var preferred_logo_scale: Vector2 = original_logo_scale * logo_scale
	var cat_foot_y: float = start_button.position.y - cat_gap + 540.0 * cat_scale
	var top_limit: float = layout_top_margin
	if layout_top_anchor != null:
		top_limit = maxf(
			top_limit, layout_top_anchor.get_global_rect().end.y - global_position.y + logo_cat_gap
		)
	var available_height: float = cat_foot_y - top_limit - logo_cat_gap
	var logo_height: float = logo_layout_rect.size.y * preferred_logo_scale.y
	var cat_height: float = (540.0 - cat_layout_rect.position.y) * cat_scale
	var fit_scale: float = clampf(
		(available_height - logo_height) / cat_height, minimum_layout_scale, 1.0
	)
	cat.scale = Vector2.ONE * cat_scale * fit_scale
	cat.position = Vector2(
		size.x * 0.5 - cat_visual_center_x * cat.scale.x,
		cat_foot_y - 540.0 * cat.scale.y + cat_visual_offset_y
	)
	cat.refresh_accessory_layout(global_position.x + size.x * 0.5)
	var cat_top: float = (
		cat.position.y - cat_visual_offset_y + cat_layout_rect.position.y * cat.scale.y
	)

	var logo_fit_scale: float = clampf(
		(available_height - cat_height * fit_scale) / logo_height, minimum_layout_scale, 1.0
	)
	logo.scale = preferred_logo_scale * logo_fit_scale
	var logo_pivot: Vector2 = logo.pivot_offset + logo.size * logo.pivot_offset_ratio
	logo.position.y = (
		cat_top
		- logo_cat_gap
		- logo_layout_rect.end.y * logo.scale.y
		- logo_pivot.y * (1.0 - logo.scale.y)
	)
	logo.global_position.x += (
		global_position.x
		+ size.x * 0.5
		+ float(_logo_original["visual_offset_x"])
		- logo_visual_anchor.global_position.x
	)
	hud.position = Vector2(size.x * 0.5 - hud.size.x * 0.5, start_button.position.y - hud_gap)
	hud.global_position.x += (
		global_position.x + size.x * 0.5 - progress_bar.get_global_rect().get_center().x
	)
	if food_bubble != null:
		food_bubble.position = Vector2(size.x * 0.5, start_button.position.y) + food_bubble_offset


func _queue_layout() -> void:
	if not _active or _layout_queued:
		return
	_layout_queued = true
	_refresh_deferred_layout.call_deferred()


func _refresh_deferred_layout() -> void:
	_layout_queued = false
	refresh_layout()


func has_companion() -> bool:
	return _strategy.has_companion()


func halloween_dress_active() -> bool:
	return Service.is_halloween_dress_mode(_service.resolve_mode(HomeCompanionCatStrategy.create()))


func is_feeding() -> bool:
	return _active and cat.get_interaction_state() == Interaction.State.FEED


func set_interaction_enabled(enabled: bool) -> void:
	cat.set_interaction_enabled(enabled and _active)


func tutorial_needed() -> bool:
	return _service.tutorial_needed(_strategy)


func tutorial_kind() -> StringName:
	return _strategy.tutorial_kind()


func guide_parameters(tutorial: bool) -> Dictionary:
	var data: Dictionary = _service.snapshot()
	return {
		"kind": tutorial_kind(),
		"tutorial": tutorial,
		"clock": _service.current_time,
		"cat_position": cat.global_position,
		"cat_scale": cat.get_global_transform().get_scale(),
		"cat_source": cat,
		"food_count": int(data["cans"]),
		"satiety": float(data["satiety"])
	}


func begin_tutorial() -> void:
	cat.hide()
	if food_bubble != null:
		food_bubble.hide()


func resume_after_tutorial() -> void:
	if not _active:
		return
	var tutorial_completed: bool = _entry_tutorial_pending and not tutorial_needed()
	if tutorial_completed:
		_entry_tutorial_pending = false
	cat.show()
	var data: Dictionary = _service.snapshot()
	cat.refresh_status(
		int(data["cans"]),
		float(data["satiety"]),
		bool(data["satiety_enabled"]),
		_food_bubble_unlocked(data)
	)
	cat.resume_after_tutorial()
	if not _entry_tutorial_pending:
		cat.reveal_tutorial_food(_strategy.earned_currency() == &"candy")
		if tutorial_completed:
			show_preview(ENTRY_PREVIEW_SECONDS)
	elif _strategy.earned_currency() != &"candy":
		cat.reveal_tutorial_food(false)


func complete_tutorial() -> void:
	_service.complete_tutorial(_strategy)


func pending_reward_presentations() -> Array[int]:
	return _service.pending_presentations()


func complete_reward_presentation(tier: int) -> bool:
	return _service.complete_reward_presentation(tier)


func chest_global_center() -> Vector2:
	if not reward_button.is_visible_in_tree():
		return Vector2.INF
	return reward_button.get_global_rect().get_center()


func event_ended() -> bool:
	return bool(_service.snapshot()["event_ended"])


func closed_notice_needed(
	previous: HomeCompanionCatStrategy, current: HomeCompanionCatStrategy
) -> bool:
	var system: System = System.new(_service.snapshot())
	return system.closed_notice_needed(previous.business_mode(), current.business_mode())


## 面板激活时刷新饱食状态与 HUD，库存和衰减数据来自业务服务。
func tick() -> void:
	if not _active:
		return
	if _strategy.has_satiety():
		var data: Dictionary = _service.snapshot()
		cat.refresh_status(
			int(data["cans"]),
			float(data["satiety"]),
			bool(data["satiety_enabled"]),
			_food_bubble_unlocked(data)
		)
	_refresh_hud()


## 先由业务服务批准并扣库存，再通知猫播放喂食；已吃饱时显示提示。
func _on_feeding_requested() -> void:
	if not _active:
		cat.confirm_feeding(false)
		return
	var result: System.FeedResult = _service.feed_result(_strategy)
	cat.confirm_feeding(result == System.FeedResult.ACCEPTED)
	if result == System.FeedResult.FULL:
		Toast.popup(tr("HOME_COMPANION_FULL_TOAST"), self)


func _on_data_changed() -> void:
	if not _active:
		return
	var data: Dictionary = _service.snapshot()
	cat.refresh_status(
		int(data["cans"]),
		float(data["satiety"]),
		bool(data["satiety_enabled"]),
		_food_bubble_unlocked(data)
	)
	_refresh_hud()


func _food_bubble_unlocked(data: Dictionary) -> bool:
	var mode: int = _requested_strategy.business_mode()
	return (
		mode not in [System.Mode.DAILY_CANS, System.Mode.SATIETY] or bool(data["has_received_cans"])
	)


func _refresh_hud() -> void:
	var system: System = System.new(_service.snapshot())
	var data: Dictionary = system.snapshot()
	var rewards: bool = _active and cat.is_entry_ui_ready() and _entry_rewards_visible
	hud.visible = rewards
	reward_button.visible = rewards
	progress_bar.visible = rewards
	countdown_label.visible = rewards
	progress_label.visible = rewards
	if rewards:
		var tier: int = int(_entry_progress["tier"])
		var previous: int = 0 if tier == 0 else System.REWARD_THRESHOLDS[tier - 1]
		var required: int = int(_entry_progress["required"])
		var progress: int = clampi(int(data["candy_total"]) - previous, 0, required)
		progress_bar.max_value = required
		progress_bar.value = progress
		if progress_fill != null:
			progress_fill.size.x = progress_bar.size.x * progress_bar.ratio
			progress_fill.visible = progress > 0
		progress_label.text = "%s/%s" % [progress, required]
		var remaining: int = maxi(0, System.EVENT_END - _service.current_time())
		countdown_label.text = System.format_countdown(remaining)
	else:
		progress_label.text = ""
	_refresh_preview_visibility()


func _refresh_preview_visibility() -> void:
	var preview_visible: bool = (
		_active
		and not _entry_tutorial_pending
		and cat.is_entry_ui_ready()
		and _entry_rewards_visible
		and _preview_timer != null
		and not _preview_timer.is_stopped()
	)
	if preview != null:
		preview.show_reward(str(_entry_progress.get("kind", "")))
		preview.set_shown(preview_visible)


func show_preview(duration_seconds: float = MANUAL_PREVIEW_SECONDS) -> void:
	if (
		not _active
		or _entry_tutorial_pending
		or not cat.is_entry_ui_ready()
		or _strategy.earned_currency() != &"candy"
	):
		return
	if _preview_timer == null:
		_preview_timer = Timer.new()
		_preview_timer.one_shot = true
		_preview_timer.wait_time = MANUAL_PREVIEW_SECONDS
		_preview_timer.timeout.connect(_on_preview_timeout)
		add_child(_preview_timer)
	_preview_timer.start(duration_seconds)
	_refresh_hud()


func _on_preview_timeout() -> void:
	if preview != null:
		preview.set_shown(false)


func _on_reward_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.COMPANION_CAT_TREASURE_BOX, self)
	show_preview()


func _on_progress_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.COMPANION_CAT_CANDY_BAR, self)
	if _active and _strategy.earned_currency() == &"candy":
		explanation_requested.emit()
