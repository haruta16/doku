## 广告补发首次登记与正常领奖流水：写失败保留来源，真实定时重试不重复登记。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var sdk: Node
var files: RefCounted
var group: RefCounted
var _reward_sequence: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	game = root.get_node("GameState")
	sdk = root.get_node("UniKitManager")
	files = game._product_store.files
	group = root.get_node("ABTestManager").common_rewardad_logic
	group.set_debug_override(1)
	_check(game.is_storage_ready(), "core store is available")
	var baseline := {"show_id": "baseline", "source": "props_normal_hint", "ts": 1}
	_check(game.add_pending_reward(baseline).ok, "baseline registration succeeds")
	_fail_writes(true)
	var failed: Dictionary = game.add_pending_reward(_entry("direct_failure"))
	_check(not failed.ok and failed.error == "write_failed", "registration exposes failed persistence")
	_check(game.get_pending_rewards() == [baseline], "failed registration does not publish a false pending record")
	_check(game.pop_all_pending_rewards().is_empty() and game.get_pending_rewards() == [baseline], "failed legacy drain never returns an uncommitted removal")
	_check(not game.remove_pending_rewards([baseline]) and game.get_pending_rewards() == [baseline], "failed removal reports failure and preserves entitlement")

	# 超时首次登记失败后，原 watchdog 必须存活；重复尝试只共用一个重试定时器。
	_watch("retry")
	sdk._on_reward_grant_timeout("retry", "props_normal_hint")
	_check(sdk._pending_watchdogs.has("retry"), "failed registration retains watchdog")
	_check(sdk._pending_watchdogs.retry.timed_out, "only elapsed watchdogs become retryable")
	var retry_timer: Timer = sdk._reward_record_retry_timer
	_check(is_instance_valid(retry_timer) and not retry_timer.is_stopped(), "failure schedules a real retry")
	sdk._on_reward_grant_timeout("retry", "props_normal_hint")
	_check(sdk._reward_record_retry_timer == retry_timer, "repeated failure reuses one timer")
	_check(game.get_pending_rewards() == [baseline], "repeated failure never records partial success")
	_fail_writes(false)
	retry_timer.start(0.01)
	await create_timer(0.08).timeout
	_check(not sdk._pending_watchdogs.has("retry") and _has_pending("retry"), "timer retries registration before consuming watchdog")
	_check(retry_timer.is_stopped(), "successful drain leaves no polling timer")
	var revision: int = game.get_core_store().revision()
	sdk._on_reward_grant_timeout("retry", "props_normal_hint")
	var duplicate: Dictionary = game.add_pending_reward(_entry("retry"))
	_check(duplicate.ok and duplicate.status == "already_applied" and game.get_core_store().revision() == revision, "old timeout and duplicate show_id do not write twice")

	# 正常奖励迟到时，仍能取消尚未写入的补发；正常流水也通过同一重试出口。
	_watch("late_normal")
	_fail_writes(true)
	sdk._on_reward_grant_timeout("late_normal", "props_normal_hint")
	_check(sdk._pending_watchdogs.has("late_normal"), "late reward test retains failed watchdog")
	_fail_writes(false)
	sdk._on_ad_rewarded_for_show("reward", "late_normal")
	_check(not sdk._pending_watchdogs.has("late_normal") and not _has_pending("late_normal"), "late normal reward cancels unregistered compensation")
	_check(sdk._pending_reward_history.is_empty() and _history_count() == 1, "normal reward history is saved before leaving retry queue")
	sdk._on_reward_grant_timeout("late_normal", "props_normal_hint")
	_check(not _has_pending("late_normal"), "cancelled watchdog cannot be resurrected by its old timer")

	_watch("still_waiting")
	sdk._retry_reward_records()
	_check(sdk._pending_watchdogs.has("still_waiting") and not _has_pending("still_waiting"), "record retry never shortens the original ad grace period")
	sdk._pending_watchdogs.erase("still_waiting")
	_watch("disabled")
	_fail_writes(true)
	sdk._on_reward_grant_timeout("disabled", "props_normal_hint")
	group.set_debug_override(0)
	sdk._retry_reward_records()
	_check(not sdk._pending_watchdogs.has("disabled") and not _has_pending("disabled"), "disabled restore policy consumes no reward entitlement")
	_fail_writes(false)
	group.set_debug_override(1)

	# 两个不同领奖事件即使时间戳相同，也不能因一次失败而丢失或在重试时重复。
	_fail_writes(true)
	_reward()
	_reward()
	_check(_history_count() == 1 and sdk._pending_reward_history.size() == 2, "failed normal reward writes retain both events without publishing history")
	_fail_writes(false)
	retry_timer.start(0.01)
	await create_timer(0.08).timeout
	_check(_history_count() == 3 and sdk._pending_reward_history.is_empty(), "timer persists every queued normal reward exactly once")
	sdk._retry_reward_records()
	_check(_history_count() == 3, "empty retry cannot duplicate successful history")
	_check(game.get_restore_remaining_today(int(Time.get_unix_time_from_system())) == 3, "recovered history restores actual product eligibility")

	# 保存失败通知中又收到领奖事件时，嵌套重试不能消费外层尚未完成的事件。
	var nested := {"done": false}
	var on_failure := func(_result: Dictionary) -> void:
		if not nested.done:
			nested.done = true
			_reward()
	game.storage_failed.connect(on_failure)
	_fail_writes(true)
	_reward()
	game.storage_failed.disconnect(on_failure)
	_check(nested.done and sdk._pending_reward_history.size() == 2 and _history_count() == 3, "synchronous failure observer can append another event without reentrant duplication")
	_fail_writes(false)
	sdk._retry_reward_records()
	_check(_history_count() == 5 and sdk._pending_reward_history.is_empty(), "both outer and nested events survive retry")
	var loaded: Dictionary = files.load_result()
	var saved: Dictionary = loaded.config.get_value("core", "state")
	_check(saved.profile.reward_history_ts.size() == 5 and saved.profile.pending_rewards.size() == 2, "disk contains the recovered history and only the two valid pending entries")
	_fail_writes(true)
	_reward()
	_watch("before_reset")
	sdk._on_reward_grant_timeout("before_reset", "props_normal_hint")
	_fail_writes(false)
	_check(game.reset_all(), "explicit reset succeeds")
	_check(sdk._pending_reward_history.is_empty() and sdk._pending_watchdogs.is_empty() and retry_timer.is_stopped(), "reset cancels pending SDK records and their retry timer")
	sdk._retry_reward_records()
	sdk._on_reward_grant_timeout("before_reset", "props_normal_hint")
	_check(_history_count() == 0 and game.get_pending_rewards().is_empty(), "old callbacks cannot restore records after explicit reset")
	group.clear_debug_override()
	print("STORAGE REWARD REGISTRATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _entry(show_id: String) -> Dictionary:
	return {"show_id": show_id, "source": "props_normal_hint", "ts": int(Time.get_unix_time_from_system())}


func _reward() -> void:
	_reward_sequence += 1
	var show_id := "normal_%d" % _reward_sequence
	sdk._start_reward_session(show_id, "props_normal_hint")
	# 先关后奖也是同一个已知展示，方便重入保存通知中登记下一次独立事件。
	sdk._on_ad_closed_for_show("reward", show_id)
	sdk._on_ad_rewarded_for_show("reward", show_id)


func _watch(show_id: String) -> void:
	sdk._start_reward_session(show_id, "props_normal_hint")
	sdk._on_ad_closed_for_show("reward", show_id)
	sdk._pending_watchdogs[show_id] = {"position": "props_normal_hint", "ts": int(Time.get_unix_time_from_system())}


func _has_pending(show_id: String) -> bool:
	for entry: Dictionary in game.get_pending_rewards():
		if entry.get("show_id") == show_id:
			return true
	return false


func _history_count() -> int:
	return game.get_core_store().snapshot().profile.reward_history_ts.size()


func _fail_writes(enabled: bool) -> void:
	files.set_fault_injector_for_tests((func(phase: String) -> bool: return phase == "before_replace") if enabled else Callable())


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
