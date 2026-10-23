## 常规打卡入口：监听打卡数据变化，刷新图标与点击入口。
extends UIChildWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _streak_entry_img: Control = $StreakEntryImg # 入口图标
@onready var _streak_txt: Label = $StreakTxt # 「连续打卡」标题文字
@onready var _count_badge: Control = $CountBadge # 天数气泡
@onready var _click_btn: Button = $ClickBtn # 整格点击按钮

@onready var _state_checked: Control = $StreakEntryImg/StateChecked # 已打卡的图标状态
@onready var _state_unchecked: Control = $StreakEntryImg/StateUnchecked # 未打卡的图标状态

@onready var _shine: Control = $StreakEntryImg/Visual

const _SHINE_MOD_THEMED := Color(1.0, 1.0, 1.0, 120.0 / 255.0)
@onready var _shine_particle: CPUParticles2D = $StreakEntryImg/Visual/ShineAddLoop
@onready var _shine_mod_default: Color = _shine_particle.modulate

const _ICON_BASE_HEIGHT: float = 296.96
const _ICON_CENTER := Vector2(229.0, 278.0)

@onready var _day_icon: StreakDayIcon = $StreakEntryImg/DayIcon
@onready var _count_txt: Label = $CountBadge/CountTxt # 气泡里的天数数字


## 订阅打卡数据变化，并给按钮接上按下/抬起缩放
func on_create() -> void:
	StreakManager.streak_updated.connect(_on_streak_updated)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


## 每次显示先刷一遍
func on_show(_params: Dictionary = {}) -> void:
	_refresh()


## 隐藏时不需要额外处理
func on_hide() -> void:
	pass


## 销毁时不需要额外处理
func on_destroy() -> void:
	pass


## 打卡数据有变化（打卡 / 断签 / 重置）时重刷
func _on_streak_updated(_data: StreakData) -> void:
	_refresh()


func _refresh() -> void:
	var checked_today: bool = not StreakManager.can_checkin_today()
	_state_checked.visible = checked_today
	_state_unchecked.visible = not checked_today

	_shine.visible = checked_today
	_shine_particle.modulate = _resolve_shine_modulate()

	_day_icon.refresh_group(checked_today)

	_day_icon.fit_uniform_height(
		_resolve_icon_height(checked_today), _resolve_icon_center(checked_today), true
	)
	_count_txt.text = str(StreakManager.get_display_streak())


func _resolve_icon_height(_checked: bool) -> float:
	match StreakManager.get_effective_icon_group():
		DailystreakIconConfig.VALUE_WOOL:
			return 299.0
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
