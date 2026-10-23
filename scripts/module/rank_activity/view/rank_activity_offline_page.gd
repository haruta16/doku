## 离线排行展示页；保留自身资料、倒计时和本地点赞交互，使用离线页面布局。

extends UIFrameWindow

const _RANK_CELL: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")

@onready var _header: BackAndSettingHeader = $MainVBox/TopBar/Header
@onready var _self_bar_slot: Control = $SelfBarSlot

@onready var _countdown_root: Control = $MainVBox/TopBar/Countdown
@onready var _countdown_label: Label = $MainVBox/TopBar/Countdown/Countdown/CountdownText

var _self_bar: Control = null


func on_create() -> void:
	_header.register_back_btn(_on_back_pressed)
	_header.register_setting_btn(_on_setting_pressed)


func on_show(_params: Dictionary = {}) -> void:
	_apply_countdown()
	var show_bar: bool = ABTestManager.rank_offline_bar.has_offline_bar()
	_self_bar_slot.visible = show_bar
	if not show_bar:
		return
	_ensure_self_bar()
	_refresh_self_bar()
	connect_managed(RankActivityManager.ranking_changed, _on_ranking_changed)


func on_hide() -> void:
	if _self_bar != null and is_instance_valid(_self_bar):
		destroy_child(_self_bar)
	_self_bar = null


func _apply_countdown() -> void:
	var show_countdown: bool = ABTestManager.rank_offline_bar.has_offline_countdown()
	_countdown_root.visible = show_countdown
	if not show_countdown:
		return
	_update_countdown()
	connect_managed(ClockTicker.second_tick, _update_countdown)


func _update_countdown() -> void:
	_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())


func _format_hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func _ensure_self_bar() -> void:
	if _self_bar != null and is_instance_valid(_self_bar):
		return
	_self_bar = create_child(_RANK_CELL, {})
	var cur: Node = _self_bar.get_parent()
	if cur != null:
		cur.remove_child(_self_bar)
	_self_bar_slot.add_child(_self_bar)

	_self_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_self_bar.apply_score_icon()

	_self_bar.set_show_chest(false)

	_self_bar.set_self_shadow(false)
	_self_bar.show_static()
	_self_bar.like_heart_pressed.connect(_on_self_like_pressed)


func _refresh_self_bar() -> void:
	if _self_bar == null or not is_instance_valid(_self_bar):
		return
	var info: PlayerInfo = ProfileService.get_player_info()

	var frozen_rank: int = maxi(0, RankActivityManager.get_last_seen_online_rank())
	_self_bar.set_entry(frozen_rank, true, info.nickname, RankActivityManager.get_collect_total())
	_self_bar.set_player(info)

	var show_pill: bool = RankOnlineHelper.should_show(info, RankOnlineHelper.window_sec_from_ab())
	_self_bar.set_online(show_pill, false, 0, true, true)
	_apply_self_like()


func _apply_self_like() -> void:
	if _self_bar == null or not is_instance_valid(_self_bar):
		return
	if not ABTestManager.rank_like_func.is_like_enabled():
		_self_bar.set_like_display(false)
		return
	var state: Dictionary = RankActivityManager.get_player_self_like_state()
	if not bool(state.get("valid", false)):
		_self_bar.set_like_display(true, 0, false, "")
		return
	_self_bar.set_like_display(
		true,
		int(state.get("heart_count", 0)),
		bool(state.get("liked_by_player", false)),
		RankActivityManager.SELF_LIKE_TARGET_ID
	)


func _on_self_like_pressed(_target_id: String) -> void:
	if not ABTestManager.rank_like_func.is_like_enabled():
		return
	var state: Dictionary = RankActivityManager.toggle_player_self_like()
	if not bool(state.get("valid", false)):
		return
	_self_bar.set_like_display(
		true,
		int(state.get("heart_count", 0)),
		bool(state.get("liked_by_player", false)),
		RankActivityManager.SELF_LIKE_TARGET_ID,
		true
	)


func _on_ranking_changed() -> void:
	if _self_bar == null or not is_instance_valid(_self_bar):
		return
	_self_bar.set_score(RankActivityManager.get_collect_total())


func on_escape() -> bool:
	_on_back_pressed()
	return true


func _on_back_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(UiName.RANK_ACTIVITY_OFFLINE)


func _on_setting_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CHALLENGE_INFO, self)
	UIManager.show_ui(UiName.RANK_ACTIVITY_HTP)


func get_dlg_name() -> String:
	return "rank_activity_offline"
