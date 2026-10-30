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
static var _active_flows: Dictionary = {}

static func run(home: Node) -> void:
	cancel(home)
	var flow: Dictionary = {"home": weakref(home), "revision": home.get_presentation_revision(),
		"tree": home.get_tree(), "id": home.get_instance_id(), "released": false}
	_active_flows[flow.id] = flow
	RankActivityManager.begin_external_presentation()
	home.set_rank_layout_locked(true)
	flow["blocker"] = weakref(_spawn_blocker(home))
	await _run_inner(home, flow)
	_release(flow)

static func cancel(home: Node) -> void:
	if not is_instance_valid(home):
		return
	var flow: Dictionary = _active_flows.get(home.get_instance_id(), {})
	if not flow.is_empty():
		_release(flow)

static func _release(flow: Dictionary) -> void:
	if flow.get("released", true):
		return
	flow.released = true
	if is_same(_active_flows.get(flow.id), flow):
		_active_flows.erase(flow.id)
	var blocker: Object = flow.get("blocker").get_ref() if flow.has("blocker") else null
	if is_instance_valid(blocker):
		blocker.queue_free()
	var home: Object = flow.home.get_ref()
	if is_instance_valid(home) and home.get_presentation_revision() == flow.revision:
		home.set_rank_layout_locked(false)
		home.refresh_peekaboo_cat()
	RankActivityManager.end_external_presentation()

static func _valid(flow: Dictionary) -> bool:
	if flow.get("released", true):
		return false
	var home: Object = flow.home.get_ref()
	return is_instance_valid(home) and home.is_inside_tree() and home.is_showing() and home.get_presentation_revision() == flow.revision

static func _delay(flow: Dictionary, seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while _valid(flow) and Time.get_ticks_msec() < until:
		await flow.tree.process_frame

static func _popup_hidden(name: StringName, flow: Dictionary) -> void:
	var page: UIFrameWindow = UIManager.get_ui(name)
	if page == null:
		return
	var revision: int = page.get_presentation_revision()
	while _valid(flow) and is_instance_valid(page) and page.is_showing() and page.get_presentation_revision() == revision:
		await flow.tree.process_frame



static func _run_inner(home: Node, flow: Dictionary) -> void:
	var click_st: Dictionary = PeekabooManager.get_cat_state()

	var prop_index: int = int(click_st.get("prop_index", 0))
	var pos_index: int = int(click_st.get("pos_index", 0))
	Tracker.track_btn_click(Tracker.peekaboo_cat_btn_for_prop(prop_index), home)

	var group: int = int(ABTestManager.peekaboo_cat.peek_value())
	var watched_ad: bool = false
	var claim_day: String = PeekabooManager.get_claim_day()
	var event_id: String = PeekabooManager.get_event_id()
	var receipt: Dictionary = {}

	var offline: bool = RankOfflineOverlayHelper.is_offline_mode()
	var grants_at_click: bool = (
		PeekabooRules.grants_reward(RankActivityManager.get_state(), offline)
		and not bool(click_st.get("claimed_today", false))
	)
	if not grants_at_click:
		await _run_interaction_only(home, prop_index, pos_index, flow)
		if not _valid(flow):
			return

		return

	if ABTestManager.peekaboo_cat.needs_ad_popup():
		var intent: String = await _run_confirm_popup(home, flow)
		if not _valid(flow):
			return
		if intent != "ad" and intent != "plain":
			return
		if intent == "ad":
			receipt = await _watch_reward_ad(home, flow, PeekabooRules.fish_count(group, true), claim_day, event_id)
			if not _valid(flow) or not receipt.get("ok", false):
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

	if (not grants and receipt.is_empty()) or amount <= 0:
		await _run_interaction_only(home, prop_index, pos_index, flow)
		if not _valid(flow):
			return

		return

	if receipt.is_empty():
		receipt = PeekabooManager.claim_reward(amount, claim_day, event_id)
	if not receipt.get("ok", false):
		Toast.popup("RECOVERY_SAVE_ERROR", home)
		return
	if receipt.get("duplicate", false):
		return
	var advance: int = int(receipt.get("advance", 0))
	await _play_peek_out_and_fish(home, amount, prop_index, pos_index, flow)
	if not _valid(flow):
		return

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
	await _popup_hidden(change_ui, flow)
	if not _valid(flow):
		return

	await _run_settle_tail(home, flow)
	if not _valid(flow):
		return


static func _run_settle_tail(home: Node, flow: Dictionary) -> void:
	if RankActivityManager.get_state() != RankActivityData.State.SETTLING:
		return
	if not RankActivityManager.get_pending_reward().is_empty():
		RankActivityManager.claim_reward(true)

		await flow.tree.process_frame
		if not _valid(flow):
			return
		await _popup_hidden(UiName.AWARD, flow)
		if not _valid(flow):
			return
		return
	var solo_shown: bool = await _run_end_solo_podium(home, flow)
	if not _valid(flow):
		return
	if not solo_shown:
		RankActivityManager.notify_settlement_done()


static func _run_end_solo_podium(home: Node, flow: Dictionary) -> bool:
	var pending: Dictionary = RankActivityManager.get_pending_end_solo_podium()
	if pending.is_empty():
		return false
	if not ABTestManager.podium_per_leaderboard.has_end_solo_podium():
		return false
	if not RankActivityManager.begin_end_solo_podium():
		return false
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": int(pending.get("rank", 4))})
	await _popup_hidden(UiName.RANK_ACTIVITY_SOLO_PODIUM, flow)
	if not _valid(flow):
		return false
	RankActivityManager.complete_end_solo_podium(true)
	if not is_instance_valid(home):
		return true
	return true


static func _run_confirm_popup(home: Node, flow: Dictionary) -> String:
	var ad_available: bool = await UniKitManager.is_reward_valid(AdPlacement.REWARD, _AD_POSITION)
	if not _valid(flow):
		return "close"

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
		res.intent = await _await_confirm_intent(home, page, flow)
		if not _valid(flow):
			res.done = true
			return
		await _popup_hidden(UiName.PEEKABOO_CONFIRM, flow)
		if not _valid(flow):
			res.done = true
			return
		res.done = true
	home.enqueue_peekaboo_confirm_popup(body)
	while not res.done:
		if not is_instance_valid(home):
			return "close"

		if not bool(res.started) and not home.is_peekaboo_confirm_pending():
			return "close"
		await flow.tree.process_frame
		if not _valid(flow):
			return "close"
	return String(res.intent)


static func _await_confirm_intent(home: Node, page: Object, flow: Dictionary) -> String:
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
		await flow.tree.process_frame
		if not _valid(flow):
			return "close"

	if page.ad_requested.is_connected(on_ad):
		page.ad_requested.disconnect(on_ad)
	if page.plain_requested.is_connected(on_plain):
		page.plain_requested.disconnect(on_plain)
	if page.close_requested.is_connected(on_close):
		page.close_requested.disconnect(on_close)
	return String(res.intent)


## 等待激励广告的结束结果并设置超时边界，防止原生广告回调缺失时流程永久悬挂。
static func _watch_reward_ad(host: Node, flow: Dictionary, amount: int, claim_day: String, event_id: String) -> Dictionary:
	var show_id: String = UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, _AD_POSITION)
	var ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, _AD_POSITION, show_id)
	if not _valid(flow):
		return {}
	if not ready:
		Toast.popup("AD_TOAST_NOT_READY", host)
		return {}
	var res := {"receipt": {}, "closed_ms": -1, "errored": false}
	# The receipt belongs to the frozen day/event, not to the lifetime of HomePage.
	var on_rewarded: Callable = func(pid: String) -> void:
		if pid == AdPlacement.REWARD:
			res.receipt = PeekabooManager.claim_reward(amount, claim_day, event_id)
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.REWARD:
			res.closed_ms = Time.get_ticks_msec()
	var on_error: Callable = func(pid: String, _message: String) -> void:
		if pid == AdPlacement.REWARD:
			res.errored = true
	if not UniKitManager.connect_reward_once(show_id, on_rewarded):
		return {}
	UniKitManager.ad_closed.connect(on_closed)
	UniKitManager.ad_error_occurred.connect(on_error)
	UniKitManager.show_reward(AdPlacement.REWARD, _AD_POSITION, show_id)
	var deadline: int = Time.get_ticks_msec() + int(_AD_WAIT_TIMEOUT_SEC * 1000.0)
	while _valid(flow) and res.receipt.is_empty() and not res.errored and Time.get_ticks_msec() < deadline:
		if int(res.closed_ms) >= 0 and Time.get_ticks_msec() - int(res.closed_ms) >= int(_AD_REWARD_GRACE_SEC * 1000.0):
			break
		await flow.tree.process_frame
	if UniKitManager.ad_closed.is_connected(on_closed):
		UniKitManager.ad_closed.disconnect(on_closed)
	if UniKitManager.ad_error_occurred.is_connected(on_error):
		UniKitManager.ad_error_occurred.disconnect(on_error)
	# Exact-ID callback remains until the bus resolves/expires it, so closed-first delivery can still commit.
	return res.receipt



static func _run_interaction_only(home: Node, prop_index: int, pos_index: int, flow: Dictionary) -> void:
	PeekabooManager.mark_interacted()
	await _play_peek_out_and_fish(home, 0, prop_index, pos_index, flow)
	if not _valid(flow):
		return


const _FISH_SCENE: PackedScene = preload("res://products/meowdoku/app/features/peekaboo/ui/peekaboo_fish.tscn")

const _FISH_LEFT_SIDE_POS_INDEXES: Array[int] = [0, 2, 3]

const _FISH_ARRIVE_TO_CHANGE_SEC: float = 0.3666667

const _FISH_SPAWN_DELAY_SEC: float = 0.1

const _FISH_SCALE: float = 0.75

const _FISH_ORIGIN_NUDGE_Y: float = -15.0


static func _play_peek_out_and_fish(
	home: Node, count: int, prop_index: int, pos_index: int, flow: Dictionary) -> void:
	if not is_instance_valid(home):
		return

	var peek_dur: float = 0.0
	var cell: Control = home.get_peekaboo_cell()
	if cell != null and cell.has_method("play_peek_out"):
		peek_dur = float(cell.call("play_peek_out", prop_index))

	var fish: Node2D = null
	if count > 0:
		if _FISH_SPAWN_DELAY_SEC > 0.0:
			await _delay(flow, _FISH_SPAWN_DELAY_SEC)
			if not _valid(flow):
				return
			if not is_instance_valid(home):
				return
		fish = _spawn_fish(home, count, pos_index)

	if fish != null:
		await _await_fish_arrived_then_settle(home, fish, count, flow)
		if not _valid(flow):
			return
		return
	if peek_dur > 0.0 and is_instance_valid(home):
		await _delay(flow, peek_dur)
		if not _valid(flow):
			return


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
static func _await_fish_arrived_then_settle(home: Node, fish: Node2D, count: int, flow: Dictionary) -> void:
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
	var arrival := {"done": false}
	fish.last_fish_arrived.connect(func() -> void: arrival.done = true, CONNECT_ONE_SHOT)
	while _valid(flow) and is_instance_valid(fish) and not arrival.done:
		await flow.tree.process_frame
		if not _valid(flow):
			return
	if not _valid(flow):
		if is_instance_valid(fish):
			fish.queue_free()
		return
	if not is_instance_valid(home):
		return

	await _delay(flow, _FISH_ARRIVE_TO_CHANGE_SEC)
	if not _valid(flow):
		return


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
