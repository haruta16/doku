## 躲猫猫交互的异步编排：弹窗、激励广告、鱼飞行、排行榜收集与到期结算按顺序执行。
## 整个流程临时锁定首页布局和活动展示，结束后释放遮罩与展示锁，避免结算动画彼此打断。

class_name PeekabooFlow
extends RefCounted

const _AD_POSITION: String = Tracker.AdPos.PEEKABOO_REWARD

const _AD_WAIT_TIMEOUT_SEC: float = 60.0

const _AD_WAIT_CLOCK_SPAN: float = 3600.0

const _AD_REWARD_GRACE_SEC: float = 1.0

const BLOCKER_NAME: String = "_PeekabooBlocker"


## 进入外部展示锁并固定首页排行入口，执行整条异步交互；结束时统一清理遮罩和布局锁。
static func run(home: Node) -> void:
	RankActivityManager.begin_external_presentation()
	home.set_rank_layout_locked(true)
	var blocker: Control = _spawn_blocker(home)

	await _run_inner(home)

	if is_instance_valid(blocker):
		blocker.queue_free()

	home.set_rank_layout_locked(false)

	RankActivityManager.end_external_presentation()

	if is_instance_valid(home):
		home.refresh_peekaboo_cat()


static func _run_inner(home: Node) -> void:
	var click_st: Dictionary = PeekabooManager.get_cat_state()

	var prop_index: int = int(click_st.get("prop_index", 0))
	var pos_index: int = int(click_st.get("pos_index", 0))
	Tracker.track_btn_click(Tracker.peekaboo_cat_btn_for_prop(prop_index), home)

	var group: int = int(ABTestManager.peekaboo_cat.peek_value())
	var watched_ad: bool = false

	var offline: bool = RankOfflineOverlayHelper.is_offline_mode()
	var grants_at_click: bool = (
		PeekabooRules.grants_reward(RankActivityManager.get_state(), offline)
		and not bool(click_st.get("claimed_today", false))
	)
	if not grants_at_click:
		await _run_interaction_only(home, prop_index, pos_index)

		return

	if ABTestManager.peekaboo_cat.needs_ad_popup():
		var intent: String = await _run_confirm_popup(home)
		if intent != "ad" and intent != "plain":
			return
		if intent == "ad":
			if not await _watch_reward_ad(home):
				return
			watched_ad = true

	var st: Dictionary = PeekabooManager.get_cat_state()
	var grants: bool = (
		PeekabooRules.grants_reward(
			RankActivityManager.get_state(), RankOfflineOverlayHelper.is_offline_mode()
		)
		and not bool(st.get("claimed_today", false))
	)
	var amount: int = PeekabooRules.fish_count(group, watched_ad)

	if not grants or amount <= 0:
		await _run_interaction_only(home, prop_index, pos_index)

		return

	var before: int = RankActivityManager.get_collect_total()
	RankActivityManager.add_external_collect(amount)
	var gained: bool = RankActivityManager.get_collect_total() > before
	if not gained:
		await _run_interaction_only(home, prop_index, pos_index)

		return

	PeekabooManager.mark_claimed(int(Time.get_unix_time_from_system()))

	var old_rank: int = RankActivityManager.get_rank_for_score(before)
	var new_rank: int = RankActivityManager.get_player_rank()
	var advance: int = maxi(0, old_rank - new_rank)

	await _play_peek_out_and_fish(home, amount, prop_index, pos_index)

	if not is_instance_valid(home) or not home.is_showing():
		return

	var change_ui: StringName = (
		UiName.RANK_ACTIVITY_CHANGE_V2
		if ABTestManager.podium_per_game.is_list_podium_style()
		else UiName.RANK_ACTIVITY_CHANGE
	)

	(
		UIManager
		. show_ui(
			change_ui,
			{
				"score_increment": amount,
				"advance_places": advance,
				"suppress_settle_flight": true,
			}
		)
	)
	await UIManager.await_hidden(change_ui)

	await _run_settle_tail(home)


static func _run_settle_tail(home: Node) -> void:
	if RankActivityManager.get_state() != RankActivityData.State.SETTLING:
		return
	if not RankActivityManager.get_pending_reward().is_empty():
		RankActivityManager.claim_reward(true)

		await home.get_tree().process_frame
		await UIManager.await_hidden(UiName.AWARD)
		return
	var solo_shown: bool = await _run_end_solo_podium(home)
	if not solo_shown:
		RankActivityManager.notify_settlement_done()


static func _run_end_solo_podium(home: Node) -> bool:
	var pending: Dictionary = RankActivityManager.get_pending_end_solo_podium()
	if pending.is_empty():
		return false
	if not ABTestManager.podium_per_leaderboard.has_end_solo_podium():
		return false
	if not RankActivityManager.begin_end_solo_podium():
		return false
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": int(pending.get("rank", 4))})
	await UIManager.await_hidden(UiName.RANK_ACTIVITY_SOLO_PODIUM)
	RankActivityManager.complete_end_solo_podium(true)
	if not is_instance_valid(home):
		return true
	return true


static func _run_confirm_popup(home: Node) -> String:
	var ad_available: bool = await UniKitManager.is_reward_valid(AdPlacement.REWARD, _AD_POSITION)

	var res: Dictionary = {"intent": "", "done": false, "started": false}
	var body: Callable = func() -> void:
		res.started = true
		var page: UIFrameWindow = UIManager.show_ui(
			UiName.PEEKABOO_CONFIRM, {"ad_available": ad_available}
		)
		if page == null:
			res.intent = "close"
			res.done = true
			return
		res.intent = await _await_confirm_intent(home, page)
		await UIManager.await_hidden(UiName.PEEKABOO_CONFIRM)
		res.done = true
	home.enqueue_peekaboo_confirm_popup(body)
	while not res.done:
		if not is_instance_valid(home):
			return "close"

		if not bool(res.started) and not home.is_peekaboo_confirm_pending():
			return "close"
		await home.get_tree().process_frame
	return String(res.intent)


static func _await_confirm_intent(home: Node, page: Object) -> String:
	var res: Dictionary = {"intent": ""}
	var on_ad: Callable = func() -> void:
		if res.intent == "":
			res.intent = "ad"
	var on_plain: Callable = func() -> void:
		if res.intent == "":
			res.intent = "plain"
	var on_close: Callable = func() -> void:
		if res.intent == "":
			res.intent = "close"
	page.ad_requested.connect(on_ad)
	page.plain_requested.connect(on_plain)
	page.close_requested.connect(on_close)
	while res.intent == "":
		if not is_instance_valid(page) or not is_instance_valid(home):
			return "close"

		if not page.is_showing():
			res.intent = "close"
			break
		await home.get_tree().process_frame

	if page.ad_requested.is_connected(on_ad):
		page.ad_requested.disconnect(on_ad)
	if page.plain_requested.is_connected(on_plain):
		page.plain_requested.disconnect(on_plain)
	if page.close_requested.is_connected(on_close):
		page.close_requested.disconnect(on_close)
	return String(res.intent)


## 等待激励广告的结束结果并设置超时边界，防止原生广告回调缺失时流程永久悬挂。
static func _watch_reward_ad(host: Node) -> bool:
	var show_id: String = UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, _AD_POSITION)
	if not await UniKitManager.is_reward_ready(AdPlacement.REWARD, _AD_POSITION, show_id):
		Toast.popup("AD_TOAST_NOT_READY", host)
		return false

	var res: Dictionary = {"rewarded": false, "closed": false, "errored": false}
	var on_rewarded: Callable = func(pid: String) -> void:
		if pid == AdPlacement.REWARD:
			res.rewarded = true
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.REWARD:
			res.closed = true
	var on_error: Callable = func(pid: String, _msg: String) -> void:
		if pid == AdPlacement.REWARD:
			res.errored = true
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)
	UniKitManager.ad_error_occurred.connect(on_error, CONNECT_ONE_SHOT)
	UniKitManager.show_reward(AdPlacement.REWARD, _AD_POSITION, show_id)

	var clock: Tween = host.create_tween()
	clock.tween_interval(_AD_WAIT_CLOCK_SPAN)

	var closed_at: float = -1.0
	while not bool(res.rewarded):
		if not is_instance_valid(host):
			break

		if bool(res.errored):
			break
		if bool(res.closed):
			if closed_at < 0.0:
				closed_at = clock.get_total_elapsed_time()
			elif clock.get_total_elapsed_time() - closed_at >= _AD_REWARD_GRACE_SEC:
				break
			await host.get_tree().process_frame
			continue

		if clock.get_total_elapsed_time() >= _AD_WAIT_TIMEOUT_SEC:
			push_warning(
				(
					"[Peekaboo] 看广等待超时 %.0fs（场景时间）未收到 ad_rewarded / ad_closed，按未发奖收尾"
					% _AD_WAIT_TIMEOUT_SEC
				)
			)
			break
		await host.get_tree().process_frame

	var rescued_late_ms: float = -1.0
	if bool(res.rewarded) and closed_at >= 0.0 and clock.is_valid():
		rescued_late_ms = (clock.get_total_elapsed_time() - closed_at) * 1000.0
	if clock.is_valid():
		clock.kill()
	if UniKitManager.ad_rewarded.is_connected(on_rewarded):
		UniKitManager.ad_rewarded.disconnect(on_rewarded)
	if UniKitManager.ad_closed.is_connected(on_closed):
		UniKitManager.ad_closed.disconnect(on_closed)
	if UniKitManager.ad_error_occurred.is_connected(on_error):
		UniKitManager.ad_error_occurred.disconnect(on_error)

	if bool(res.rewarded) and closed_at >= 0.0:
		print("[Peekaboo] 奖励被宽限期救回：reward 晚于 close %.0fms（场景时间）" % rescued_late_ms)
		push_error(
			(
				"PeekabooFlow: reward ad closed before rewarded, fish reward rescued, position=%s"
				% _AD_POSITION
			)
		)
	return bool(res.rewarded)


static func _run_interaction_only(home: Node, prop_index: int, pos_index: int) -> void:
	PeekabooManager.mark_interacted()
	await _play_peek_out_and_fish(home, 0, prop_index, pos_index)


const _FISH_SCENE: PackedScene = preload("res://scripts/module/peekaboo/ui/peekaboo_fish.tscn")

const _FISH_LEFT_SIDE_POS_INDEXES: Array[int] = [0, 2, 3]

const _FISH_ARRIVE_TO_CHANGE_SEC: float = 0.3666667

const _FISH_SPAWN_DELAY_SEC: float = 0.1

const _FISH_SCALE: float = 0.75

const _FISH_ORIGIN_NUDGE_Y: float = -15.0


static func _play_peek_out_and_fish(
	home: Node, count: int, prop_index: int, pos_index: int
) -> void:
	if not is_instance_valid(home):
		return

	var peek_dur: float = 0.0
	var cell: Control = home.get_peekaboo_cell()
	if cell != null and cell.has_method("play_peek_out"):
		peek_dur = float(cell.call("play_peek_out", prop_index))

	var fish: Node2D = null
	if count > 0:
		if _FISH_SPAWN_DELAY_SEC > 0.0:
			var delay_tween: Tween = (home as Node).create_tween()
			delay_tween.tween_interval(_FISH_SPAWN_DELAY_SEC)
			await delay_tween.finished
			if not is_instance_valid(home):
				return
		fish = _spawn_fish(home, count, pos_index)

	if fish != null:
		await _await_fish_arrived_then_settle(home, fish, count)
		return
	if peek_dur > 0.0 and is_instance_valid(home):
		var wait_tween: Tween = (home as Node).create_tween()
		wait_tween.tween_interval(peek_dur)
		await wait_tween.finished


static func _spawn_fish(home: Node, count: int, pos_index: int) -> Node2D:
	var target: Vector2 = home.get_rank_entry_center()
	if target == Vector2.ZERO:
		push_warning("[PeekabooFlow] rank 入口落点取不到，跳过鱼干飞入段（分已入账，不影响数值）")
		return null
	var layer: Control = home.get_peekaboo_fly_layer()
	if layer == null:
		return null
	var source: Vector2 = home.get_peekaboo_center()
	if source == Vector2.ZERO:
		source = target

	var fish: Node2D = _FISH_SCENE.instantiate() as Node2D
	if fish == null:
		return null
	fish.scale = Vector2(_FISH_SCALE, _FISH_SCALE)
	layer.add_child(fish)

	fish.global_position = (
		source - _fish_origin_offset(fish) * _FISH_SCALE + Vector2(0.0, _FISH_ORIGIN_NUDGE_Y)
	)
	var side_left: bool = _FISH_LEFT_SIDE_POS_INDEXES.has(pos_index)
	fish.call(
		"play",
		side_left,
		count,
		target,
		_shape_family_for_home(home),
		_flight_duration_for(home, source, target)
	)
	return fish


static func _fish_origin_offset(fish: Node2D) -> Vector2:
	var host: Control = fish.get_node_or_null("Control") as Control
	if host == null:
		return Vector2.ZERO
	var first_fish: Control = host.get_node_or_null("Fish1") as Control
	if first_fish == null:
		return host.position
	var ratio: Vector2 = first_fish.pivot_offset_ratio
	if ratio == Vector2.ZERO:
		ratio = Vector2(0.5, 0.5)
	return host.position + first_fish.position + first_fish.size * ratio


static func _flight_duration_for(home: Node, source: Vector2, target: Vector2) -> float:
	var distance: float = source.distance_to(target)
	if not home.has_method("get_peekaboo_pos_centers"):
		return FishFlightCurve.FLIGHT_DURATION_FAR_SEC
	var centers: PackedVector2Array = home.call("get_peekaboo_pos_centers")
	if centers.size() < 2:
		return FishFlightCurve.FLIGHT_DURATION_FAR_SEC
	var near_distance: float = INF
	var far_distance: float = 0.0
	for c in centers:
		var d: float = c.distance_to(target)
		near_distance = minf(near_distance, d)
		far_distance = maxf(far_distance, d)
	return FishFlightCurve.flight_duration_for_distance(distance, near_distance, far_distance)


## 等待奖励鱼抵达后才继续结算演出；收集分数此前已入账，这里协调的是可见表现的先后。
static func _await_fish_arrived_then_settle(home: Node, fish: Node2D, count: int) -> void:
	fish.connect(
		"first_fish_arrived",
		func() -> void:
			if not is_instance_valid(home):
				return
			var rank_cell: Control = home.get_rank_entry_cell()
			if rank_cell != null and rank_cell.has_method("play_peekaboo_feedback"):
				rank_cell.call("play_peekaboo_feedback", count),
		CONNECT_ONE_SHOT
	)
	fish.connect(
		"all_fish_arrived",
		func() -> void:
			if is_instance_valid(fish):
				fish.queue_free(),
		CONNECT_ONE_SHOT
	)
	await fish.last_fish_arrived
	if not is_instance_valid(home):
		return

	var settle_tween: Tween = (home as Node).create_tween()
	settle_tween.tween_interval(_FISH_ARRIVE_TO_CHANGE_SEC)
	await settle_tween.finished


static func _shape_family_for_home(home: Node) -> StringName:
	if home.has_method("is_rank_entry_left_side") and bool(home.call("is_rank_entry_left_side")):
		return FishFlightCurve.FAMILY_LAYOUT_2
	return FishFlightCurve.FAMILY_LAYOUT_1


static func _spawn_blocker(home: Node) -> Control:
	if not is_instance_valid(home):
		return null
	var b := Control.new()
	b.name = BLOCKER_NAME
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	home.add_child(b)
	return b
