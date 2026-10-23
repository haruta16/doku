## 每日挑战首页入口：刷新可玩状态、倒计时和参与人数，并处理点击分流。
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

@onready var _players_row: DcPlayersJoinedRow = $PlayersJoinedRow


func on_create() -> void:
	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


func on_show(_params: Dictionary = {}) -> void:
	connect_managed(ClockTicker.second_tick, _refresh)
	roll_players_avatars()

	_refresh()


func _refresh() -> void:
	var s: int = DailyEntryState.compute_state()
	_state_normal.visible = s == DailyEntryState.State.NORMAL
	_state_locked.visible = s == DailyEntryState.State.LOCKED

	_state_done.visible = DailyEntryState.is_done_like(s)
	match s:
		DailyEntryState.State.NORMAL:
			_normal_date.text = DailyEntryState.today_date_text()
			_normal_time.text = DailyEntryState.countdown_text()
		DailyEntryState.State.LOCKED:
			_unlock_label.text = tr("DAILY_CHALLENGE_UNLOCK_AT") % DailyEntryState.UNLOCK_LEVEL
		DailyEntryState.State.DONE, DailyEntryState.State.REPLAY:
			_done_date.text = DailyEntryState.today_date_text()
			_done_time.text = DailyEntryState.done_time_text()
			_done_rank.text = DailyEntryState.done_rank_text()

	_players_row.refresh(s)


func roll_players_avatars() -> void:
	_players_row.roll_avatars()


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)
	VibrateManager.play_at(VibrateManager.Pos.DAILY_ENTRY_CLICK)

	DailyEntryState.handle_click(
		self,
		func() -> void:
			UIManager.show_ui(UiName.DAILY_GAME, {})
			UIManager.hide_ui(UiName.HOME),
		func() -> void:
			DcReplayFlow.open_confirm(
				self,
				func() -> void:
					UIManager.show_ui(UiName.DAILY_GAME, DcReplayFlow.enter_params())
					UIManager.hide_ui(UiName.HOME)
			)
	)
