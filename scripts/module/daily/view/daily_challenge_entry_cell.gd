# 主页上的每日挑战入口格：一秒一跳，按 DailyEntryState 的三态切换三套子节点
extends UIChildWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _state_normal: Control = $DcEntryImg/StateNormal # 可玩态整块
@onready var _state_locked: Control = $DcEntryImg/StateLocked # 未解锁态整块
@onready var _state_done: Control = $DcEntryImg/StateDone # 已完成态整块
@onready var _normal_date: Label = $DcEntryImg/StateNormal/Jun3Txt # 可玩态：今天日期
@onready var _normal_time: Label = $DcEntryImg/StateNormal/CountdownGroup/Countdown/TimeTxt # 可玩态：今日剩余时间倒计时
@onready var _done_date: Label = $DcEntryImg/StateDone/Jun3Txt # 已完成态：日期
@onready var _done_time: Label = $DcEntryImg/StateDone/CountdownGroup/Countdown/TimeTxt # 已完成态：本次耗时
@onready var _done_rank: Label = $DcEntryImg/StateDone/ActionBtn/TOP90Txt # 已完成态：排名文案（TOP x%）
@onready var _unlock_label: Label = $DcEntryImg/StateLocked/LockGroup/UnlockAtLv21Txt # 未解锁态：解锁条件文案
@onready var _click_btn: Button = $ClickBtn # 整格点击按钮


# 注册 1 秒心跳刷新，并给点击按钮接上按下/抬起缩放反馈
func on_create() -> void:
	create_tick(1.0, _refresh)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


# 每次显示先刷一遍三态
func on_show(_params: Dictionary = {}) -> void:
	_refresh()


# 按当前状态只显示对应那一套，并填好该状态的文案
func _refresh() -> void:
	var s: int = DailyEntryState.compute_state()
	_state_normal.visible = s == DailyEntryState.State.NORMAL
	_state_locked.visible = s == DailyEntryState.State.LOCKED
	_state_done.visible = s == DailyEntryState.State.DONE
	match s:
		DailyEntryState.State.NORMAL:
			_normal_date.text = DailyEntryState.today_date_text()
			_normal_time.text = DailyEntryState.countdown_text()
		DailyEntryState.State.LOCKED:
			_unlock_label.text = tr("DAILY_CHALLENGE_UNLOCK_AT") % DailyEntryState.UNLOCK_LEVEL
		DailyEntryState.State.DONE:
			_done_date.text = DailyEntryState.today_date_text()
			_done_time.text = DailyEntryState.done_time_text()
			_done_rank.text = DailyEntryState.done_rank_text()


# 点击：埋点 + 震动后交给 DailyEntryState 决定是弹 Toast 还是进游戏
func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)

	DailyEntryState.handle_click(self)
