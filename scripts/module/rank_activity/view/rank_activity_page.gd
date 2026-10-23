## 排行榜主页；组合虚拟列表、前三名领奖台与屏幕边缘的自身浮动行。
## 快照负责数据一致性，列表适配器负责节点复用；领奖触发延后执行，避免在当前 UI 回调中重入切页。

extends UIFrameWindow

const _RANK_CELL: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")
const _AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _PODIUM_AVATAR_SCALE: float = 210.0 / 185.0

const _PODIUM_COUNT: int = 3

const _PODIUM_AREA_HEIGHT_CONTROL: float = 521.0
const _PODIUM_AREA_HEIGHT_WITH_TAG: float = 542.0

const _PODIUM_TAG_TOP: float = 498.0

@onready var _podium: Control = $MainVBox/PodiumArea/Top3Podium
@onready var _podium_area: Control = $MainVBox/PodiumArea
@onready var _list: VirtualList = $MainVBox/ListGroup/VirtualList
@onready var _float_row: Control = $FloatRow
@onready var _countdown_label: Label = $MainVBox/TopBar/Countdown/Countdown/CountdownText
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _header: BackAndSettingHeader = $MainVBox/TopBar/Header

var _adapter: RankVirtualListAdapter = null
var _floating: RankFloatingRowController = RankFloatingRowController.new()
var _floating_cell: RankCell = null
var _snapshots: Array[Dictionary] = []
var _self_snapshot: Dictionary = {}

var _snapshot_namespace: String = ""
var _snapshot_epoch: int = 0
var _display_generation: int = 0
var _intro_pending: bool = false
var _intro_timers: Dictionary = {}
var _float_intro_timers: Array[Timer] = []

var _podium_avatars: Array[Control] = []

var _podium_frame_snapshot_counts: Array[int] = []

var _self_info_opening: bool = false

var _reward_flow_active: bool = false

var _showing_finished_period: bool = false


func on_create() -> void:
	RankActivityManager.period_opened.connect(_on_display_period_opened)
	GameState.all_data_reset.connect(_on_display_data_reset)
	_adapter = RankVirtualListAdapter.new(self)
	_list.set_active(false)
	_list.set_adapter(_adapter)

	_header.register_back_btn(_on_back_pressed)
	_header.register_setting_btn(_on_setting_pressed)

	move_child(_float_row, get_child_count() - 1)
	_center_decor_for_wide()


func _center_decor_for_wide() -> void:
	await get_tree().process_frame
	var margin: float = (get_viewport_rect().size.x - 1080.0) * 0.5
	if margin <= 0.5:
		return
	for p: Node2D in [$Star, $Star2]:
		if is_instance_valid(p):
			p.position.x += margin


## 刷新排行快照和领奖台，连接当前展示所需的信号，并检查是否需要进入领奖流程。
func on_show(_params: Dictionary = {}) -> void:
	_showing_finished_period = false

	RankActivityManager.set_online_window_sec(RankOnlineHelper.window_sec_from_ab())

	var helper: ScrollDragHelper = ScrollDragHelper.attach(_list.scroll, true)
	helper.elastic_max_overscroll = 0.0
	connect_managed(helper.interaction_cancelled, _on_list_interaction_cancelled)
	connect_managed(RankActivityManager.ranking_changed, _on_ranking_changed)

	connect_managed(ProfileService.avatar_frame_changed, _on_profile_display_changed)

	connect_managed(ClockTicker.second_tick, _update_countdown)
	_cancel_intro()
	_list.set_active(false)
	_floating.teardown()
	_ensure_floating_cell()
	_floating_cell.reset_for_reuse()
	_floating_cell.prepare_intro()
	_floating_cell.show()
	_floating.setup(_list, _floating_cell)
	connect_managed(_list.layout_updated, _on_list_updated)
	connect_managed(_list.visible_range_changed, _on_list_updated)
	connect_managed(_list.viewport_updated, _on_list_updated)
	_intro_pending = true
	_rebuild()
	_list.scroll_to_offset(0.0)
	_list.set_active(true)
	AnimUtil.play(_anim, &"Appear")
	_on_list_updated.call_deferred()
	_attach_self_avatar_click()

	connect_managed(RankActivityManager.state_changed, _on_rank_state_changed)

	connect_managed(RankActivityManager.settle_ready, _on_rank_settle_ready)
	_reward_flow_active = false
	if not RankActivityManager.get_pending_reward().is_empty():
		_reward_flow_active = true

		_claim_reward_deferred.call_deferred()


## 把领奖放到延迟调用，避免排行榜信号正在派发时同步销毁或切换当前页面。
func _claim_reward_deferred() -> void:
	if not is_showing():
		return
	if RankActivityManager.get_pending_reward().is_empty():
		return
	RankActivityManager.claim_reward()


func _on_rank_state_changed(state: int) -> void:
	if not is_showing():
		return
	if state == RankActivityData.State.NOT_OPENED:
		_showing_finished_period = true

		if _reward_flow_active:
			UIManager.hide_ui(UiName.RANK_ACTIVITY_PAGE)
	elif state == RankActivityData.State.SETTLING:
		if not RankActivityManager.get_pending_reward().is_empty():
			_reward_flow_active = true
			RankActivityManager.claim_reward()


func _on_rank_settle_ready(_result: Dictionary) -> void:
	await get_tree().process_frame
	if not is_showing():
		return
	var pending: Dictionary = RankActivityManager.get_pending_end_solo_podium()
	if pending.is_empty():
		return
	if not ABTestManager.podium_per_leaderboard.has_end_solo_podium():
		RankActivityManager.notify_settlement_done()
		return
	if not RankActivityManager.begin_end_solo_podium():
		return

	_reward_flow_active = true
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": int(pending.get("rank", 4))})
	await UIManager.await_hidden(UiName.RANK_ACTIVITY_SOLO_PODIUM)

	RankActivityManager.complete_end_solo_podium(true)


## 停止页面表现并清理临时交互，使再次显示时从业务快照重建而不沿用旧动画。
func on_hide() -> void:
	_cancel_intro()
	_cancel_external_press()
	_list.set_active(false)
	_floating.teardown()
	_floating_cell.reset_for_reuse()
	_floating_cell.hide()
	_clear_podium_avatars()


func on_stack_bottom() -> void:
	_cancel_intro()
	_cancel_external_press()
	_list.set_active(false)
	_floating_cell.reset_for_reuse()
	_floating_cell.hide()


func on_stack_top() -> void:
	if not is_showing():
		return
	if _showing_finished_period:
		_on_profile_display_changed()
		RankRowSnapshot.apply(_floating_cell, _self_snapshot, true)
	else:
		_refresh_snapshot(false)
	_floating_cell.show_static()
	_floating_cell.show()
	_list.set_active(true)
	_on_list_updated.call_deferred()


func on_destroy() -> void:
	RankActivityManager.period_opened.disconnect(_on_display_period_opened)
	GameState.all_data_reset.disconnect(_on_display_data_reset)
	_cancel_intro()
	_floating.teardown()
	_list.set_adapter(null)
	if is_instance_valid(_floating_cell):
		destroy_child(_floating_cell)
	_floating_cell = null


func _rebuild() -> void:
	_refresh_snapshot(false)
	_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())


## 把本次 RankInfo 转成行快照，通过修订号让虚拟列表只更新发生变化的行。
func _refresh_snapshot(preserve_anchor: bool) -> void:
	RankActivityManager.record_seen_online_rank()
	var infos: Array = RankActivityManager.get_rank_infos()
	if not infos.is_empty():
		if _snapshot_namespace.is_empty():
			_snapshot_namespace = (
				"period:%d:%d" % [RankActivityManager.get_period_count(), _snapshot_epoch]
			)
		var previous: Dictionary = {}
		for snapshot: Dictionary in _snapshots:
			previous[snapshot.key] = snapshot
		var updated: Array[Dictionary] = []
		_self_snapshot = {}
		for info: RankInfo in infos:
			var snapshot: Dictionary = RankRowSnapshot.from_info(
				info, _online_window_sec(), _snapshot_namespace
			)
			var old: Dictionary = previous.get(snapshot.key, {})
			if not old.is_empty() and RankRowSnapshot.same_payload(old, snapshot):
				snapshot = old
			else:
				snapshot = RankRowSnapshot.with_revision(snapshot, int(old.get("revision", 0)) + 1)
			updated.append(snapshot)
			if snapshot.is_self:
				_self_snapshot = snapshot
		_snapshots = updated
	if _self_snapshot.is_empty():
		var fallback: RankInfo = RankInfo.new()
		fallback.player_info = ProfileService.get_player_info()
		fallback.score = RankActivityManager.get_collect_total()
		if _snapshot_namespace.is_empty():
			_snapshot_namespace = (
				"period:%d:%d" % [RankActivityManager.get_period_count(), _snapshot_epoch]
			)
		_self_snapshot = RankRowSnapshot.from_info(
			fallback, _online_window_sec(), _snapshot_namespace
		)
	_adapter.snapshots = _snapshots
	_list.reload(preserve_anchor)
	var podium_infos: Array[RankInfo] = []
	for snapshot: Dictionary in _snapshots:
		if snapshot.rank > _PODIUM_COUNT:
			continue
		var info: RankInfo = RankInfo.new()
		info.player_info = PlayerInfo.from_dict(snapshot.player)
		info.rank = snapshot.rank
		info.score = snapshot.score
		info.idle_sec = snapshot.idle_sec
		info.next_score_sec = 0 if snapshot.online else 2147483647
		podium_infos.append(info)
	_populate_podium_refresh(podium_infos)
	RankRowSnapshot.apply(_floating_cell, _self_snapshot, true)
	if not _intro_pending:
		_floating_cell.show_static()
	_attach_self_avatar_click()


func _on_display_period_opened(_period_count: int) -> void:
	_snapshot_epoch += 1
	_snapshot_namespace = ""


func _on_display_data_reset() -> void:
	_snapshot_epoch += 1
	_snapshot_namespace = ""


func _play_intro() -> void:
	_intro_pending = false
	var generation: int = _display_generation
	var bindings: Array[VirtualListBinding] = _list.get_visible_bindings()
	var self_delay: float = 0.3
	for ordinal in bindings.size():
		var binding: VirtualListBinding = bindings[ordinal]
		var delay: float = 0.06 + 0.05 * ordinal
		(binding.get_cell() as RankCell).prepare_intro()
		if binding.key == _self_snapshot.key:
			self_delay = delay
		_intro_timers[binding.generation] = create_countdown(delay, func() -> void:
			_intro_timers.erase(binding.generation)
			if generation == _display_generation and _list.is_binding_current(binding):
				(binding.get_cell() as RankCell).play_intro(&"Appear1"))
	_floating_cell.prepare_intro()

	var float_delay: float = 0.3 if _floating.is_at_edge() else self_delay
	_float_intro_timers.append(create_countdown(float_delay, func() -> void:
		if generation == _display_generation:
			var animation: StringName = &"Appear2" if _floating.is_at_edge() else &"Appear1"
			_floating_cell.play_intro(animation)))


func cancel_row_intro(binding: VirtualListBinding) -> void:
	var timer: Timer = _intro_timers.get(binding.generation)
	if is_instance_valid(timer):
		remove_timer(timer)
	_intro_timers.erase(binding.generation)


func _cancel_intro() -> void:
	_display_generation += 1
	_intro_pending = false
	var timers: Array = _intro_timers.values()
	for timer: Timer in timers:
		if is_instance_valid(timer):
			remove_timer(timer)
	_intro_timers.clear()
	for timer: Timer in _float_intro_timers:
		if is_instance_valid(timer):
			remove_timer(timer)
	_float_intro_timers.clear()


func _ensure_floating_cell() -> void:
	if is_instance_valid(_floating_cell):
		return
	_floating_cell = create_child(_RANK_CELL) as RankCell
	_floating_cell.reparent(_float_row, false)
	initialize_dynamic_widget(_floating_cell)


func _on_list_updated() -> void:
	if _self_snapshot.is_empty():
		return
	_floating.sync(_self_snapshot.key)
	if _intro_pending and not _list.get_visible_bindings().is_empty():
		_play_intro()


func _on_list_interaction_cancelled() -> void:
	var helper: ScrollDragHelper = ScrollDragHelper.attach(_list.scroll, true)
	helper.cancel_pressed_interaction(_floating_cell)


## 列表交互被取消时同步清掉外部浮动行的按压态，避免复用行保留一次未完成点击。
func _cancel_external_press() -> void:
	var helper: ScrollDragHelper = ScrollDragHelper.attach(_list.scroll, true)
	helper.cancel_pressed_interaction(_floating_cell)
	helper.cancel_pressed_interaction(_podium)


func _populate_podium(infos: Array) -> void:
	_podium.set_show_box(true)
	_podium_avatars.resize(_PODIUM_COUNT)
	_podium_frame_snapshot_counts.resize(_PODIUM_COUNT)
	_podium_frame_snapshot_counts.fill(-1)
	var by_rank: Dictionary = {}
	for info: RankInfo in infos:
		if info.rank >= 1 and info.rank <= _PODIUM_COUNT:
			by_rank[info.rank] = info
	var window_sec: int = _online_window_sec()

	if _podium_area != null:
		_podium_area.custom_minimum_size.y = (
			_PODIUM_AREA_HEIGHT_WITH_TAG if window_sec > 0 else _PODIUM_AREA_HEIGHT_CONTROL
		)

	_podium.set_online_layout(window_sec > 0, _PODIUM_TAG_TOP)
	for r in range(1, _PODIUM_COUNT + 1):
		var info: RankInfo = by_rank.get(r, null)
		if info == null:
			_podium.apply(r, "", 0)
			_podium.apply_online(r, false, false, 0)
			_apply_podium_like_display(r, null)
			continue
		var player: PlayerInfo = info.player_info
		_podium.apply(r, _display_name(player), info.score)

		_podium.apply_online(
			r,
			RankOnlineHelper.should_show(player, window_sec),
			_is_online(info.next_score_sec, window_sec),
			info.idle_sec,
			info.is_self()
		)
		_apply_podium_like_display(r, info)
		var mount: Control = _podium.get_avatar_mount(r)
		if mount != null and player != null:
			var avatar: Control = create_child(_AVATAR_CELL, {})
			_mount(avatar, mount)
			avatar.apply_player_info(player)

			var avatar_scale: float = (
				(mount.size.x / 185.0) if mount.size.x > 0.0 else _PODIUM_AVATAR_SCALE
			)
			avatar.scale = Vector2(avatar_scale, avatar_scale)
			avatar.pivot_offset = avatar.size * 0.5
			avatar.position = mount.size * 0.5 - avatar.pivot_offset
			_podium_avatars[r - 1] = avatar
			_podium_frame_snapshot_counts[r - 1] = (
				player.frame.acquired_count if player.frame != null else -1
			)


func _online_window_sec() -> int:
	return RankActivityManager.get_online_window_sec()


func _is_online(next_score_sec: int, window_sec: int) -> bool:
	return RankOnlineHelper.is_online(next_score_sec, window_sec)


func _apply_podium_like_display(rank: int, _info: RankInfo) -> void:
	_podium.set_like_display(rank, false)


func _on_profile_display_changed() -> void:
	if _self_snapshot.is_empty():
		return
	_replace_self_player(ProfileService.get_player_info())


func _apply_self_frame(frame_id: int, form: int, count: int) -> void:
	if _self_snapshot.is_empty():
		return
	var player: PlayerInfo = PlayerInfo.from_dict(_self_snapshot.player)
	player.frame = AvatarFrame.new(frame_id, count, form)
	_replace_self_player(player)


func _replace_self_player(player: PlayerInfo) -> void:
	var updated: Dictionary = RankRowSnapshot.with_player(_self_snapshot, player)
	if updated == _self_snapshot:
		return
	_self_snapshot = updated
	for index in _snapshots.size():
		if _snapshots[index].is_self:
			_snapshots[index] = _self_snapshot
			_adapter.snapshots = _snapshots
			_list.refresh_item(index)
	RankRowSnapshot.apply(_floating_cell, _self_snapshot, true)
	_floating_cell.show_static()
	var rank: int = _self_snapshot.rank
	if has_podium_avatar(rank):
		var avatar: Control = _podium_avatars[rank - 1]
		avatar.apply_player_info(PlayerInfo.from_dict(_self_snapshot.player))
		_podium.apply(rank, player.nickname, _self_snapshot.score)
		_podium_frame_snapshot_counts[rank - 1] = player.frame.acquired_count
	_attach_self_avatar_click()


func _on_ranking_changed() -> void:
	if _showing_finished_period:
		_on_profile_display_changed()
		return
	_refresh_snapshot(true)


func _populate_podium_refresh(infos: Array) -> void:
	_clear_podium_avatars()
	_populate_podium(infos)


func _clear_podium_avatars() -> void:
	for a in _podium_avatars:
		if is_instance_valid(a):
			destroy_child(a)
	_podium_avatars.clear()
	_podium_frame_snapshot_counts.clear()


func has_podium_avatar(rank: int) -> bool:
	var idx: int = rank - 1
	if idx < 0 or idx >= _podium_avatars.size():
		return false
	return is_instance_valid(_podium_avatars[idx])


func get_podium_avatar_center(rank: int) -> Vector2:
	var idx: int = rank - 1
	if idx < 0 or idx >= _podium_avatars.size():
		return Vector2.ZERO
	var avatar: Control = _podium_avatars[idx]
	if avatar == null or not is_instance_valid(avatar):
		return Vector2.ZERO
	var avatar_scale: Vector2 = avatar.get_global_transform().get_scale()
	return avatar.global_position + avatar.size * avatar_scale / 2.0


func set_podium_frame_form(rank: int, frame_id: int, form: int, count: int = -1) -> void:
	var idx: int = rank - 1
	if idx < 0 or idx >= _podium_avatars.size():
		return
	var avatar: Control = _podium_avatars[idx]
	if avatar == null or not is_instance_valid(avatar):
		return
	var snapshot: int = (
		_podium_frame_snapshot_counts[idx] if idx < _podium_frame_snapshot_counts.size() else -1
	)
	avatar.set_frame(frame_id, form)
	avatar.set_count(count if count >= 0 else snapshot)

	if rank == 1:
		_apply_self_frame(frame_id, form, count if count >= 0 else snapshot)


func _update_countdown() -> void:
	var remaining: int = 0 if _showing_finished_period else RankActivityManager.get_remaining_sec()
	_countdown_label.text = _format_hms(remaining)


func _display_name(pinfo: PlayerInfo) -> String:
	return pinfo.nickname if pinfo != null else ""


func _mount(cell: Control, parent: Control) -> void:
	var cur: Node = cell.get_parent()
	if cur == parent:
		return
	if cur != null:
		cur.remove_child(cell)
	parent.add_child(cell)


func _format_hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func _resolve_self_avatars() -> Array[Control]:
	var result: Array[Control] = []
	if _self_snapshot.is_empty():
		return result

	var rank: int = _self_snapshot.rank
	if rank >= 1 and rank <= _PODIUM_COUNT:
		var idx: int = rank - 1
		if idx < _podium_avatars.size() and is_instance_valid(_podium_avatars[idx]):
			result.append(_podium_avatars[idx])
	if is_instance_valid(_floating_cell) and _floating_cell.visible:
		var avatar: Control = _floating_cell.get_avatar_cell()
		if avatar != null:
			result.append(avatar)
	return result


func _attach_self_avatar_click() -> void:
	var targets: Array[Control] = _resolve_self_avatars()
	for target: Control in targets:
		if target.has_node("SelfInfoButton"):
			continue
		var button := Button.new()
		button.name = "SelfInfoButton"
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.self_modulate = Color(1, 1, 1, 0)
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		target.add_child(button)
		button.pressed.connect(_on_self_avatar_pressed)
		initialize_dynamic_widget(button)


func get_scr_name() -> String:
	return Tracker.Scr.CHALLENGE_RANK


func _on_self_avatar_pressed() -> void:
	if (
		_self_info_opening
		or _showing_finished_period
		or RankActivityManager.get_remaining_sec() <= 0
	):
		return
	_self_info_opening = true
	Tracker.track_btn_click(Tracker.Btn.SELF_INFO, self)
	var profile: UIFrameWindow = UIManager.show_ui(UiName.PROFILE)
	if profile == null:
		_self_info_opening = false
		return
	await UIManager.await_hidden(UiName.PROFILE)
	_self_info_opening = false
	if not is_showing():
		return
	_on_profile_display_changed()


func _on_back_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(UiName.RANK_ACTIVITY_PAGE)


func on_escape() -> bool:
	_on_back_pressed()
	return true


func _on_cta_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.PLAY, self)
	UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
	var home := UIManager.get_ui(UiName.HOME)
	if home != null and home.is_showing():
		UIManager.hide_ui(UiName.HOME)
	UIManager.hide_ui(UiName.RANK_ACTIVITY_PAGE)


func _on_setting_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CHALLENGE_INFO, self)
	UIManager.show_ui(UiName.RANK_ACTIVITY_HTP)
