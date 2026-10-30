## 紧凑打卡入口：按布局规则缩放图标，保留与常规入口一致的状态刷新。
extends UIChildWindow

@onready var _state_checked: Control = $Content/StateChecked
@onready var _state_unchecked: Control = $Content/StateUnchecked

const _ICON_BASE_HEIGHT: float = 163.0
const _ICON_CENTER := Vector2(313.98, 313.33)

@onready var _day_icon: StreakDayIcon = $Content/DayIcon
@onready var _count: Label = $Content/CheckinCount/Count
@onready var _click_btn: Button = $ClickBtn

@onready var _shine: Control = $Content/Bg/Bg/Particle

const _SHINE_MOD_THEMED := Color(1.0, 1.0, 1.0, 120.0 / 255.0)
@onready var _shine_particle: CPUParticles2D = $Content/Bg/Bg/Particle/ShineAddLoop
@onready var _shine_mod_default: Color = _shine_particle.modulate


func on_create() -> void:
	StreakManager.streak_updated.connect(_on_streak_updated)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


func on_show(_params: Dictionary = {}) -> void:
	_refresh()


func _on_streak_updated(_data: StreakData) -> void:
	_refresh()


func _refresh() -> void:
	var checked_today: bool = not StreakManager.can_checkin_today()
	_state_checked.visible = checked_today
	_state_unchecked.visible = not checked_today

	_day_icon.refresh_group(checked_today)

	_day_icon.fit_uniform_height(
		_resolve_icon_height(checked_today), _resolve_icon_center(checked_today), true
	)

	_shine.visible = checked_today
	_shine_particle.modulate = _resolve_shine_modulate()
	_count.text = str(StreakManager.get_display_streak())


func _resolve_icon_height(_checked: bool) -> float:
	match StreakManager.get_effective_icon_group():
		DailystreakIconConfig.VALUE_WOOL:
			return 160.0
	return _ICON_BASE_HEIGHT


func _resolve_shine_modulate() -> Color:
	match StreakManager.get_effective_icon_group():
		DailystreakIconConfig.VALUE_SUN:
			return _shine_mod_default
	return _SHINE_MOD_THEMED


func _resolve_icon_center(_checked: bool) -> Vector2:
	return _ICON_CENTER


func reset_icon() -> void:
	_day_icon.reset_icon()
	_day_icon.refresh_group(false)


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.STREAK, self)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_ENTRY_CLICK)
	StreakPage.open_main()
