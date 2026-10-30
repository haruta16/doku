## 激励广告逐次身份：乱序、重复、清档、同步重入与旧桥降级。
extends SceneTree

class LegacyBridge:
	extends RefCounted
	signal ad_closed(placement_id: String)
	signal ad_rewarded(placement_id: String)
	var shows := 0
	func isAdReady(_placement: String, _position: String, _show_id: String) -> bool:
		return true
	func isAdValid(_placement: String, _position: String) -> bool:
		return true
	func showAd(_placement: String, _position: String, _show_id: String) -> void:
		shows += 1

class IdentifiedBridge:
	extends LegacyBridge
	signal ad_closed_for_show(placement_id: String, show_id: String)
	signal ad_rewarded_for_show(placement_id: String, show_id: String)
	signal ad_shown_for_show(placement_id: String, show_id: String)
	signal ad_error_for_show(placement_id: String, show_id: String, message: String)
	func showAd(placement: String, _position: String, show_id: String) -> void:
		shows += 1
		ad_shown_for_show.emit(placement, show_id)
		ad_rewarded_for_show.emit(placement, show_id)
		ad_closed_for_show.emit(placement, show_id)

var checks := 0
var failures := 0
var game: Node
var sdk: Node
var received: Dictionary = {}
var public_rewards := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	sdk = root.get_node("UniKitManager")
	var group: RefCounted = root.get_node("ABTestManager").common_rewardad_logic
	group.set_debug_override(1)
	sdk.ad_rewarded.connect(func(_placement: String) -> void: public_rewards += 1)

	_start("A", true)
	_start("B", true)
	sdk._on_ad_rewarded_for_show("reward", "B")
	_check(received.get("B", 0) == 1 and received.get("A", 0) == 0, "late B reward reaches only B consumer")
	_check(sdk._pending_watchdogs.has("A") and not sdk._pending_watchdogs.has("B"), "late B removes only B watchdog")
	sdk._on_ad_rewarded_for_show("reward", "A")
	sdk._on_ad_rewarded_for_show("reward", "B")
	_check(received.get("A", 0) == 1 and received.get("B", 0) == 1 and public_rewards == 0, "closed rewards deliver once without broadcasting to new consumers")

	_start("old", true)
	_start("current", false)
	sdk._on_ad_rewarded("reward")
	sdk._on_ad_rewarded_for_show("reward", "unknown")
	sdk._on_ad_rewarded_for_show("interstitial", "current")
	sdk._on_ad_closed_for_show("reward", "old")
	sdk._on_ad_error_for_show("reward", "old", "late error")
	_check(sdk._reward_active_show_id == "current" and not sdk._reward_received, "legacy, unknown, wrong placement and old lifecycle callbacks cannot settle current show")
	sdk._on_ad_rewarded_for_show("reward", "old")
	_check(received.get("old", 0) == 1 and received.get("current", 0) == 0 and not sdk._reward_received, "old reward while B active still reaches original consumer")
	sdk._on_ad_rewarded_for_show("reward", "current")
	sdk._on_ad_rewarded_for_show("reward", "current")
	sdk._on_ad_closed_for_show("reward", "current")
	_check(received.get("current", 0) == 1 and public_rewards == 1, "active identified reward and observer notification are emitted once")

	_start("restored", true)
	sdk._on_reward_grant_timeout("restored", "props_normal_hint")
	_check(_has_pending("restored"), "timeout creates one real persisted compensation")
	sdk._on_ad_rewarded_for_show("reward", "restored")
	sdk._on_reward_grant_timeout("restored", "props_normal_hint")
	_check(received.get("restored", 0) == 0 and _has_pending("restored"), "late confirmed reward cannot also pay after compensation registration")
	_check(not sdk._start_reward_session("restored", "props_normal_hint"), "terminal show IDs cannot be reused")

	_start("failed_restore", true)
	_fail_writes(true)
	sdk._on_reward_grant_timeout("failed_restore", "props_normal_hint")
	_fail_writes(false)
	sdk._on_ad_rewarded_for_show("reward", "failed_restore")
	_check(received.get("failed_restore", 0) == 1 and not _has_pending("failed_restore") and not sdk._pending_watchdogs.has("failed_restore"), "late earned reward after failed registration takes normal path, without restore qualification")

	_start("during_write", true)
	var entered := {"done": false}
	var observer := func(_result: Dictionary) -> void:
		if not entered.done:
			entered.done = true
			sdk._on_ad_rewarded_for_show("reward", "during_write")
	game.storage_failed.connect(observer)
	_fail_writes(true)
	sdk._on_reward_grant_timeout("during_write", "props_normal_hint")
	game.storage_failed.disconnect(observer)
	_fail_writes(false)
	sdk._retry_reward_records()
	_check(entered.done and received.get("during_write", 0) == 1 and not _has_pending("during_write"), "reward reentered during failed compensation commit settles normally exactly once")

	_start("during_retry", true)
	_fail_writes(true)
	sdk._on_reward_grant_timeout("during_retry", "props_normal_hint")
	var retry_observed := {"done": false}
	var on_retry := func(_result: Dictionary) -> void:
		if not retry_observed.done:
			retry_observed.done = true
			sdk._on_ad_rewarded_for_show("reward", "during_retry")
	game.storage_failed.connect(on_retry)
	sdk._retry_reward_records()
	game.storage_failed.disconnect(on_retry)
	_check(received.get("during_retry", 0) == 1 and not sdk._pending_reward_history.is_empty() and not sdk._reward_record_retry_timer.is_stopped(), "reward arriving inside restore retry keeps its new history event scheduled")
	_fail_writes(false)
	sdk._reward_record_retry_timer.start(0.01)
	await create_timer(0.08).timeout
	_check(sdk._pending_reward_history.is_empty() and sdk._reward_record_retry_timer.is_stopped(), "timer persists history added after retry queue had already drained")

	_start("during_success", true)
	var committed := {"done": false}
	var on_commit := func(_revision: int) -> void:
		if not committed.done:
			committed.done = true
			sdk._on_ad_rewarded_for_show("reward", "during_success")
	game.get_core_store().committed.connect(on_commit)
	sdk._on_reward_grant_timeout("during_success", "props_normal_hint")
	game.get_core_store().committed.disconnect(on_commit)
	_check(committed.done and received.get("during_success", 0) == 0 and _has_pending("during_success"), "reward reentered during successful compensation commit cannot also pay normally")

	_start("hidden_during_history", false)
	var on_history := func(_revision: int) -> void: sdk.disconnect_reward_callbacks(self)
	game.get_core_store().committed.connect(on_history)
	sdk._on_ad_rewarded_for_show("reward", "hidden_during_history")
	game.get_core_store().committed.disconnect(on_history)
	sdk._on_ad_closed_for_show("reward", "hidden_during_history")
	_check(received.get("hidden_during_history", 0) == 0, "synchronous history observer can cancel consumer before delivery to a reused page")

	# 隐藏页明确取消其消费者，不让迟到奖励作用于该节点的下一次展示。
	_start("hidden", true)
	sdk.disconnect_reward_callbacks(self)
	sdk._on_ad_rewarded_for_show("reward", "hidden")
	_check(received.get("hidden", 0) == 0 and not sdk._pending_watchdogs.has("hidden"), "detached page receives no old reward; known reward still cancels speculative restore")

	_start("before_reset", true)
	_check(game.reset_all(), "explicit reset succeeds")
	_start("after_reset", false)
	sdk._on_ad_rewarded_for_show("reward", "before_reset")
	sdk._on_ad_closed_for_show("reward", "before_reset")
	sdk._on_reward_grant_timeout("before_reset", "props_normal_hint")
	_check(sdk._reward_active_show_id == "after_reset" and received.get("before_reset", 0) == 0 and game.get_pending_rewards().is_empty(), "old callbacks after reset cannot affect new show or restore old entitlement")
	_check(not sdk._start_reward_session("before_reset", "props_normal_hint"), "reset does not permit reuse of a pre-reset ID")
	sdk._on_ad_closed_for_show("reward", "after_reset")

	# 真实页面直接销毁可以跳过 on_hide；帧末 free 之前也必须取消其消费者。
	for scene_path: String in [
		"res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn",
		"res://products/meowdoku/gameplay/presentation/result/ui/game_fail_page.tscn",
		"res://products/meowdoku/gameplay/presentation/daily/ui/daily_fail_page.tscn",
		"res://products/meowdoku/app/features/award/ui/award_page.tscn",
	]:
		var page: Node = load(scene_path).instantiate()
		host.add_child(page)
		var show_id := "destroy_" + scene_path.get_file()
		_check(sdk.connect_reward_once(show_id, Callable(page, "set_meta").bind(true)), "register real page before destroy " + show_id)
		sdk._start_reward_session(show_id, "props_normal_hint")
		page._do_destroy()
		page.queue_free()
		_check(is_instance_valid(page) and page.is_queued_for_deletion() and not sdk._reward_callbacks.has(show_id), "destroy synchronously cancels consumer " + show_id)
		sdk._on_ad_rewarded_for_show("reward", show_id)
		sdk._on_ad_closed_for_show("reward", show_id)
		_check(not page.has_meta("reward"), "same-frame late reward cannot invoke destroyed real page " + show_id)
	await process_frame

	# 新桥的信号合同与旧桥 fail-closed 都实际经过 show_reward/readiness 入口。
	var adapter: Node = load("res://tools/validation/fixtures/identified_ad_adapter.gd").new()
	root.add_child(adapter)
	adapter.cheat_show_reward = true
	adapter.cheat_show_interstitial = true
	var legacy := LegacyBridge.new()
	adapter._plugin = legacy
	_check(not adapter._has_identified_reward_bridge() and not (await adapter.is_reward_ready("reward", "p", "legacy")) and not (await adapter.is_reward_valid("reward", "p")), "legacy native bridge consistently reports reward unavailable")
	adapter.show_reward("reward", "p", "legacy")
	_check(legacy.shows == 0 and adapter._reward_active_show_id.is_empty(), "show cannot bypass identity capability guard")
	_check(await adapter.is_interstitial_ready("interstitial", "p", "interstitial"), "legacy native bridge still supports interstitial readiness")
	adapter.try_show_interstitial("interstitial", "p", "interstitial")
	_check(legacy.shows == 1, "identity guard leaves interstitial display available")
	var bridge := IdentifiedBridge.new()
	adapter._plugin = bridge
	adapter._connect_identified_reward_callbacks()
	var synchronous := {"count": 0}
	adapter.connect_reward_once("synchronous", func(_placement: String) -> void: synchronous.count += 1)
	_check(await adapter.is_reward_ready("reward", "p", "synchronous"), "identified bridge is ready")
	adapter.show_reward("reward", "p", "synchronous")
	bridge.ad_rewarded_for_show.emit("reward", "synchronous")
	_check(synchronous.count == 1 and adapter._reward_active_show_id.is_empty(), "registration precedes synchronous native callbacks and duplicate is ignored")
	adapter.queue_free()
	host.queue_free()
	await process_frame
	group.clear_debug_override()
	print("STORAGE AD IDENTITY TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _start(show_id: String, close: bool) -> void:
	_check(sdk.connect_reward_once(show_id, func(_placement: String) -> void: received[show_id] = int(received.get(show_id, 0)) + 1), "register " + show_id)
	_check(sdk._start_reward_session(show_id, "props_normal_hint"), "start " + show_id)
	sdk._on_ad_shown_for_show("reward", show_id)
	if close:
		sdk._on_ad_closed_for_show("reward", show_id)


func _has_pending(show_id: String) -> bool:
	for entry: Dictionary in game.get_pending_rewards():
		if entry.show_id == show_id:
			return true
	return false


func _fail_writes(enabled: bool) -> void:
	game._product_store.files.set_fault_injector_for_tests((func(phase: String) -> bool: return phase == "before_replace") if enabled else Callable())


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
