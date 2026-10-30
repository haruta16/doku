## 旧权益 API 兼容的候选事务、完成重试及提交通知重入；1.22 已退役自动标叉弹窗。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var files: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	files = game.get_core_store().get("_file_store")
	game.set_sound_on(false)
	await _test_free_entitlement()
	await _test_confirmed_entitlement()
	await _test_pending_observers()
	await _test_tutorial_completion()
	ui.hide_all()
	await create_timer(0.7).timeout
	for name: String in ["tutorial", "game", "confirm", "toast"]:
		ui.destroy_ui(name)
	await process_frame
	print("PRODUCT ENTITLEMENT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_free_entitlement() -> void:
	_prepare_auto_mark(false)
	var attempts := {"count": 0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			attempts.count += 1
			return attempts.count == 2
		return false)
	var result: Dictionary = game.activate_daily_auto_mark(true)
	_check(result.get("ok", false) and attempts.count == 1, "免费资格与权益只有一次文件提交")
	_check(_saved().profile.daily_auto_mark_free_consumed and _saved().profile.daily_auto_mark_enabled, "不存在第二次失败造成半笔权益")
	files.set_fault_injector_for_tests(Callable())
	var revision: int = game.get_core_store().revision()
	_check(game.activate_daily_auto_mark(true).get("duplicate", false), "当日已激活权益重试返回重复成功")
	_check(game.get_core_store().revision() == revision, "重复激活不重复写盘")
	_prepare_auto_mark(false)
	var before: Dictionary = game.get_core_candidate()
	_fail_writes()
	result = game.activate_daily_auto_mark(true)
	_check(not result.get("ok", false) and game.get_core_candidate() == before, "免费保存失败不消费资格也不发布权益")
	files.set_fault_injector_for_tests(Callable())
	_check(game.activate_daily_auto_mark(true).get("ok", false) and _saved().profile.daily_auto_mark_enabled, "同一次免费资格可直接重试保存")
	_prepare_auto_mark(true)
	_check(game.activate_daily_auto_mark(true).get("error") == "daily_auto_mark_free_unavailable", "已消费免费机会不能再次免费激活")
	_check(not _saved().profile.daily_auto_mark_enabled, "资格拒绝不启用权益")


func _test_confirmed_entitlement() -> void:
	# 仅验证已确认资格进入本地事务；已删除的旧广告界面不属于 1.22 产品。
	_prepare_auto_mark(true)
	var today: String = Time.get_date_string_from_system()
	var before: Dictionary = game.get_core_candidate()
	_fail_writes()
	var result: Dictionary = game.activate_daily_auto_mark(false, today)
	_check(not result.get("ok", false) and game.get_core_candidate() == before, "已确认资格写失败不假启用")
	files.set_fault_injector_for_tests(Callable())
	_check(game.activate_daily_auto_mark(false, today).get("ok", false) and _saved().profile.daily_auto_mark_enabled, "已确认资格可直接重试保存")
	var revision: int = game.get_core_store().revision()
	_check(game.activate_daily_auto_mark(false, today).get("duplicate", false) and game.get_core_store().revision() == revision, "已确认资格重复调用不重写")
	_prepare_auto_mark(true)
	before = game.get_core_candidate()
	result = game.activate_daily_auto_mark(false, "2000-01-01")
	_check(result.get("error") == "daily_auto_mark_date_changed" and game.get_core_candidate() == before, "旧日期资格不会启用新日权益")
	var old_day: Dictionary = game.get_core_candidate()
	old_day.profile.today_date = "2000-01-01"
	old_day.profile.daily_auto_mark_enabled = true
	_check(game.commit_core_candidate(old_day, game.get_core_store().revision()).get("ok", false), "准备上一日已激活权益")
	before = game.get_core_candidate()
	_fail_writes()
	result = game.activate_daily_auto_mark(false, today)
	_check(not result.get("ok", false) and game.get_core_candidate() == before, "跨日激活失败不提前单独提交日期轮换")
	files.set_fault_injector_for_tests(Callable())
	revision = game.get_core_store().revision()
	result = game.activate_daily_auto_mark(false, today)
	_check(result.get("ok", false) and game.get_core_store().revision() == revision + 1, "日期轮换与新日权益同一次提交")
	_check(_saved().profile.today_date == today and _saved().profile.daily_auto_mark_enabled and _saved().profile.daily_auto_mark_free_consumed, "新日已确认资格保留终身免费消费事实")


func _test_pending_observers() -> void:
	var candidate: Dictionary = game.get_core_candidate()
	candidate.endgame.stats.main_total = {}
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "准备通知重入统计")
	game.inc_game_total_stat("main", "before_commit", 2)
	game.tool_count_changed.connect(func(_kind: String, _count: int) -> void:
		game.inc_game_total_stat("main", "from_observer"), CONNECT_ONE_SHOT)
	_check(game.set_tool_count("hint", game.get_tool_count("hint") + 1), "库存提交通知观察者")
	_check(_saved().endgame.stats.main_total.get("before_commit") == 2, "本次提交包含先前待保存统计")
	_check(_saved().endgame.stats.main_total.get("from_observer", 0) == 0, "通知中新登记的数据尚未宣称落盘")
	_check(game.get_game_total_stat("main", "from_observer") == 1 and game.get("_endgame_dirty"), "外层提交收尾保留观察者新统计")
	await create_timer(0.6).timeout
	_check(_saved().endgame.stats.main_total.get("from_observer") == 1, "观察者统计随后正常合并且只保存一次")

	# 观察者新增统计后，独立库存服务又提交；不能误当成外层GameState候选清理统计。
	game.tool_count_changed.connect(func(_kind: String, _count: int) -> void:
		game.inc_game_total_stat("main", "independent_nested")
		var award: Dictionary = game.get_economy_service().register_award([{"kind": "hint", "count": 1}], 0, "observer_test")
		_check(award.get("ok", false), "同步观察者可以执行独立奖励登记"), CONNECT_ONE_SHOT)
	game.set_tool_count("hint", game.get_tool_count("hint") + 1)
	_check(game.get_game_total_stat("main", "independent_nested") == 1 and game.get("_endgame_dirty"), "独立嵌套提交保留观察者pending")
	await create_timer(0.6).timeout
	_check(_saved().endgame.stats.main_total.get("independent_nested") == 1, "嵌套独立提交后的统计最终落盘")

	# 自有嵌套提交纳入第一笔统计；其后新增的第二笔仍应保留给下一次合并。
	game.tool_count_changed.connect(func(_kind: String, _count: int) -> void:
		game.inc_game_total_stat("main", "owned_nested")
		_check(game.set_people_on(not game.is_people_on()), "同步观察者可以提交偏好")
		game.inc_game_total_stat("main", "owned_nested"), CONNECT_ONE_SHOT)
	game.set_tool_count("hint", game.get_tool_count("hint") + 1)
	_check(_saved().endgame.stats.main_total.get("owned_nested") == 1 and game.get_game_total_stat("main", "owned_nested") == 2, "嵌套提交仅确认其包含的统计")
	_check(game.get("_endgame_dirty"), "内外提交返回后仍保留最后一笔pending")
	await create_timer(0.6).timeout
	_check(_saved().endgame.stats.main_total.get("owned_nested") == 2 and not game.get("_endgame_dirty"), "内外通知后的统计完整保存且不重复")


func _test_tutorial_completion() -> void:
	_check(game.set_tutorial_done(false), "准备未完成教程")
	var page: Variant = ui.show_ui("tutorial")
	# 结束旧教学等待，再驱动真实结束步骤和确认按钮。
	page._flow_token += 1
	page._step_completed.emit()
	page._step_finish()
	_fail_writes()
	page._confirm_btn.tag_pressed.emit()
	_check(not game.is_tutorial_done() and not _saved().profile.tutorial_done, "教程完成写失败保留未完成标记")
	_check(not ui.has_ui("game"), "保存失败没有提前创建正式游戏页")
	_check(page._current_mode == page.StepMode.CONFIRM and page._confirm_btn.visible, "保存失败回到结束确认按钮可重试")
	files.set_fault_injector_for_tests(Callable())
	page._confirm_btn.tag_pressed.emit()
	await create_timer(0.6).timeout
	_check(game.is_tutorial_done() and _saved().profile.tutorial_done, "完成确认重试持久保存")
	var gameplay: Variant = ui.get_ui("game")
	_check(gameplay != null and gameplay.visible and gameplay._entry_error.is_empty(), "保存成功后进入真实首局")
	var generation: int = gameplay._business_generation
	_check(page.complete_tutorial(), "重复完成返回成功")
	_check(gameplay._business_generation == generation, "重复完成不再次刷新或启动首局")


func _prepare_auto_mark(free_consumed: bool) -> void:
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile.today_date = Time.get_date_string_from_system()
	candidate.profile.daily_auto_mark_enabled = false
	candidate.profile.daily_auto_mark_free_consumed = free_consumed
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "准备当日自动标叉资格")


func _saved() -> Dictionary:
	return game.get_core_store().snapshot()


func _fail_writes() -> void:
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + description)
