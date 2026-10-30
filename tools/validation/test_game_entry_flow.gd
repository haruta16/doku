## 真正通过 UIManager 进入普通关，覆盖选题提交、页面退出与残局恢复。
extends SceneTree

var _checks: int = 0

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var ui: Node = root.get_node("UIManager")
	var game: Node = root.get_node("GameState")
	var page: Variant = ui.show_ui("game", {"level_index": game.get_current_level()})
	await create_timer(1.0).timeout
	_check(page != null and not page._puzzle.is_empty(), "actual UI entry resolves puzzle")
	_check(page._entry_error.is_empty(), "actual UI entry has no resolution failure")
	var checkpoint: Dictionary = game.get_endgame_snapshot()
	_check(not checkpoint.is_empty(), "new level selection commits initial checkpoint")
	_check(checkpoint.get("regionMap") == page._puzzle.regions, "selected checkpoint and visible puzzle match")
	_check(not game.get_retry_puzzle(game.get_current_level()).is_empty(), "selection commits retry puzzle")
	var progress_before: Dictionary = game.get_core_store().snapshot().profile.bank_progress.duplicate(true)
	var original_regions: Array = page._puzzle.regions.duplicate(true)
	page._entry_anim_playing = false
	var response: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(response.get("ok", false), "real selected level supports independent hint")
	var round_id: String = str(response.get("round_id", ""))
	var remaining: int = game.get_tool_count("hint")
	page._flush_endgame_snapshot()
	ui.hide_ui("game")
	await create_timer(0.4).timeout
	page = ui.show_ui("game", {"level_index": game.get_current_level()})
	await create_timer(1.0).timeout
	_check(page._puzzle.regions == original_regions, "UI re-entry restores same resolved puzzle")
	_check(game.get_core_store().snapshot().profile.bank_progress == progress_before, "restoring does not advance bank cursors")
	page._entry_anim_playing = false
	var requested_again: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(requested_again.get("ok", false) and requested_again.get("round_id") == round_id, "UI restore preserves business round identity")
	_check(game.get_tool_count("hint") == remaining - 1 and requested_again.result.hint_token != response.result.hint_token, "new hint request after page restore purchases a fresh hint")
	ui.hide_ui("game")
	await create_timer(0.4).timeout
	print("GAME ENTRY FLOW: checks=%d failures=%d" % [_checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)
