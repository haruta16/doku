## 隔离工程中的真实奖励页面：按钮、SDK 信号、窗口状态与存档故障一起验证。
extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _hidden_count: int = 0


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
	var award: Node = root.get_node("AwardManager")
	var ui: Node = root.get_node("UIManager")
	var sdk: Node = root.get_node("UniKitManager")
	var files: RefCounted = game._product_store.files
	ui.events.window_hidden.connect(func(name: String, _window: Node) -> void:
		if name == "award":
			_hidden_count += 1
	)
	_check(game.is_storage_ready(), "真实核心存档已经打开")
	var initial: int = game.get_tool_count("hint")
	var uid: int = award.dispatch([{"kind": "hint", "count": 2}], 1, "page_test")
	_check(uid > 0, "登记真实奖励")
	award.show_award(uid)
	var page: Variant = ui.get_ui("award")
	_check(page != null, "UIManager 创建真实奖励场景")
	if page == null:
		quit(1)
		return
	await _wait_gift_ready(page)
	_check(page.is_showing() and page.visible, "奖励页已显示")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page.get_node("AwardPanel/DoubleBtnGroup/CollectBtn").emit_signal("tag_pressed")
	await process_frame
	_check(page.is_showing() and page.visible and _hidden_count == 0, "普通领取写失败不关闭页面")
	_check(game.get_tool_count("hint") == initial and not game.find_in_flight_award(uid).is_empty(), "失败保留余额与待领奖凭证")
	_check(page._on_persisted.is_valid(), "失败后保留可重试回调")
	files.set_fault_injector_for_tests(Callable())
	page.get_node("AwardPanel/DoubleBtnGroup/CollectBtn").emit_signal("tag_pressed")
	await process_frame
	_check(page.is_hidden() and not page.visible and _hidden_count == 1, "普通按钮重试成功后才关闭")
	_check(game.get_tool_count("hint") == initial + 2 and game.find_in_flight_award(uid).is_empty(), "普通领取只入账一次")

	var bonus_uid: int = award.dispatch([{"kind": "hint", "count": 2}], 1, "page_bonus_test", "page_bonus")
	award.show_award(bonus_uid)
	await _wait_gift_ready(page)
	_check(page == ui.get_ui("award") and page.is_showing(), "复用实际页面展示下一笔奖励")
	var before_bonus: int = game.get_tool_count("hint")
	# 原生桥的逐次身份回调，业务注册与真实广告按钮一致。
	sdk.connect_reward_once("award_double", Callable(page, "_on_ad_rewarded"))
	sdk._start_reward_session("award_double", "streak_x2_reward")
	page.connect_managed_once(sdk.ad_closed, Callable(page, "_on_reward_ad_failed"))
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	sdk._on_ad_rewarded_for_show("reward", "award_double")
	await process_frame
	_check(page.is_showing() and page.visible and _hidden_count == 1, "翻倍保存失败不关闭页面")
	_check(page._double_pending and page._ad_settled, "页面保留已收到的翻倍意图")
	_check(game.get_tool_count("hint") == before_bonus and not game.find_in_flight_award(bonus_uid).doubled, "翻倍失败未发布库存或虚假持久标记")
	# 即使此时磁盘恢复，紧随的 close 也不能把已收到的翻倍奖励降成普通领取。
	files.set_fault_injector_for_tests(Callable())
	sdk._on_ad_closed_for_show("reward", "award_double")
	await process_frame
	_check(page.is_showing() and _hidden_count == 1 and page._double_pending, "SDK close 不覆盖待保存的翻倍事实")
	_check(game.get_tool_count("hint") == before_bonus and not game.find_in_flight_award(bonus_uid).is_empty(), "close 不偷偷按普通份额入账")
	page.get_node("AwardPanel/DoubleBtnGroup/CollectBtn").emit_signal("tag_pressed")
	await process_frame
	_check(page.is_hidden() and not page.visible and _hidden_count == 2, "下一次普通按钮重试完成翻倍后关闭")
	_check(game.get_tool_count("hint") == before_bonus + 4 and game.find_in_flight_award(bonus_uid).is_empty(), "重试领取基础与翻倍共两份")
	sdk._on_ad_rewarded_for_show("reward", "award_double")
	sdk._on_ad_closed_for_show("reward", "award_double")
	page.get_node("AwardPanel/DoubleBtnGroup/CollectBtn").emit_signal("tag_pressed")
	await process_frame
	_check(game.get_tool_count("hint") == before_bonus + 4 and _hidden_count == 2, "迟到 SDK 信号和重复按钮不再次入账或关闭")
	var persisted: Dictionary = files.load_result()
	var cfg: ConfigFile = persisted.config
	var saved: Dictionary = cfg.get_value("core", "state")
	_check(saved.inventory.hint == before_bonus + 4 and saved.pending_awards.is_empty(), "实际磁盘最终保存翻倍余额且清除待领奖")
	await ui.destroy_ui("award")
	await process_frame
	await process_frame
	print("STORAGE AWARD PAGE TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("TEST_FAILED: " + label)


func _wait_gift_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while page.is_showing() and page._buttons_locked and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page.is_showing() and not page._buttons_locked, "1.22 礼盒入场完成，真实按钮可操作")
