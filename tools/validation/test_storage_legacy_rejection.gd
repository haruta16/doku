## 损坏旧奖励输入应产生明确拒绝，不能先在迁移 typed loop 中中断脚本。
extends SceneTree
const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const PASSWORD := "legacy-rejection-test"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var invalid: Array = [7, null, "broken", [], {"uid": "not-an-integer", "items": [{"kind": "hint", "count": 1}]}]
	for index: int in invalid.size():
		_test_rejection(index, invalid[index])
	print("STORAGE LEGACY REJECTION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rejection(index: int, invalid: Variant) -> void:
	var dir: String = "user://legacy-rejection-" + str(index)
	DirAccess.make_dir_recursive_absolute(dir)
	var player := FileStore.new(PASSWORD, dir, false, dir.path_join("player.cfg"))
	var endgame := FileStore.new(PASSWORD, dir, false, dir.path_join("endgame.cfg"))
	var profile := ConfigFile.new()
	profile.set_value("progress", "tool_hint", 5)
	profile.set_value("progress", "tool_locate", 5)
	profile.set_value("progress", "tool_undo", 3)
	profile.set_value("progress", "in_flight_awards", [invalid])
	_check(player.save_config(profile), "prepare encrypted invalid legacy fixture " + str(index))
	var original_hash: String = FileAccess.get_sha256(dir.path_join("player.cfg"))
	var product := ProductStore.new(dir, PASSWORD)
	var result: Dictionary = product.open(ConfigFile.new(), player, endgame, dir.path_join("no-streak.cfg"))
	_check(not result.get("ok", false) and result.get("status") == "invalid_legacy", "invalid nested legacy award is rejected before projection " + str(index))
	_check(not product.core.is_open() and product.files.load_result().get("status") == "missing", "rejection leaves core unopened and uncreated")
	_check(FileAccess.get_sha256(dir.path_join("player.cfg")) == original_hash, "rejection preserves original recoverable file")
	profile.set_value("progress", "in_flight_awards", [{"uid": 4, "items": [{"kind": "hint", "count": 2}], "reason": "old_reward", "display_type": 0}])
	_check(player.save_config(profile), "repair only temporary legacy fixture")
	var recovered := ProductStore.new(dir, PASSWORD)
	_check(recovered.open(ConfigFile.new(), player, endgame, dir.path_join("no-streak.cfg")).get("ok", false), "valid replacement can migrate after refusal")
	_check(recovered.core.snapshot().award_sequence == 4 and recovered.core.snapshot().pending_awards.size() == 1, "valid older reward retains its sequence and entitlement")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
