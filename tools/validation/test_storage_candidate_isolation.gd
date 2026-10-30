## 真实 GameState 候选必须隔离活数据；提交前的业务早退也不能提前消费资格。
extends SceneTree

const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")

var checks: int = 0
var failures: int = 0
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	game = root.get_node("GameState")
	_test_profile_isolation()
	for reason: String in ["later_ineligible", "overflow", "invalid_request"]:
		_test_early_rejection(reason)
	_test_query_ownership()
	print("STORAGE CANDIDATE ISOLATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_profile_isolation() -> void:
	_check(game.reset_all(), "reset isolated profile fixture")
	var candidate: Dictionary = game.get_core_candidate()
	var now: int = int(Time.get_unix_time_from_system())
	candidate.profile.merge({
		"bank_progress": {"4_1": 3},
		"main_bank_progress": {"4_1": {"idx": 2, "since_lk": 1, "transform": 0}},
		"lkmod_progress": {"4_1": {"idx": 1}},
		"game_total_stats": {"normal": {"wins": 2}},
		"retry_puzzle_params": {"regions": [[0, 0], [1, 1]], "solution": [0, 1]},
		"recent_puzzles": [{"puzzle_id": "fixture", "bank_progress": {"4_1": 3}}],
		"grt_level_d90_reported": [10], "grt_reported_events": ["fixture"],
		"pending_rewards": [{"show_id": "isolation", "source": "props_normal_hint", "ts": now}],
		"reward_history_ts": [now],
	}, true)
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "publish populated nested profile fixture")
	var before: Dictionary = game.get_core_store().snapshot()
	var revision: int = game.get_core_store().revision()
	var edited: Dictionary = game.get_core_candidate()
	for key: String in edited.profile:
		var value: Variant = edited.profile[key]
		if value is Array or value is Dictionary:
			_mutate_containers(value)
			var live: Dictionary = ProductStore.capture_profile(game._encode_profile_config()).profile
			_check(live[key] == before.profile[key], "candidate nested edits cannot change live profile field: " + key)
	_check(game.get_core_store().snapshot() == before and game.get_core_store().revision() == revision, "editing a candidate neither commits nor changes the authoritative snapshot")
	_check(game.set_sound_on(not game.is_sound_on()), "unrelated setting still saves after discarded candidate")
	var stored: Dictionary = game.get_core_store().snapshot().profile
	for key: String in before.profile:
		if before.profile[key] is Array or before.profile[key] is Dictionary:
			_check(stored[key] == before.profile[key], "unrelated save cannot persist discarded container edits: " + key)


## Modify both nested children and their owner so a shallow outer copy cannot pass.
func _mutate_containers(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_mutate_containers(child)
		value.clear()
	elif value is Array:
		for child: Variant in value:
			_mutate_containers(child)
		value.clear()


func _test_early_rejection(reason: String) -> void:
	_check(game.reset_all(), reason + ": reset isolated state")
	var now: int = int(Time.get_unix_time_from_system())
	var a := {"show_id": "early-A", "source": "props_normal_hint", "ts": now}
	var b := {"show_id": "early-B", "source": "props_normal_hint", "ts": now}
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile["pending_rewards"] = [a, b]
	candidate.profile["reward_history_ts"] = [now, now, now]
	candidate.profile["today_date"] = Time.get_date_string_from_system()
	candidate.profile["restored_today_count"] = 0
	candidate.inventory.hint = 9223372036854775806 if reason == "overflow" else 5
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, reason + ": publish valid compensation eligibility")
	var before: Dictionary = game.get_core_store().snapshot()
	var revision: int = game.get_core_store().revision()
	var requests: Array = [{"entry": a}, {"entry": b}]
	if reason == "later_ineligible":
		requests[1] = {"entry": {"show_id": "missing", "source": "props_normal_hint", "ts": now}}
	elif reason == "invalid_request":
		requests[1] = {"entry": "not_a_record"}
	var result: Dictionary = game.claim_restored_rewards(requests)
	var expected_error: String = "no_longer_eligible" if reason == "later_ineligible" else reason
	_check(not result.ok and result.error == expected_error, reason + ": later item rejects the entire claim before commit")
	_check(game.get_core_store().revision() == revision and game.get_core_store().snapshot() == before, reason + ": rejected claim changes no authoritative state")
	_check(game.get_pending_rewards() == before.profile.pending_rewards, reason + ": first staged item retains its live eligibility")
	_check(game.get_tool_count("hint") == before.inventory.hint and game.get_restored_today_count() == 0, reason + ": no inventory or daily quota is published")
	_check(game.set_sound_on(not game.is_sound_on()), reason + ": subsequent unrelated setting saves successfully")
	var disk: Dictionary = game._product_store.files.load_result().config.get_value("core", "state")
	_check(disk.profile.pending_rewards == before.profile.pending_rewards and disk.claims == before.claims, reason + ": unrelated save preserves both entitlements without false claim receipts")
	_check(disk.inventory == before.inventory and disk.profile.restored_today_count == 0, reason + ": disk retains the pre-claim inventory and quota")
	if reason == "overflow":
		_check(game.set_tool_count("hint", 5), "restore realistic inventory for an explicit successful retry")
	var retried: Dictionary = game.claim_restored_rewards([{"entry": a}, {"entry": b}])
	_check(retried.ok and game.get_pending_rewards().is_empty() and game.get_tool_count("hint") == 7, reason + ": corrected retry can still claim both original entitlements once")
	_check(game.claim_restored_rewards([{"entry": a}, {"entry": b}]).status == "already_applied" and game.get_tool_count("hint") == 7, reason + ": successful retry remains idempotent")


func _test_query_ownership() -> void:
	_check(game.reset_all(), "reset query ownership fixture")
	var revision: int = game.get_core_store().revision()
	var main: Dictionary = game.get_main_progress(99, 99)
	var lk: Dictionary = game.get_lkmod_progress(99, 99)
	_check(main == {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0} and lk == {"idx": 0}, "missing progress reads preserve legacy defaults")
	main.regular = 8
	lk.idx = 8
	_check(game.get_main_bank_progress_snapshot().is_empty() and game.get_lkmod_progress_snapshot().is_empty(), "reading and editing absent progress creates no live records")
	_check(game.get_core_store().revision() == revision, "progress queries perform no save")
	var main_input := {"idx": 3, "since_lk": 1, "transform": 0}
	var lk_input := {"idx": 2}
	var retry_input := {"regions": [[0, 0], [1, 1]], "solution": [0, 1]}
	game.set_main_progress(4, 1, "", main_input)
	game.set_lkmod_progress(4, 1, lk_input)
	game.set_retry_puzzle(12, retry_input)
	main_input.idx = 99
	lk_input.idx = 99
	retry_input.regions[0][0] = 99
	main = game.get_main_progress(4, 1)
	lk = game.get_lkmod_progress(4, 1)
	var retry: Dictionary = game.get_retry_puzzle(12)
	_check(main.idx == 3 and lk.idx == 2 and retry.regions[0][0] == 0, "setters own their dictionary inputs")
	main.idx = 77
	lk.idx = 77
	retry.regions[0][0] = 77
	_check(game.get_main_progress(4, 1).idx == 3 and game.get_lkmod_progress(4, 1).idx == 2, "progress getters return independent values")
	_check(game.get_retry_puzzle(12).regions[0][0] == 0 and game.get_retry_puzzle(13).is_empty(), "retry query isolates nested data and preserves level matching")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
