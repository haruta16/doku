## 直接调用产品结算，证明不需要页面、GameState 或文件；提交与通知仍由外层负责。
extends SceneTree

const Settlement = preload("res://products/meowdoku/gameplay/application/meowdoku_round_settlement.gd")
const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const DokuModule = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const POLICY := {"retry_once": false, "tool_revive": true, "any_action": false, "next_is_skip": true}
const TODAY := "2026-10-27"

# stage 只询问存储是否可用；若意外调用 snapshot/commit，本夹具会直接报错。
class OpenStore extends RefCounted:
	func is_open() -> bool:
		return true

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var economy := Economy.new(OpenStore.new())
	var original := _fixture()
	var candidate := original.duplicate(true)
	var runtime := {"board": [[1]]}
	var request := Settlement.main_round("main-1/attempt#0", 21, "win", runtime)
	runtime.board[0][0] = 0
	var policy := request.saved_dda_policy(candidate)
	_check(policy == POLICY, "product request reads the frozen DDA policy")
	var won: Dictionary = request.stage(candidate, economy, TODAY, policy)
	_check(won.ok and not won.duplicate, "main settlement runs without a page or storage commit")
	_check(candidate.profile.current_level == 22 and candidate.inventory.hint == 7, "progress and frozen reward enter the same candidate")
	_check(candidate.round_runtime.dda_pending_demote and candidate.profile.current_strategy == 3, "frozen skip policy defers the demotion")
	_check(candidate.profile.today_played_count == 1 and candidate.endgame.snapshot.is_empty(), "play count and endgame cleanup are staged together")
	_check(candidate.round_services["doku/main"].status == "settled" and candidate.product_settlements.main.last_attempt == 0, "host and product receipt advance together")
	_check(won.grants.size() == 1 and won.grants[0].count == 2 and candidate.pending_awards.is_empty(), "fixed reward is fully claimed in the candidate")
	_check(original == _fixture(), "staging does not publish or mutate the source snapshot")
	var after_win := candidate.duplicate(true)
	var duplicate: Dictionary = request.stage(candidate, economy, TODAY, policy)
	_check(duplicate.ok and duplicate.duplicate and candidate == after_win, "duplicate settlement changes no candidate field")
	var conflict := Settlement.main_round("main-1/attempt#0", 21, "quit").stage(candidate, economy, TODAY, policy)
	_check(not conflict.ok and conflict.error == "settlement_conflict", "conflicting repeat keeps the stable failure code")
	var invalid := original.duplicate(true)
	invalid.round_services["doku/main"].snapshot.content.level_definition.reward.hint = -1
	var invalid_reward := request.stage(invalid, economy, TODAY, policy)
	_check(not invalid_reward.ok and invalid_reward.error == "invalid_saved_level_definition" and original == _fixture(), "late validation failure remains unpublished and caller can discard the candidate")
	var daily_candidate := original.duplicate(true)
	daily_candidate.round_services["doku/daily"] = original.round_services["doku/main"].duplicate(true)
	daily_candidate.round_services["doku/daily"].round_id = "daily-1"
	var daily := Settlement.daily_round("daily-1/attempt#0", TODAY, "win", 69, 93.5, {"board": [[1]]})
	var daily_result := daily.stage(daily_candidate, economy, TODAY, {})
	_check(daily_result.ok and daily_candidate.profile.daily_elapsed_sec == 69, "daily result also runs without global services")
	_check(daily_candidate.profile.current_level == 21 and daily_candidate.inventory == original.inventory and daily_candidate.endgame == original.endgame, "daily result preserves parked main progress, reward and endgame")
	var legacy_candidate := original.duplicate(true)
	legacy_candidate.endgame.snapshot = {"level": 21, "size": 1, "solution": [0], "placed_cats": [[0, 0]]}
	var legacy := Settlement.legacy_main(21)
	var legacy_result := legacy.stage(legacy_candidate, economy, TODAY, POLICY)
	_check(legacy_result.ok and legacy_candidate.profile.current_level == 22 and legacy_candidate.inventory == original.inventory, "legacy completion advances once without inventing a reward")
	_check(legacy_candidate.profile.get("today_played_count", 0) == 0 and legacy.stage(legacy_candidate, economy, TODAY, POLICY).duplicate, "legacy completion does not recount the game and remains idempotent")
	print("PRODUCT SETTLEMENT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture() -> Dictionary:
	var cfg := ConfigFile.new()
	var profile := {"current_level": 21, "current_strategy": 3, "consecutive_clean_wins": 0, "consecutive_fails": 0, "consecutive_retry_levels": 0, "retry_tracking_strategy": 0, "today_date": TODAY}
	for key: String in profile:
		cfg.set_value("progress", key, profile[key])
	var state := ProductStore.from_legacy(cfg, null, {})
	state["round_runtime"] = {"current_level_dirty": true, "current_level_retried": false, "demoted_this_level": false, "dda_tool_or_revive_used": true, "dda_revive_used": false, "dda_pending_demote": false, "is_daily_first_easy_level": false, "rnr_mod1_exempt": false, "rnr_g_prev_was_max": false}
	state.endgame.snapshot = {"version": 2, "level": 21}
	var created := DokuModule.new().create_snapshot({
		"board": [[0]], "regions": [[0]], "solution": [[true]],
		"content": {"level": 21, "gameplay_policy": {"dda": POLICY}, "level_definition": {
			"puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1}, "reward": {"hint": 2},
		}},
	})
	state.round_services["doku/main"] = {"round_id": "main-1", "status": "active", "snapshot": created.snapshot}
	return state


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
