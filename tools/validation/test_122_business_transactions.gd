## 实际产品聚合的离线回归：伪造API响应，不创建HttpClient或调用商店/服务端。
extends SceneTree


var checks: int = 0
var failures: int = 0
var game: Node
var files: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-") or not ProjectSettings.get_setting("doku/validation/offline", false):
		quit(2)
		return
	game = root.get_node("GameState")
	files = game.get_core_store().get("_file_store")
	_check(game.reset_all(), "business aggregate reset")
	game.set_tutorial_done(true)
	game.set_current_level(31)
	await _test_cloud()
	_test_peekaboo()
	_test_vip_gift()
	await _test_reward_popup()
	print("122 BUSINESS TRANSACTIONS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_cloud() -> void:
	var manager: Node = load("res://products/meowdoku/app/features/data_sync/data_sync_manager.gd").new()
	var fake: Variant = load("res://tools/validation/fixtures/fake_data_sync_api.gd").new()
	manager._api = fake
	var before: Dictionary = game.get_core_candidate()
	var uploaded: int = await manager._upload("test-only", 1, "local", "manual_choice", true)
	_check(uploaded == 5 and fake.uploads.size() == 2, "version conflict downloads then retries with new sync code")
	_check(int(fake.uploads[1].core.current_level) == 31 and game.get_current_level() == 31, "explicit local choice survives upload conflict and cannot become cloud choice")
	_check(game.get_tool_count("hint") == int(before.inventory.hint), "explicit local choice retains local inventory")
	var baseline: Dictionary = manager._last_cloud_root.duplicate(true)
	before = game.get_core_candidate()
	_fault(true)
	_check(not manager._merge_cloud_root(fake.remote, "cloud"), "cloud merge propagates local atomic-write failure")
	_check(game.get_core_candidate() == before and manager._last_cloud_root == baseline, "failed cloud merge leaves every module and baseline unchanged")
	_fault(false)
	_check(manager._merge_cloud_root(fake.remote, "cloud"), "failed cloud merge can retry")
	_check(game.get_current_level() == 99 and game.get_tool_count("hint") == 17 and int(game.get_feature_state("rank_activity").period_count) == 7, "cloud progress inventory and rank commit together")
	before = game.get_core_candidate()
	_check(not manager._merge_cloud_root({"core": {"current_level": 99, "tool_hint": -1}}, "cloud"), "invalid remote inventory refuses entire merge")
	_check(game.get_core_candidate() == before, "invalid remote data cannot partially apply")
	var stale: Variant = load("res://tools/validation/fixtures/fake_data_sync_api.gd").new()
	manager._api = stale
	stale.after_upload = func() -> void: manager._account_epoch += 1
	_check(await manager._upload("test-only", 1, "local") == -1 and stale.uploads.size() == 1, "account epoch rejects old async response before retry/merge")
	stale.after_upload = Callable()
	manager.free()

func _test_peekaboo() -> void:
	var rank: Node = root.get_node("RankActivityManager")
	var peek: Node = root.get_node("PeekabooManager")
	var model := RankActivityData.new()
	model.state = RankActivityData.State.OPEN_JOINED
	model.joined = true
	model.collect_total = 3
	model.period_count = 4
	var candidate: Dictionary = game.get_core_candidate()
	candidate.features.rank_activity = model.to_dict()
	candidate.features.peekaboo = {"cat_present": true, "claimed_date": "", "interacted": false}
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "prepare eligible local event")
	var day: String = peek.get_claim_day()
	var event: String = peek.get_event_id()
	var before: Dictionary = game.get_core_candidate()
	_fault(true)
	var failed: Dictionary = peek.claim_reward(5, day, event)
	_check(not failed.ok and game.get_core_candidate() == before, "peekaboo write failure preserves rank and unclaimed eligibility")
	_fault(false)
	var applied: Dictionary = peek.claim_reward(5, day, event)
	_check(applied.ok and applied.before == 3 and applied.after == 8, "peekaboo awards score and consumes dated eligibility atomically")
	var revision: int = game.get_core_store().revision()
	_check(peek.claim_reward(5, day, event).get("duplicate", false) and game.get_core_store().revision() == revision, "duplicate peekaboo callback cannot award again")
	_check(not peek.claim_reward(5, "1900-01-01", event).ok and not peek.claim_reward(5, day, "stale-event").ok, "wrong day and account/period identity refuse claim")
	_check(rank.get_collect_total() == 8, "rank cache observes atomic feature publication")

func _test_vip_gift() -> void:
	var purchase: Node = root.get_node("PurchaseManager")
	# 仅准备本地权益缓存，不触发购买或平台订阅请求。
	var data: Dictionary = game.get_feature_state("purchase")
	data["vip_active"] = true
	var candidate: Dictionary = game.get_core_candidate()
	var rewards: Array = [{"kind": "hint", "count": 2}, {"category": 1, "frame_id": 100, "count": 1}]
	var before: Dictionary = game.get_core_candidate()
	_fault(true)
	var failed: Dictionary = game.commit_feature_award("purchase", data, rewards, 0, "fixture", "", "fixture/vip/once")
	_check(not failed.ok and game.get_core_candidate() == before, "feature entitlement and mixed award registration rollback together")
	_fault(false)
	var applied: Dictionary = game.commit_feature_award("purchase", data, rewards, 0, "fixture", "", "fixture/vip/once")
	_check(applied.ok and game.get_feature_state("purchase").get("vip_active", false), "feature+reward registration retries")
	var revision: int = game.get_core_store().revision()
	_check(game.commit_feature_award("purchase", data, rewards, 0, "fixture", "", "fixture/vip/once").get("duplicate", false) and game.get_core_store().revision() == revision, "stable feature claim key prevents a second entitlement/reward transaction")

func _fault(enabled: bool) -> void:
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return enabled and phase == "before_replace")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)


func _test_reward_popup() -> void:
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var ui: Node = root.get_node("UIManager")
	var allowed: Dictionary = {"ok": false, "calls": 0, "signals": 0}
	var callback := func() -> bool:
		allowed.calls += 1
		return allowed.ok
	var params: Dictionary = {"items": [AwardItem.make("hint", 1)], "claim": callback, "text": "fixture"}
	var page: Variant = ui.show_ui("reward_claim_popup", params)
	await process_frame
	var on_claimed := func(_granted: bool) -> void: allowed.signals += 1
	page.claimed.connect(on_claimed)
	page._on_action_pressed()
	_check(page.is_showing() and not page._claiming and allowed.signals == 0, "failed popup claim remains visible and does not publish completion")
	allowed.ok = true
	page._on_action_pressed()
	_check(allowed.calls == 2 and allowed.signals == 1 and not page.is_showing(), "popup retry publishes successful claim once")
	await create_timer(0.3).timeout
	page.claimed.disconnect(on_claimed)
	page = ui.show_ui("reward_claim_popup", params)
	await process_frame
	var reopened := func(_granted: bool) -> void: ui.show_ui("reward_claim_popup", params)
	page.claimed.connect(reopened)
	var generation: int = page._claim_revision
	page._on_action_pressed()
	_check(page.is_showing() and page._claim_revision > generation, "old successful signal cannot hide a synchronously reopened popup")
	page.claimed.disconnect(reopened)
	ui.hide_ui("reward_claim_popup")
	await create_timer(0.3).timeout
	var before: int = game.get_tool_count("hint")
	var writes: Dictionary = {"count": 0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			writes.count += 1
			return writes.count >= 2
		return false)
	page = ui.show_ui("reward_claim_popup", {"items": [AwardItem.make("hint", 1)], "reason": "fixture_popup"})
	await process_frame
	page._on_action_pressed()
	var uid: int = page._pending_award_uid
	_check(uid > 0 and page.is_showing() and game.get_tool_count("hint") == before and not game.find_in_flight_award(uid).is_empty(), "direct registration is not reported as a successful asset claim after write failure")
	var sequence: int = game.get_core_candidate().award_sequence
	_fault(false)
	page._on_action_pressed()
	_check(game.get_tool_count("hint") == before + 1 and game.find_in_flight_award(uid).is_empty() and game.get_core_candidate().award_sequence == sequence, "direct popup retry consumes the original uid without duplicate registration")
	await create_timer(0.3).timeout
	await ui.destroy_ui("reward_claim_popup")
	await process_frame
