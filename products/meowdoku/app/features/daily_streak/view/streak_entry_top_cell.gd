## 顶部打卡入口：将打卡状态同步到顶部按钮与图标。
extends UIChildWindow

@onready var _icon_slot: Control = $Root/Content/IconSlot
@onready var _day_icon: StreakDayIcon = $Root/Content/IconSlot/DayIcon
@onready var _count_txt: Label = $Root/Content/CountTxt
@onready var _click_btn: Button = $ClickBtn


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

	_day_icon.refresh_group(checked_today)

	_icon_slot.custom_minimum_size = _day_icon.fit_design(70.0, Vector2.INF, true)
	_count_txt.text = str(StreakManager.get_display_streak())


func reset_icon() -> void:
	_day_icon.reset_icon()
	_day_icon.refresh_group(false)


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.STREAK, self)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_ENTRY_CLICK)
	StreakPage.open_main()
