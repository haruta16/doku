## 打卡历史首页：切换月份、渲染签到日历与奖励状态，并适配页面高度。
@tool
extends UIFrameWindow

signal previous_month_requested
signal next_month_requested
signal continue_requested

const _CALENDAR_CELL_COUNT: int = 42
const CALENDAR_CELL_VIEW = preload(
	"res://scripts/module/daily_streak/view/other/streak_calendar_cell.gd"
)
const STREAK_HISTORY: GDScript = preload("res://scripts/module/daily_streak/core/streak_history.gd")
const _WEEKDAY_KEYS: Array[String] = [
	"WEEKDAY_SUN",
	"WEEKDAY_MON",
	"WEEKDAY_TUE",
	"WEEKDAY_WED",
	"WEEKDAY_THU",
	"WEEKDAY_FRI",
	"WEEKDAY_SAT",
]

@export_group("Content Fit")
@export_range(0.1, 1.0, 0.01) var max_content_scale: float = 1.0:
	set(value):
		max_content_scale = value
		if is_node_ready():
			_queue_fit()

@export_range(0.0, 1.0, 0.01) var content_vertical_alignment: float = 0.0:
	set(value):
		content_vertical_alignment = value
		if is_node_ready():
			_queue_fit()

@export_group("Presentation")
@export var show_extended_reward_track: bool = false:
	set(value):
		show_extended_reward_track = value
		if is_node_ready():
			_refresh_reward_state()

@export var calendar_cell_scene: PackedScene

@export_group("Editor Preview")
@export_range(1970, 2100, 1) var preview_year: int = 2026:
	set(value):
		preview_year = clampi(value, 1970, 2100)
		_queue_editor_preview()

@export_range(1, 12, 1) var preview_month: int = 9:
	set(value):
		preview_month = clampi(value, 1, 12)
		_queue_editor_preview()

@export var preview_checked_days: PackedInt32Array = PackedInt32Array():
	set(value):
		preview_checked_days = value
		_queue_editor_preview()

@export_group("Scene Bindings")
@export var _entry_animation_player: AnimationPlayer
@export var _safe_area: MarginContainer
@export var _page_margin: MarginContainer
@export var _header_offset: MarginContainer
@export var _header: MarginContainer
@export var _body_fit: Control
@export var _content: VBoxContainer
@export var _back_button: Button
@export var _title: Label
@export var _current_caption: Label
@export var _weekday_row: HBoxContainer
@export var _progress_before: Control
@export var _progress_after: Control
@export var _continue_button: BaseButton
@export var _calendar_grid: GridContainer
@export var _month_caption: Label
@export var _streak_number: Label
@export var _day_icon: StreakDayIcon
@export var _previous_month_button: Button
@export var _next_month_button: Button
@export var _previous_month_visual: TextureRect
@export var _next_month_visual: TextureRect
@export var _before_reward_labels: Array[Label]
@export var _after_reward_labels: Array[Label]
@export var _before_reward_anchors: Array[Marker2D]
@export var _after_reward_anchors: Array[Marker2D]
@export var _before_reward_track: Control
@export var _after_reward_track: Control
@export var _before_reward_fill: TextureRect
@export var _after_reward_fill: TextureRect
@export var _reward_claimed_chest: TextureRect

@export_group("Icon Fit")
@export var icon_height: float = 332.0
@export var icon_center: Vector2 = Vector2(252.0, 166.0)

var _entering_game: bool = false
var _entry_animation_running: bool = false
var _calendar_cells: Array[CALENDAR_CELL_VIEW] = []
var _layout_queued: bool = false
var _fit_queued: bool = false
var _editor_preview_queued: bool = false
var _selected_month_index: int = 0
var _min_month_index: int = 0
var _max_month_index: int = 0
var _last_refresh_jdn: int = 0
var _data_refresh_count: int = 0
var _month_render_count: int = 0


func _ready() -> void:
	if _safe_area == null or _body_fit == null or _content == null:
		return
	resized.connect(_queue_layout)
	_body_fit.resized.connect(_queue_fit)
	_content.minimum_size_changed.connect(_queue_fit)
	_page_margin.theme_changed.connect(_queue_layout)
	_header.theme_changed.connect(_queue_layout)
	_initialize_calendar_cells()
	if Engine.is_editor_hint():
		_refresh_editor_preview()
	else:
		_refresh_text()
	_refresh_reward_state()
	_queue_layout()


func _queue_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready() or _editor_preview_queued:
		return
	_editor_preview_queued = true
	call_deferred("_refresh_editor_preview")


func _refresh_editor_preview() -> void:
	_editor_preview_queued = false
	if (
		not Engine.is_editor_hint()
		or _month_caption == null
		or _calendar_cells.size() != _CALENDAR_CELL_COUNT
	):
		return
	var first_jdn: int = STREAK_HISTORY.date_to_jdn(preview_year, preview_month, 1)
	var day_count: int = STREAK_HISTORY.days_in_month(preview_year, preview_month)
	var preview_days: Array[bool] = []
	preview_days.resize(day_count)
	preview_days.fill(false)
	for day: int in preview_checked_days:
		if day >= 1 and day <= day_count:
			preview_days[day - 1] = true
	_month_caption.text = "%02d/%04d" % [preview_month, preview_year]
	render_calendar((first_jdn + 1) % 7, preview_days)


func on_create() -> void:
	bind_press_release_scale(_back_button)


func on_show(_params: Dictionary = {}) -> void:
	_entering_game = false
	_continue_button.visible = true
	_continue_button.disabled = _entry_animation_running
	if not _entry_animation_running:
		_continue_button.modulate = Color.WHITE
		_continue_button.self_modulate = Color.WHITE
		_continue_button.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_refresh_text()
	connect_managed(StreakManager.streak_updated, _on_streak_updated)
	_refresh_from_model(true)
	connect_managed(HomeSettingAnchor.anchor_changed, _on_home_anchor_changed)
	connect_managed(get_viewport().size_changed, _queue_layout)
	_queue_layout()


func _play_open_animation() -> void:
	if _entry_animation_player == null or not _entry_animation_player.has_animation(open_anim_name):
		push_error("StreakHomePage: entry animation binding is missing")
		return
	_entry_animation_running = true
	_continue_button.disabled = true

	_continue_button.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_entry_animation_player.play(&"RESET")
	_entry_animation_player.advance(0.0)
	connect_managed_once(_entry_animation_player.animation_finished, _on_entry_animation_finished)
	super._play_open_animation()
	_entry_animation_player.advance(0.0)


func _on_entry_animation_finished(animation_name: StringName) -> void:
	if animation_name != StringName(open_anim_name) or not is_showing():
		return
	_entry_animation_running = false
	_continue_button.disabled = _entering_game
	_continue_button.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED


func on_hide() -> void:
	_entry_animation_player.stop()
	_entry_animation_running = false


func on_escape() -> bool:
	_on_back_pressed()
	return true


func get_scr_name() -> String:
	return Tracker.Scr.STREAK


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
		_queue_layout()


func _refresh_text() -> void:
	if (
		_title == null
		or _current_caption == null
		or _weekday_row == null
		or _continue_button == null
	):
		return
	_title.text = tr("DAILY_STREAK_TITLE")
	_current_caption.text = tr("DAILY_STREAK_CURRENT")
	_continue_button.set("btn_text", tr("WIN_CONTINUE"))
	var weekdays: Array[Node] = _weekday_row.get_children()
	for index in weekdays.size():
		var label: Label = weekdays[index].get_node("WEDTxt")
		label.text = tr(_WEEKDAY_KEYS[index])


func _refresh_reward_state() -> void:
	if _progress_before == null or _progress_after == null:
		return
	_progress_before.visible = not show_extended_reward_track
	_progress_after.visible = show_extended_reward_track


func _on_streak_updated(_data: StreakData) -> void:
	_refresh_from_model(false)


func _refresh_from_model(reset_month: bool) -> void:
	var today: Dictionary = StreakManager.get_today_date()
	var today_jdn: int = STREAK_HISTORY.date_to_jdn(today["year"], today["month"], today["day"])
	if reset_month or today_jdn != _last_refresh_jdn:
		_selected_month_index = int(today["year"]) * 12 + int(today["month"]) - 1
	_last_refresh_jdn = today_jdn
	var bounds: Dictionary = StreakManager.get_history_month_range()
	_min_month_index = int(bounds["min_year"]) * 12 + int(bounds["min_month"]) - 1
	_max_month_index = int(bounds["max_year"]) * 12 + int(bounds["max_month"]) - 1
	_selected_month_index = clampi(_selected_month_index, _min_month_index, _max_month_index)
	_streak_number.text = str(maxi(0, StreakManager.get_display_streak()))
	var today_flags: Array[bool] = StreakManager.get_history_month(today["year"], today["month"])
	var checked_today: bool = today_flags[int(today["day"]) - 1]
	_day_icon.reset_icon()
	_day_icon.refresh_group(checked_today)
	_day_icon.fit_uniform_height(icon_height, icon_center)
	_render_selected_month()
	_render_rewards(StreakManager.get_display_reward_cycle())
	_data_refresh_count += 1
	_queue_fit()


func _render_selected_month() -> void:
	var year: int = floori(float(_selected_month_index) / 12.0)
	var month: int = _selected_month_index % 12 + 1
	var flags: Array[bool] = StreakManager.get_history_month(year, month)
	var first_jdn: int = STREAK_HISTORY.date_to_jdn(year, month, 1)
	render_calendar((first_jdn + 1) % 7, flags)
	_month_caption.text = "%02d/%04d" % [month, year]
	_set_month_arrow(
		_previous_month_button, _previous_month_visual, _selected_month_index > _min_month_index
	)
	_set_month_arrow(
		_next_month_button, _next_month_visual, _selected_month_index < _max_month_index
	)
	_month_render_count += 1


func _set_month_arrow(button: Button, visual: TextureRect, enabled: bool) -> void:
	button.disabled = not enabled
	visual.modulate.a = 1.0 if enabled else 0.4
	var material: ShaderMaterial = visual.material as ShaderMaterial
	material.set_shader_parameter("disabled", 0.0 if enabled else 1.0)


func _render_rewards(cycle: int) -> void:
	cycle = maxi(0, cycle)
	show_extended_reward_track = cycle >= 7
	var labels: Array[Label] = (
		_after_reward_labels if show_extended_reward_track else _before_reward_labels
	)
	var anchors: Array[Marker2D] = (
		_after_reward_anchors if show_extended_reward_track else _before_reward_anchors
	)
	var track: Control = _after_reward_track if show_extended_reward_track else _before_reward_track
	var fill: TextureRect = (
		_after_reward_fill if show_extended_reward_track else _before_reward_fill
	)
	var milestone: int = cycle - cycle % 7 if show_extended_reward_track else 7
	for index in labels.size():
		labels[index].text = str(milestone + index * 7)
	var endpoint: float = track.position.x
	if show_extended_reward_track:
		endpoint = lerpf(
			anchors[0].position.x, anchors[1].position.x, float(cycle - milestone) / 7.0
		)
	else:
		endpoint = lerpf(track.position.x, anchors[0].position.x, float(cycle) / 7.0)
	endpoint = clampf(endpoint, track.position.x, track.get_rect().end.x)
	fill.position.x = track.position.x
	fill.size.x = endpoint - track.position.x
	fill.visible = fill.size.x > 0.0
	_reward_claimed_chest.visible = show_extended_reward_track


func _on_home_anchor_changed(_center: float) -> void:
	_queue_layout()


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_update_layout")


func debug_recompute() -> void:
	_queue_layout()


func _update_layout() -> void:
	_layout_queued = false
	if not is_node_ready() or _safe_area == null or _body_fit == null:
		return
	var insets: Vector2 = Vector2.ZERO
	if not Engine.is_editor_hint():
		insets = UIManager.get_safe_insets()
	_set_margin(_safe_area, "margin_top", ceili(insets.x))
	_set_margin(_safe_area, "margin_bottom", ceili(insets.y))
	var extra_header_top: float = 0.0
	if not Engine.is_editor_hint() and HomeSettingAnchor.has_value():
		var base_center: float = (
			global_position.y
			+ insets.x
			+ _page_margin.get_theme_constant("margin_top")
			+ _header.get_theme_constant("margin_top")
			+ _back_button.position.y
			+ _back_button.size.y * 0.5
		)
		extra_header_top = maxf(0.0, HomeSettingAnchor.get_settingbtn_y() - base_center)
	_set_margin(_header_offset, "margin_top", ceili(extra_header_top))
	_queue_fit()


func _set_margin(container: MarginContainer, property: StringName, value: int) -> void:
	if container.get_theme_constant(property) != value:
		container.add_theme_constant_override(property, value)


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	call_deferred("_fit_content")


func _fit_content() -> void:
	_fit_queued = false
	if not is_node_ready() or _body_fit == null or _content == null:
		return
	var design_size: Vector2 = _content.get_combined_minimum_size()
	if (
		design_size.x <= 0.0
		or design_size.y <= 0.0
		or _body_fit.size.x <= 0.0
		or _body_fit.size.y <= 0.0
	):
		return
	_content.size = design_size
	var fit_scale: float = minf(
		max_content_scale, minf(_body_fit.size.x / design_size.x, _body_fit.size.y / design_size.y)
	)
	_content.scale = Vector2.ONE * fit_scale
	var remaining: Vector2 = _body_fit.size - design_size * fit_scale
	_content.position = Vector2(remaining.x * 0.5, remaining.y * content_vertical_alignment)


func _initialize_calendar_cells() -> void:
	if not _calendar_cells.is_empty():
		return
	if _calendar_grid == null or calendar_cell_scene == null:
		push_error("StreakHomePage: calendar scene bindings are missing")
		return
	for index in _CALENDAR_CELL_COUNT:
		var cell_name: String = "Date%02d" % index
		var cell: CALENDAR_CELL_VIEW = (
			_calendar_grid.get_node_or_null(cell_name) as CALENDAR_CELL_VIEW
		)
		if cell == null:
			cell = calendar_cell_scene.instantiate() as CALENDAR_CELL_VIEW
			cell.name = cell_name
			_calendar_grid.add_child(cell)

		cell.render_day(0, false)
		_calendar_cells.append(cell)


func render_calendar(first_weekday: int, checked_days: Array[bool]) -> void:
	if first_weekday < 0 or first_weekday >= _calendar_grid.columns or checked_days.size() > 31:
		push_error("StreakHomePage: invalid calendar presentation")
		return
	if _calendar_cells.size() != _CALENDAR_CELL_COUNT:
		push_error("StreakHomePage: calendar cells are not initialized")
		return
	var columns: int = _calendar_grid.columns
	var column_gap: float = float(_calendar_grid.get_theme_constant(&"h_separation"))
	for index in _CALENDAR_CELL_COUNT:
		var day_index: int = index - first_weekday
		var in_month: bool = day_index >= 0 and day_index < checked_days.size()
		var checked: bool = in_month and checked_days[day_index]
		var column: int = index % columns
		var starts_segment: bool = (
			checked and (column == 0 or day_index == 0 or not checked_days[day_index - 1])
		)
		var segment_width: float = 0.0
		if starts_segment:
			var segment_length: int = 1
			while (
				column + segment_length < columns
				and day_index + segment_length < checked_days.size()
				and checked_days[day_index + segment_length]
			):
				segment_length += 1
			var cell_width: float = _calendar_cells[index].custom_minimum_size.x
			segment_width = cell_width * segment_length + column_gap * (segment_length - 1)
		_calendar_cells[index].render_day(
			day_index + 1 if in_month else 0, checked, starts_segment, segment_width
		)


func _on_back_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(get_ui_name())


func _on_previous_month_pressed() -> void:
	if not is_showing() or _selected_month_index <= _min_month_index:
		return
	_selected_month_index -= 1
	_render_selected_month()
	previous_month_requested.emit()


func _on_next_month_pressed() -> void:
	if not is_showing() or _selected_month_index >= _max_month_index:
		return
	_selected_month_index += 1
	_render_selected_month()
	next_month_requested.emit()


func _on_continue_pressed() -> void:
	if _entry_animation_running or _entering_game or not is_showing() or not is_visible_in_tree():
		return
	_entering_game = true
	_continue_button.disabled = true
	Tracker.track_btn_click(Tracker.Btn.GOTOPLAY, self)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_GO_PLAY)
	continue_requested.emit()
	var game: UIFrameWindow = UIManager.show_ui(
		UiName.GAME, {"level_index": GameState.get_current_level()}
	)
	if game == null:
		_entering_game = false
		_continue_button.disabled = false
		return
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home != null and home.is_showing():
		UIManager.hide_ui(UiName.HOME)
	UIManager.hide_ui(get_ui_name())
