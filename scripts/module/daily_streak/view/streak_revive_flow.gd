## 断签补签流程：等待玩家选择与广告库存，收到奖励后补签，并防止过期页面回调生效。
class_name StreakReviveFlow
extends RefCounted

const _AD_POSITION: String = "streak_revive_reward"

const _AD_WAIT_TIMEOUT_SEC: float = 60.0

const _AD_WAIT_CLOCK_SPAN: float = 3600.0

const _AD_REWARD_GRACE_SEC: float = 1.0


## 用页面展示序号隔离一次恢复流程；放弃则普通打卡，拿到激励奖励才调用补签。
static func run(host: Node) -> void:
	var ui: StringName = UiName.STREAK_BACKFILL
	var info: Dictionary = StreakManager.get_revive_info()

	var broken_streak: int = int(info.get("broken_streak", 0))
	var page: UIFrameWindow = (
		UIManager
		. show_ui(
			ui,
			{
				"from_streak": broken_streak,
				"to_streak": StreakManager.get_display_streak(),
				"info_days": broken_streak,
			}
		)
	)
	if page == null:
		StreakManager.give_up_revive()
		return

	var seq: int = int(page.call("get_show_sequence"))
	var opportunity: Dictionary = {}
	var settled: bool = false
	while not settled:
		var action: String = await _await_intent(host, page, seq)
		if action == "stale":
			return
		if action == "give_up":
			StreakManager.give_up_revive()
			settled = true
		else:
			var query_result: String = await _await_ad_query(host, page, seq, opportunity)
			if query_result == "stale":
				return
			if query_result == "give_up":
				StreakManager.give_up_revive()
				settled = true
			elif query_result == "ready":
				var show_id: String = opportunity["show_id"]

				opportunity.clear()
				if await _watch_reward_ad(host, show_id):
					StreakManager.revive_streak()
					settled = true

	if _is_current_page(page, seq):
		UIManager.hide_ui(ui)
		var close_state: Dictionary = {"hidden": false}
		_wait_page_hidden(ui, close_state)
		while not close_state["hidden"] and is_instance_valid(host):
			if (
				is_instance_valid(page)
				and page.is_showing()
				and int(page.call("get_show_sequence")) != seq
			):
				return
			await host.get_tree().process_frame


static func _wait_page_hidden(ui: StringName, state: Dictionary) -> void:
	await UIManager.await_hidden(ui)
	state["hidden"] = true


static func _is_current_page(page: Object, seq: int) -> bool:
	return (
		is_instance_valid(page) and page.is_showing() and int(page.call("get_show_sequence")) == seq
	)


## 监听本轮恢复或放弃选择，页面换轮次时返回过期状态，并解除临时信号连接。
static func _await_intent(host: Node, page: Object, seq: int) -> String:
	var res: Dictionary = {"action": ""}
	var on_restore: Callable = func() -> void:
		if res.action == "":
			res.action = "restore"
	var on_giveup: Callable = func() -> void: res.action = "give_up"
	page.restore_requested.connect(on_restore)
	page.give_up_requested.connect(on_giveup)
	while res.action == "":
		if not is_instance_valid(page):
			res.action = "give_up"
			break
		if not is_instance_valid(host) or not _is_current_page(page, seq):
			res.action = "stale"
			break
		await host.get_tree().process_frame
	if is_instance_valid(page):
		if page.restore_requested.is_connected(on_restore):
			page.restore_requested.disconnect(on_restore)
		if page.give_up_requested.is_connected(on_giveup):
			page.give_up_requested.disconnect(on_giveup)
		if not _is_current_page(page, seq):
			return "stale"
	return res.action


## 查询库存期间仍允许放弃；宿主或页面过期后丢弃异步结果。
static func _await_ad_query(host: Node, page: Object, seq: int, opportunity: Dictionary) -> String:
	if not is_instance_valid(host) or not _is_current_page(page, seq):
		return "stale"
	var state: Dictionary = {"done": false, "ready": false, "cancelled": false}
	var on_give_up: Callable = func() -> void: state["cancelled"] = true
	page.give_up_requested.connect(on_give_up)
	page.call("set_restore_query_pending", true, seq)
	_query_ad_ready(page, seq, opportunity, state)
	while not state["done"] and not state["cancelled"]:
		if not is_instance_valid(host) or not _is_current_page(page, seq):
			state["cancelled"] = true
			break
		await host.get_tree().process_frame
	if is_instance_valid(page) and page.give_up_requested.is_connected(on_give_up):
		page.give_up_requested.disconnect(on_give_up)
	if not is_instance_valid(host) or not _is_current_page(page, seq):
		state["cancelled"] = true
		return "stale"
	page.call("set_restore_query_pending", false, seq)
	if state["cancelled"]:
		return "give_up"
	if state["ready"]:
		return "ready"
	Toast.popup("AD_TOAST_LOADING", host)
	return "not_ready"


## 同一次机会复用 show_id，后续点击只补报一次广告变为有效，避免重复统计。
static func _query_ad_ready(
	page: Object, seq: int, opportunity: Dictionary, state: Dictionary
) -> void:
	if state["cancelled"] or not _is_current_page(page, seq):
		return
	var first_click: bool = not opportunity.has("show_id")
	if first_click:
		opportunity["show_id"] = UniKitManager.stats_ad_show_timing(
			AdPlacement.REWARD, _AD_POSITION
		)
		opportunity["became_valid_reported"] = false
	var show_id: String = opportunity["show_id"]
	if not first_click:
		var ad_valid: bool = await UniKitManager.is_reward_valid(AdPlacement.REWARD, _AD_POSITION)
		if state["cancelled"] or not _is_current_page(page, seq):
			return
		if not ad_valid:
			state["done"] = true
			return
		if not opportunity["became_valid_reported"]:
			UniKitManager.stats_ad_became_valid(AdPlacement.REWARD, _AD_POSITION, show_id)
			opportunity["became_valid_reported"] = true
	var ad_ready: bool = await UniKitManager.is_reward_ready(
		AdPlacement.REWARD, _AD_POSITION, show_id
	)
	if state["cancelled"] or not _is_current_page(page, seq):
		return
	state["ready"] = ad_ready
	state["done"] = true


## 等待奖励最多 60 秒，广告先关闭时保留 1 秒宽限；结束后取消计时并断开回调。
static func _watch_reward_ad(host: Node, show_id: String) -> bool:
	var res: Dictionary = {"rewarded": false, "closed": false, "errored": false}
	var on_rewarded: Callable = func(placement_id: String) -> void:
		if placement_id == AdPlacement.REWARD:
			res.rewarded = true
	var on_closed: Callable = func(placement_id: String) -> void:
		if placement_id == AdPlacement.REWARD:
			res.closed = true
	var on_error: Callable = func(placement_id: String, _message: String) -> void:
		if placement_id == AdPlacement.REWARD:
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
					"[StreakRevive] 看广等待超时 %.0fs（场景时间）未收到 ad_rewarded / ad_closed，按未发奖收尾"
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
		print("[StreakRevive] 补签被宽限期救回：reward 晚于 close %.0fms（场景时间）" % rescued_late_ms)
	return bool(res.rewarded)
