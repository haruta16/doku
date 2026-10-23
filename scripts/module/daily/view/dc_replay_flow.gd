## 每日挑战重玩流程：确认后等待激励广告奖励回执，再调用进入重玩的回调。
class_name DcReplayFlow
extends RefCounted

const _AD_POSITION: String = Tracker.AdPos.DAILY_REPLAY

const _TIMER_ICON_PATH: String = "res://assets/sprites/daily/icon_timer_check.png"
const _TIMER_ICON_W: int = 60
const _TIMER_ICON_H: int = 68

const _TIME_COLOR_HEX: String = "F19320"

const _AD_WAIT_TIMEOUT_SEC: float = 60.0

const _AD_WAIT_CLOCK_SPAN: float = 3600.0

const _AD_REWARD_GRACE_SEC: float = 1.0


## 实验允许重玩时打开确认页，确认回调串到广告等待流程。
static func open_confirm(host: Node, on_enter: Callable) -> void:
	if not ABTestManager.dc_costume.can_replay():
		return

	UIManager.show_ui(
		UiName.DC_REPLAY_CONFIRM,
		{
			"title": "DC_REPLAY_TITLE",
			"content": _content_bbcode(),
			"on_confirm": func() -> void: _on_confirmed(host, on_enter),
		}
	)


static func _content_bbcode() -> String:
	var time_seg: String = (
		"[img=%dx%d]%s[/img] [color=#%s]%s[/color]"
		% [
			_TIMER_ICON_W,
			_TIMER_ICON_H,
			_TIMER_ICON_PATH,
			_TIME_COLOR_HEX,
			DailyEntryState.done_time_text(),
		]
	)
	return "[center]%s[/center]" % I18nFormat.fill("DC_REPLAY_CONTENT", time_seg)


static func start_ad_replay(host: Node, on_enter: Callable) -> void:
	if not ABTestManager.dc_costume.can_replay():
		return
	await _on_confirmed(host, on_enter)


## 只有激励奖励真正到达且宿主仍有效时，才调用进入重玩的回调。
static func _on_confirmed(host: Node, on_enter: Callable) -> void:
	if not is_instance_valid(host):
		return
	if not await _watch_reward_ad(host):
		return
	if not is_instance_valid(host) or not on_enter.is_valid():
		return
	on_enter.call()


static func enter_params() -> Dictionary:
	return {"_tracker_status": Tracker.GameStatus.REPLAY}


## 等待奖励、错误或关闭事件；最多等 60 秒，关闭后再留 1 秒接收迟到奖励，并清理连接。
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
					"[DcReplay] 看广等待超时 %.0fs（场景时间）未收到 ad_rewarded / ad_closed，按未重玩收尾"
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
		print("[DcReplay] 重玩机会被宽限期救回：reward 晚于 close %.0fms（场景时间）" % rescued_late_ms)
		push_error(
			(
				"DcReplayFlow: reward ad closed before rewarded, replay rescued, position=%s"
				% _AD_POSITION
			)
		)
	return bool(res.rewarded)
