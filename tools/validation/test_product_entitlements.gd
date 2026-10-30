## 现有权益与完成状态：真实按钮、写失败、广告迟到回调、完成重试及提交通知重入。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var kit: Node
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
	kit = root.get_node("UniKitManager")
	files = game.get_core_store().get("_file_store")
	game.set_sound_on(false)
	root.get_node("ABTestManager").game_auto_mark.set_debug_override(5)
	await _test_free_entitlement()
	await _test_ad_entitlement()
	await _test_pending_observers()
	await _test_tutorial_completion()
	ui.hide_all()
	await create_timer(0.7).timeout
	print("PRODUCT ENTITLEMENT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_free_entitlement() -> void:
	_prepare_auto_mark(false)
	var popup: Variant = ui.show_ui("daily_auto_mark_popup")
	var attempts := {"count": 0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			attempts.count += 1
			return attempts.count == 2
		return false)
	popup._primary_btn.pressed.emit()
	await create_timer(0.5).timeout
	_check(attempts.count == 1, "免费资格与权益只有一次文件提交")
	_check(_saved().profile.daily_auto_mark_free_consumed and _saved().profile.daily_auto_mark_enabled, "不存在第二次失败造成半笔权益")
	_check(popup.is_hidden(), "免费权益保存成功后关闭")
	files.set_fault_injector_for_tests(Callable())
	var revision: int = game.get_core_store().revision()
	_check(game.activate_daily_auto_mark(true).get("duplicate", false), "当日已激活权益重试返回重复成功")
	_check(game.get_core_store().revision() == revision, "重复激活不重复写盘")

	_prepare_auto_mark(false)
	popup = ui.show_ui("daily_auto_mark_popup")
	_fail_writes()
	popup._primary_btn.pressed.emit()
	_check(popup.is_showing(), "免费保存失败保留弹窗")
	_check(not _saved().profile.daily_auto_mark_free_consumed and not _saved().profile.daily_auto_mark_enabled, "免费保存失败不消费资格也不发布权益")
	files.set_fault_injector_for_tests(Callable())
	popup._primary_btn.pressed.emit()
	await create_timer(0.5).timeout
	_check(popup.is_hidden() and _saved().profile.daily_auto_mark_enabled, "免费按钮原地重试成功")
	_prepare_auto_mark(true)
	_check(game.activate_daily_auto_mark(true).get("error") == "daily_auto_mark_free_unavailable", "已消费免费机会不能再次免费激活")
	_check(not _saved().profile.daily_auto_mark_enabled, "资格拒绝不启用权益")


func _test_ad_entitlement() -> void:
	_prepare_auto_mark(true)
	kit.cheat_show_reward = true # 真实按钮进入项目Mock广告页，再由其按钮发奖/关闭。
	var popup: Variant = ui.show_ui("daily_auto_mark_popup")
	var rewards := {"count": 0}
	var stale_callbacks: Array[Callable] = []
	var observer := func(_placement: String) -> void:
		rewards.count += 1
	kit.ad_rewarded.connect(observer)
	popup._primary_btn.pressed.emit()
	for callback: Callable in kit._reward_callbacks.values():
		if callback.get_object() == popup:
			stale_callbacks.append(callback)
	_fail_writes()
	var mock_ad: Variant = ui.get_ui("mock_ad")
	_check(mock_ad != null and mock_ad.is_showing(), "实际按钮已打开Mock广告页")
	if mock_ad != null:
		mock_ad.get_node("Root/ButtonRow/RewardButton").pressed.emit()
	await create_timer(0.1).timeout
	_check(rewards.count == 1 and popup._ad_requested, "实际广告入口已收到一次发奖")
	_check(not _saved().profile.daily_auto_mark_enabled and popup.is_showing(), "广告权益保存失败不关闭或假启用")
	_check(not popup._reward_pending_date.is_empty(), "保留已发奖待保存的重试意图")
	_check(not popup._ad_icon_box.visible and not popup._primary_badge.visible, "保存重试不再标为需要广告")
	kit.ad_closed.emit("reward")
	_check(popup.is_showing(), "迟到SDK关闭不能取消权益保存重试")
	await ui.hide_ui("daily_auto_mark_popup")
	popup = ui.show_ui("daily_auto_mark_popup")
	_check(not popup._reward_pending_date.is_empty(), "缓存窗口重开仍保留同日已发奖意图")
	files.set_fault_injector_for_tests(Callable())
	popup._primary_btn.pressed.emit()
	await create_timer(0.5).timeout
	_check(_saved().profile.daily_auto_mark_enabled and popup.is_hidden(), "广告权益可以直接重试保存")
	_check(rewards.count == 1, "保存重试没有请求第二次广告奖励")

	_prepare_auto_mark(true)
	popup = ui.show_ui("daily_auto_mark_popup")
	_check(not stale_callbacks.is_empty(), "捕获了旧显示的真实广告回调")
	for callback: Callable in stale_callbacks:
		callback.call("reward")
	_check(not _saved().profile.daily_auto_mark_enabled and popup.is_showing(), "旧显示的发奖回调不能修改或关闭新弹窗")
	popup._reward_pending_date = "2000-01-01"
	ui.show_ui("daily_auto_mark_popup")
	_check(popup._reward_pending_date.is_empty(), "过期日的未保存广告意图不延续到另一日")
	kit.ad_rewarded.disconnect(observer)
	await ui.hide_ui("daily_auto_mark_popup")


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
