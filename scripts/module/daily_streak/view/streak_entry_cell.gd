# 主页上的连续打卡入口：显示今天打没打卡 + 当前连续天数，点击进打卡页
extends UIChildWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _streak_entry_img: Control = $StreakEntryImg # 入口图标
@onready var _streak_txt: Label = $StreakTxt # 「连续打卡」标题文字
@onready var _count_badge: Control = $CountBadge # 天数气泡
@onready var _click_btn: Button = $ClickBtn # 整格点击按钮

@onready var _state_checked: Control = $StreakEntryImg/StateChecked # 已打卡的图标状态
@onready var _state_unchecked: Control = $StreakEntryImg/StateUnchecked # 未打卡的图标状态
@onready var _count_txt: Label = $CountBadge/CountTxt # 气泡里的天数数字


# 订阅打卡数据变化，并给按钮接上按下/抬起缩放
func on_create() -> void:
	StreakManager.streak_updated.connect(_on_streak_updated)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


# 每次显示先刷一遍
func on_show(_params: Dictionary = {}) -> void:
	_refresh()


# 隐藏时不需要额外处理
func on_hide() -> void:
	pass


# 销毁时不需要额外处理
func on_destroy() -> void:
	pass


# 打卡数据有变化（打卡 / 断签 / 重置）时重刷
func _on_streak_updated(_data: StreakData) -> void:
	_refresh()


# 「今天已打卡」= 今天不能再打卡；天数取当前连续天数
func _refresh() -> void:
	var checked_today: bool = not StreakManager.can_checkin_today()
	_state_checked.visible = checked_today
	_state_unchecked.visible = not checked_today
	_count_txt.text = str(StreakManager.get_data().current_streak)


# 点击：埋点 + 震动后以常规态打开打卡页
func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.STREAK, self)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
	StreakPage.open_main()
