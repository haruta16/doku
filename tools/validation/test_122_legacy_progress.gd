## 两个原 1.22 开发诊断入口使用完整选题/结算候选，禁止触碰真实用户目录或服务。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var files: RefCounted
var signals_seen: Array = []
var level_data: Variant

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-") or not ProjectSettings.get_setting("doku/validation/offline", false):
		quit(2)
		return
	game = root.get_node("GameState")
	files = game.get_core_store().get("_file_store")
	level_data = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_level.set_debug_override(0)
	game.level_settled.connect(_on_settled)
	_test_legacy_api()
	_test_plan_transaction()
	_test_fastjump()
	_test_fastjump_elo()
	await _test_simulator()
	game.level_settled.disconnect(_on_settled)
	ab.normal_level.clear_debug_override()
	await process_frame
	print("122 LEGACY PROGRESS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_legacy_api() -> void:
	_check(game.reset_all(), "reset legacy API fixture")
	var before: Dictionary = game.get_core_candidate()
	signals_seen.clear()
	_fault(true)
	_check(not game.on_level_won(1), "legacy win propagates write failure")
	_check(game.get_core_candidate() == before and signals_seen.is_empty(), "failed win publishes neither state nor settlement signal")
	_fault(false)
	_check(game.on_level_won(1), "old six-argument compatible API still executes 1.22 progression")
	_check(game.get_current_level() == 2 and signals_seen == [true], "successful compatibility win advances once and publishes")
	_check(not game.on_level_won(1), "stale normal level cannot settle again without a matching receipt")
	before = game.get_core_candidate()
	signals_seen.clear()
	_fault(true)
	_check(not game.on_level_failed(2), "legacy failure also propagates write failure")
	_check(game.get_core_candidate() == before and signals_seen.is_empty(), "failed loss leaves retry and DDA facts unchanged")
	_fault(false)
	_check(game.on_level_failed(2), "legacy failure executes via pure progression")
	_check(game.get_current_level() == 2 and game.get_core_candidate().round_runtime.current_level_retried and signals_seen == [false], "loss keeps level and commits retry fact once")

func _test_plan_transaction() -> void:
	_check(game.reset_all(), "reset plan transaction fixture")
	var before: Dictionary = game.get_core_candidate()
	var plan: Dictionary = level_data.resolve_level_entry(1)
	_check(plan.get("ok", false) and game.get_core_candidate() == before, "diagnostic selection itself is pure")
	var revision: int = game.get_core_store().revision()
	_fault(true)
	_check(not game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan), "selection and win fail together")
	_check(game.get_core_candidate() == before and game.get_core_store().revision() == revision, "write fault cannot consume selection or advance progress")
	_fault(false)
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan), "same plan retries after write failure")
	_check(game.get_current_level() == 2 and not game.get_recent_puzzles().is_empty(), "committed win retains real delivered puzzle record")
	revision = game.get_core_store().revision()
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan) and game.get_core_store().revision() == revision, "same plan receipt cannot advance or write twice")
	_check(not game.on_level_failed(1, LevelKind.MAIN, plan), "same plan cannot change terminal outcome")

func _test_fastjump() -> void:
	_check(game.reset_all(), "reset fastjump fixture")
	var commands: Node = load("res://products/meowdoku/app/diagnostics/cheat_commands.gd").new()
	var before: Dictionary = game.get_core_candidate()
	_fault(true)
	var summary: Dictionary = commands._run_fastjump(1)
	_check(summary.completed == 0 and summary.final_level == 1, "actual fastjump stops at failed commit")
	_check(game.get_core_candidate() == before, "actual fastjump failure keeps pending precat and cursor unchanged")
	_fault(false)
	summary = commands._run_fastjump(2)
	_check(summary.completed == 2 and summary.final_level == 3, "actual fastjump commits each selected level")
	_check(game.get_recent_puzzles().size() == 2, "fastjump commits selection delivery exactly once per level")
	commands.free()

func _test_fastjump_elo() -> void:
	_check(game.reset_all(), "reset fastjump Elo fixture")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_level.set_debug_override(12207)
	game.set_current_level(21)
	game.set_current_strategy(3)
	var commands: Node = load("res://products/meowdoku/app/diagnostics/cheat_commands.gd").new()
	var before: Dictionary = game.get_core_candidate()
	_fault(true)
	var summary: Dictionary = commands._run_fastjump(1)
	_check(summary.completed == 0 and game.get_core_candidate() == before, "actual Elo fastjump cannot publish attempt or rating before write")
	_fault(false)
	summary = commands._run_fastjump(1)
	_check(summary.completed == 1 and summary.final_level == 22, "actual Elo fastjump runs frozen v2 strategy successfully")
	_check(not game.get_recent_puzzles().is_empty(), "Elo fastjump retains delivered identity with progression")
	commands.free()
	ab.normal_level.set_debug_override(0)

func _test_simulator() -> void:
	var packed: PackedScene = load("res://products/meowdoku/app/diagnostics/ui/playtest_simulator_page.tscn")
	var page: Node = packed.instantiate()
	root.add_child(page)
	var before: Dictionary = game.get_core_candidate()
	_fault(true)
	var result: Dictionary = page._run_simulation(3)
	_check(not result.get("ok", false) and game.get_core_candidate() == before, "real simulator cannot start after failed reset")
	_fault(false)
	var original_rnr: int = root.get_node("ABTestManager").rule_normal_rank.value()
	page._rnr_input.text = "7"
	page._sc_input.text = ""
	var fault: Dictionary = {"writes": 0, "before": {}}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase != "before_replace":
			return false
		fault.writes += 1
		if fault.writes == 1:
			return false
		if fault.before.is_empty():
			fault.before = game.get_core_candidate()
		return true
	)
	result = page._run_simulation(3)
	_check(not result.get("ok", false) and int(fault.writes) >= 2, "real simulator stops when selected round cannot commit")
	_check(game.get_core_candidate() == fault.before and game.get_recent_puzzles().is_empty(), "simulator failure publishes no delivery, dirty flag, or retry cache")
	_check(root.get_node("ABTestManager").rule_normal_rank.value() == original_rnr, "simulator failure releases temporary AB override")
	_fault(false)
	page._rnr_input.text = ""
	seed(122)
	result = page._run_simulation(8)
	_check(result.get("ok", false) and FileAccess.file_exists(str(result.get("report_path", ""))), "real simulator completes and keeps report generation")
	_check(not game.get_recent_puzzles().is_empty(), "real simulator commits the delivered history used by its report")
	_check(game.reset_all(), "reset cached simulator fixture")
	var loss_plan: Dictionary = level_data.resolve_level_entry(1)
	_check(game.on_level_failed(1, LevelKind.MAIN, loss_plan), "diagnostic loss commits selected retry puzzle")
	var cached: Dictionary = game.get_retry_puzzle(1)
	var retry_entry: Dictionary = {"size": cached.get("bank_size", 0), "regionMap": cached.get("prebuilt_regions", []), "solution": cached.get("prebuilt_solution", []), "_bank_rank": cached.get("bank_rank", 1)}
	before = game.get_core_candidate()
	var retry_plan: Dictionary = page._prepare_cached_simulation_plan(1, retry_entry, cached)
	_check(retry_plan.get("ok", false) and game.get_core_candidate() == before, "simulator cached retry preparation remains pure")
	_check(not str(retry_plan.get("puzzle_id", "")).is_empty() and retry_plan.puzzle_id == loss_plan.puzzle_id, "simulator retry retains original delivered puzzle identity")
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, retry_plan) and game.get_current_level() == 2, "simulator cached retry settles original puzzle through candidate bridge")
	_check(game.get_retry_puzzle(1).is_empty(), "successful retry clears cached failed puzzle in same transaction")
	page.queue_free()
	await process_frame

func _on_settled(won: bool) -> void:
	signals_seen.append(won)

func _fault(enabled: bool) -> void:
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return enabled and phase == "before_replace")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ASSERT FAILED: " + message)
