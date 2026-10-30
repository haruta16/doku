## 真实设置页、合并统计与重置的组合故障回归；只在临时工程中运行。
extends SceneTree

const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")

var _checks: int = 0
var _failures: int = 0
var _reset_events: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: 必须通过 tools/run_validation.py 隔离运行")
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var game: Node = root.get_node("GameState")
	_check(game.is_storage_ready(), "真实核心存档已经打开")
	await _test_coalesced_stats(game)
	await _test_settings_pages(game)
	_test_debug_locale(game)
	_test_reset_defaults(game)
	print("STORAGE PREFERENCES TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_coalesced_stats(game: Node) -> void:
	var files: RefCounted = game._product_store.files
	var core: RefCounted = game.get_core_store()
	var saved_board := {"level": 5, "fixture": "accepted"}
	_check(game.set_endgame_snapshot(saved_board), "准备已保存残局")
	game.inc_game_total_stat("main", "combined_failure")
	game.persist_game_round_stats("main", {"moves": 3})
	_fail_writes(files)
	_check(not game.set_sound_on(false), "无关设置写失败返回 false")
	_check(game.is_sound_on(), "失败设置不发布新状态")
	_check(game.get_game_total_stat("main", "combined_failure") == 1, "设置失败保留已接收累计统计")
	_check(game.get_game_round_stats("main").get("moves") == 3, "设置失败保留已接收本局统计")
	_check(not game.set_endgame_snapshot({"level": 6, "fixture": "rejected"}), "随后棋盘保存也可失败")
	_check(game.get_endgame_snapshot() == saved_board, "保留待合并统计不会接受失败棋盘")
	_check(not game.reset_all(), "统计待保存期间重置失败")
	_check(game.get_game_total_stat("main", "combined_failure") == 1, "失败重置不能清掉此前已接收统计")
	_check(game.get_endgame_snapshot() == saved_board, "失败重置恢复已保存残局")
	files.set_fault_injector_for_tests(Callable())
	var economy: RefCounted = game.get_economy_service()
	var award: Dictionary = economy.register_award([{"kind": "hint", "count": 2}], 0, "pending_stats_test")
	_check(award.get("ok", false), "独立奖励登记成功")
	_check(economy.claim_award(award.uid).get("ok", false), "独立库存提交成功")
	_check(game.get_game_total_stat("main", "combined_failure") == 1, "独立库存提交保留待合并统计")
	_check(core.snapshot().endgame.stats.main_total.get("combined_failure", 0) == 0, "独立库存提交不谎称统计已经保存")
	await create_timer(0.6).timeout
	var disk := _disk_state(files)
	_check(disk.endgame.stats.main_total.get("combined_failure") == 1, "合并定时器最终保存统计且不重复计数")
	_check(disk.endgame.stats.main_round.get("moves") == 3 and disk.endgame.snapshot == saved_board, "最终磁盘保留统计与原棋盘")
	_check(not game._endgame_dirty, "成功合并清除待保存标志")
	# 再覆盖定时器本身失败、后续业务提交恢复这一组合。
	game.inc_game_total_stat("daily", "timer_retry", 2)
	_fail_writes(files)
	await create_timer(0.6).timeout
	_check(game.get_game_total_stat("daily", "timer_retry") == 2 and game._endgame_dirty, "定时写失败仍保留待保存统计")
	files.set_fault_injector_for_tests(Callable())
	_check(game.set_people_on(false), "后续业务保存可重试尚未落盘统计")
	disk = _disk_state(files)
	_check(disk.endgame.stats.daily_total.get("timer_retry") == 2, "后续提交落盘统计且只计一次")


func _test_settings_pages(game: Node) -> void:
	_check(game.reset_all(), "设置测试恢复默认值")
	var files: RefCounted = game._product_store.files
	var ui: Node = root.get_node("UIManager")
	ui.show_ui("setting")
	await process_frame
	var page: Node = ui.get_ui("setting")
	_check(page != null and page.is_showing(), "创建真实设置页")
	if page == null:
		return
	var options := ["music", "sound", "vibration", "people"]
	for option: String in options:
		_fail_writes(files)
		page.call("_on_%s_btn_pressed" % option)
		_check(bool(game.call("is_%s_on" % option)), option + " 失败保持已保存值")
		var toggle: Panel = page.get("_%s_toggle_on" % option)
		_check(toggle.visible, option + " 失败仍显示开启")
		_check(Toast._current.get_node("Panel/Label").text.contains("重试") or Toast._current.get_node("Panel/Label").text.contains("try again"), option + " 失败展示重试提示")
		if option == "vibration":
			_check(VibrateManager.is_enabled(), "震动写失败未提前关闭运行时震动")
		files.set_fault_injector_for_tests(Callable())
		page.call("_on_%s_btn_pressed" % option)
		_check(not bool(game.call("is_%s_on" % option)) and not toggle.visible, option + " 重试成功后状态与界面同步")
		if option == "vibration":
			_check(not VibrateManager.is_enabled(), "成功提交后才同步运行时震动")
		await process_frame
	# 页面缓存期间通过业务入口修改，下一次展示仍应反映全部四个偏好。
	await ui.hide_ui("setting")
	_check(game.set_sound_on(true) and game.set_vibration_on(true), "隐藏期间更新声音与震动")
	ui.show_ui("setting")
	await process_frame
	_check(page._sound_toggle_on.visible and page._vibration_toggle_on.visible, "缓存页面再次显示同步声音与震动")
	await ui.hide_ui("setting")
	ui.show_ui("language")
	await process_frame
	var language: Node = ui.get_ui("language")
	_check(language != null and language.is_showing(), "创建真实语言选择页")
	if language == null:
		return
	var original_locale := TranslationServer.get_locale()
	var original_saved: String = game.get_apply_locale()
	var selected_locale: String = ""
	for index: int in language._display.size():
		var locale: String = language._display[index].locale
		if TranslationServer.standardize_locale(locale) != original_locale:
			language._selected_index = index
			selected_locale = locale
			break
	_check(not selected_locale.is_empty(), "找到不同的目标语言")
	_fail_writes(files)
	language._on_yes_pressed()
	_check(language.is_showing() and not language._confirmed, "语言写失败保留选择页并允许重试")
	_check(TranslationServer.get_locale() == original_locale and game.get_apply_locale() == original_saved, "语言写失败不切运行时或持久偏好")
	files.set_fault_injector_for_tests(Callable())
	language._on_yes_pressed()
	_check(language._confirmed and game.get_apply_locale() == selected_locale, "语言重试先提交偏好")
	_check(TranslationServer.get_locale() == TranslationServer.standardize_locale(selected_locale), "提交成功后发布运行时语言")
	await create_timer(0.6).timeout
	_check(language.is_hidden(), "成功确认后关闭语言页")


func _test_debug_locale(game: Node) -> void:
	var commands: Node = load("res://products/meowdoku/app/diagnostics/cheat_commands.gd").new()
	var files: RefCounted = game._product_store.files
	var original_locale := TranslationServer.get_locale()
	var original_saved: String = game.get_apply_locale()
	_fail_writes(files)
	commands._apply_locale("ja")
	_check(TranslationServer.get_locale() == original_locale and game.get_apply_locale() == original_saved, "调试语言切换失败也不发布新语言")
	commands._apply_locale("system")
	_check(TranslationServer.get_locale() == original_locale and game.get_apply_locale() == original_saved, "调试清除语言覆盖失败不切换到系统语言")
	files.set_fault_injector_for_tests(Callable())
	commands._apply_locale("ja")
	_check(game.get_apply_locale() == "ja" and TranslationServer.get_locale() == "ja", "调试切换重试成功后同步语言")
	commands._apply_locale("system")
	_check(game.get_apply_locale().is_empty(), "调试清除覆盖重试成功")
	commands.free()


func _test_reset_defaults(game: Node) -> void:
	var fresh: Node = game.get_script().new()
	var defaults: ConfigFile = fresh._encode_profile_config()
	fresh.free()
	var candidate: Dictionary = game.get_core_candidate()
	# 所有规范玩家字段都改成非默认值；避免只测本次发现的那一个遗漏。
	for key: String in candidate.profile:
		if not ProductStore.PROFILE_TYPES.has(key):
			continue
		match ProductStore.PROFILE_TYPES[key]:
			TYPE_BOOL: candidate.profile[key] = not bool(defaults.get_value("progress", key))
			TYPE_INT: candidate.profile[key] = int(defaults.get_value("progress", key)) + 7
			TYPE_FLOAT: candidate.profile[key] = float(defaults.get_value("progress", key)) + 0.25
			TYPE_STRING: candidate.profile[key] = "changed"
			TYPE_DICTIONARY: candidate.profile[key] = {"changed": 1}
	candidate.profile.grt_level_d90_reported = [5]
	candidate.profile.grt_reported_events = ["fixture"]
	candidate.profile.pending_rewards = [{"show_id": "fixture", "source": "hint", "ts": 1}]
	candidate.profile.reward_history_ts = [1]
	candidate.profile.recent_puzzles = [{"puzzle_id": "fixture", "level": 5, "v": "1", "src": "test", "ts": 1, "bank_progress": {}, "main_bank_progress": {}, "lkmod_progress": {}}]
	candidate.inventory = {"locate": 8, "hint": 9, "undo": 10}
	candidate.endgame.snapshot = {"fixture": "reset"}
	for key: String in candidate.endgame.stats:
		candidate.endgame.stats[key] = "changed" if key.ends_with("_id") else {"changed": 1}
	_check(game.get_economy_service().stage_award(candidate, [{"kind": "hint", "count": 1}], 0, "reset_fixture").get("ok", false), "重置夹具同时包含待领取奖励")
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "准备非默认的完整玩家状态")
	_test_profile_mapping(candidate, game.get_script())
	game.all_data_reset.connect(func() -> void: _reset_events += 1)
	var before: Dictionary = game.get_core_store().snapshot()
	var files: RefCounted = game._product_store.files
	_fail_writes(files)
	_check(not game.reset_all() and _reset_events == 0, "重置失败不发全量重置事件")
	_check(game.get_core_store().snapshot() == before, "重置失败不改变权威核心")
	_check(game.is_rule_info_bar_collapsed(), "重置失败保留规则栏折叠偏好")
	files.set_fault_injector_for_tests(Callable())
	_check(game.reset_all() and _reset_events == 1, "重置成功仅通知一次")
	var memory: ConfigFile = game._encode_profile_config()
	var disk: ConfigFile = ProductStore.profile_config(_disk_state(files))
	for key: String in ProductStore.PROFILE_TYPES:
		var expected: Variant = defaults.get_value("progress", key)
		_check(memory.get_value("progress", key) == expected and disk.get_value("progress", key) == expected, "重置恢复默认且落盘: " + key)
	_check(VibrateManager.is_enabled(), "重置成功恢复运行时震动默认值")


## 用非默认状态往返检查映射，防止新增字段只更新类型表、读取或写入中的一处。
func _test_profile_mapping(candidate: Dictionary, game_script: Script) -> void:
	var fresh: Node = game_script.new()
	var expected: ConfigFile = ProductStore.profile_config(candidate)
	fresh._apply_profile_config(expected)
	var encoded: ConfigFile = fresh._encode_profile_config()
	var keys := Array(encoded.get_section_keys("progress"))
	var declared: Array = ProductStore.PROFILE_TYPES.keys()
	keys.sort()
	declared.sort()
	_check(keys == declared, "玩家字段编码与类型表完整对应")
	# 残局和分玩法统计归独立分区，profile 编码刻意只保留空兼容槽位。
	var captured: Dictionary = ProductStore.capture_profile(encoded)
	_check(captured.profile == candidate.profile, "非默认玩家字段完整读取/编码往返")
	_check(captured.inventory == candidate.inventory, "非默认库存完整读取/编码往返")
	_check(fresh._capture_endgame() == candidate.endgame, "独立残局与统计分区完整读取/编码往返")
	_check(encoded.get_value("progress", "in_flight_awards") == candidate.pending_awards, "待领取奖励完整读取/编码往返")
	fresh.free()


func _disk_state(files: RefCounted) -> Dictionary:
	var result: Dictionary = files.load_result()
	return result.config.get_value("core", "state")


func _fail_writes(files: RefCounted) -> void:
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("TEST_FAILED: " + label)
