## 在 tools/run_validation.py 创建的隔离工程执行，覆盖迁移与真实业务入口。
extends SceneTree

const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const RoundHost = preload("res://scripts/framework/application/round_service.gd")
const DokuModule = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const PASSWORD := "storage-business-test"

var _root_dir: String
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var project := ProjectSettings.globalize_path("res://")
	if not project.contains("/doku-validation-"):
		printerr("TEST_FAILED: 必须通过隔离验证运行器执行")
		quit(2)
		return
	_root_dir = project.path_join("business_storage_fixtures")
	DirAccess.make_dir_recursive_absolute(_root_dir)
	_test_migration()
	_test_economy()
	_test_actual_facade()
	_test_restores_and_switches()
	_test_settlements()
	print("STORAGE BUSINESS TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_migration() -> void:
	var dir := _root_dir.path_join("migration")
	DirAccess.make_dir_recursive_absolute(dir)
	var legacy_player := FileStore.new(PASSWORD, dir, true, dir.path_join("a.cfg"), dir.path_join("b.cfg"), dir.path_join("flag"))
	var legacy_endgame := FileStore.new(PASSWORD, dir, false, dir.path_join("endgame.cfg"))
	var profile := _profile()
	profile.set_value("progress", "current_level", 48)
	profile.set_value("progress", "tool_hint", 7)
	profile.set_value("progress", "in_flight_awards", [{"uid": 12, "items": [{"kind": "hint", "count": 2}], "reason": "old_reward", "display_type": 0}])
	_check(legacy_player.save_config(profile), "准备旧玩家存档")
	var endgame := ConfigFile.new()
	endgame.set_value("snapshot", "data", {"version": 2, "level": 48, "regionMap": [[0]]})
	endgame.set_value("stats", "main_id", "old-round")
	_check(legacy_endgame.save_config(endgame), "准备旧残局存档")
	var streak := ConfigFile.new()
	streak.set_value("streak", "reward_cycle_day", 6)
	streak.set_value("streak", "last_checkin_date", "2026-10-25")
	_check(streak.save(dir.path_join("streak.cfg")) == OK, "准备旧签到存档")
	var legacy_hash := FileAccess.get_sha256(dir.path_join("a.cfg"))
	var product := ProductStore.new(dir, PASSWORD)
	_check(product.open(_profile(), legacy_player, legacy_endgame, dir.path_join("streak.cfg")).ok, "三份旧档一次性导入新核心")
	var state: Dictionary = product.core.snapshot()
	_check(state.profile.current_level == 48 and state.inventory.hint == 7, "迁移保持进度库存")
	_check(state.endgame.snapshot.level == 48 and state.endgame.stats.main_id == "old-round", "迁移保持残局及对局身份")
	_check(state.features.streak.reward_cycle_day == 6, "迁移保持签到资格")
	_check(state.award_sequence == 12 and state.pending_awards.size() == 1, "旧奖励迁移并保留发号水位")
	var captured: Dictionary = ProductStore.capture_profile(ProductStore.profile_config(state))
	_check(captured.size() == 2 and captured.profile == state.profile and captured.inventory == state.inventory,
		"当前字段映射保持进度库存，不重复执行奖励、残局与签到迁移")
	_check(not captured.profile.has("endgame_snapshot") and not captured.profile.has("in_flight_awards"),
		"旧接口的跨分区投影不会混入当前 profile")
	_check(FileAccess.get_sha256(dir.path_join("a.cfg")) == legacy_hash, "迁移不写旧玩家档")
	var economy := Economy.new(product.core)
	_check(economy.claim_award(12).ok, "迁移奖励可补发")
	_check(product.core.snapshot().inventory.hint == 9, "迁移补发全额到账")
	var reopened := ProductStore.new(dir, PASSWORD)
	_check(reopened.open(_profile(), legacy_player, legacy_endgame, dir.path_join("streak.cfg")).ok, "再次启动读取新档")
	_check(reopened.core.snapshot().inventory.hint == 9 and reopened.core.snapshot().pending_awards.is_empty(), "不会重新导入旧奖励")
	var invalid_dir := _root_dir.path_join("invalid_legacy")
	DirAccess.make_dir_recursive_absolute(invalid_dir)
	var invalid_player := FileStore.new(PASSWORD, invalid_dir, false, invalid_dir.path_join("legacy.cfg"))
	var invalid_cfg := _profile()
	invalid_cfg.set_value("progress", "current_level", "bad_type")
	_check(invalid_player.save_config(invalid_cfg), "准备类型损坏的旧档")
	var invalid_end := FileStore.new(PASSWORD, invalid_dir, false, invalid_dir.path_join("end.cfg"))
	var invalid := ProductStore.new(invalid_dir, PASSWORD)
	var invalid_result: Dictionary = invalid.open(_profile(), invalid_player, invalid_end, invalid_dir.path_join("none.cfg"))
	_check(invalid_result.status == "invalid_legacy", "类型损坏旧档拒绝迁移")
	_check(invalid_result.error == "invalid_legacy" and not invalid_result.detail.is_empty(), "迁移拒绝也使用统一机器码与说明")
	_check(invalid.files.load_result().status == "missing", "拒绝迁移不生成默认核心档")


func _test_economy() -> void:
	var product := _new_product("economy")
	var economy := Economy.new(product.core)
	var first: Dictionary = economy.register_award([{"kind": "hint", "count": 2}, {"kind": "locate", "count": 3}], 1, "test", "bonus", "test/checkin/1")
	_check(first.ok and first.uid == 1, "创建稳定奖励流水")
	var duplicate: Dictionary = economy.register_award([{"kind": "hint", "count": 2}], 1, "test", "", "test/checkin/1")
	_check(duplicate.ok and duplicate.duplicate and duplicate.uid == first.uid, "同业务身份登记只返回原流水")
	_check(economy.double_award(first.uid).ok, "翻倍资格单独持久化")
	var revision: int = product.core.revision()
	_check(economy.double_award(first.uid).ok and product.core.revision() == revision, "重复翻倍不再次提交")
	product.files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed_claim: Dictionary = economy.claim_award(first.uid)
	_check(not failed_claim.ok, "失败时不报告发奖成功")
	_check(failed_claim.error == "write_failed" and not failed_claim.detail.is_empty(), "库存用例保留底层写失败机器码与说明")
	var failed: Dictionary = product.core.snapshot()
	_check(failed.inventory.hint == 5 and failed.inventory.locate == 5 and failed.pending_awards.size() == 1, "失败保留完整待领取记录及原库存")
	product.files.set_fault_injector_for_tests(Callable())
	_check(economy.claim_award(first.uid).ok, "失败后可重试整笔入账")
	var awarded: Dictionary = product.core.snapshot()
	_check(awarded.inventory.hint == 9 and awarded.inventory.locate == 11 and awarded.pending_awards.is_empty(), "基础与翻倍全部道具一次到账")
	var repeat: Dictionary = economy.claim_award(first.uid)
	_check(repeat.ok and repeat.status == "already_applied" and product.core.snapshot().inventory.hint == 9, "重复领取不会加钱")
	var core_reopen := ProductStore.new(_root_dir.path_join("economy"), PASSWORD)
	_check(core_reopen.core.open().ok, "重启后可读取已结算奖励")
	var economy_reopen := Economy.new(core_reopen.core)
	_check(economy_reopen.claim_award(first.uid).status == "already_applied", "跨重启重复领取仍拒重")
	var later: Dictionary = economy_reopen.register_award([{"kind": "hint", "count": 1}], 0, "later")
	_check(later.ok and later.uid == 2, "跨重启发号不归零")
	var unknown: Dictionary = economy_reopen.register_award([{"kind": "unknown", "count": 1}], 0, "test")
	_check(not unknown.ok, "拒绝未注册道具")
	_check(unknown.error == "invalid_award" and unknown.status == "invalid_award" and not unknown.detail.is_empty(), "库存资格失败与存储失败遵循同一返回约定")


func _test_actual_facade() -> void:
	var game := root.get_node("GameState")
	var streak := root.get_node("StreakManager")
	_check(game.is_storage_ready(), "实际 GameState 已打开统一核心存档")
	_check(game.set_tool_count("hint", 4), "实际门面库存 setter 确认成功")
	_check(game.get_tool_count("hint") == 4 and game.get_core_store().snapshot().inventory.hint == 4, "门面与核心库存一致")
	var files: RefCounted = game._product_store.files
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.set_tool_count("hint", 1), "实际门面库存 setter 暴露保存失败")
	_check(game.get_tool_count("hint") == 4, "保存失败不发布余额")
	var next := {"current_streak": 7, "best_streak": 7, "last_checkin_date": "2026-10-26", "reward_cycle_day": 7, "streak_start_weekday": 1}
	var items := [{"kind": "hint", "count": 2}]
	var rejected: Dictionary = game.commit_streak_checkin(next, items, "test_streak", "test_bonus")
	_check(not rejected.ok and game.get_streak_data().get("last_checkin_date", "") != "2026-10-26", "实际签到写失败不消耗资格")
	files.set_fault_injector_for_tests(Callable())
	var accepted: Dictionary = game.commit_streak_checkin(next, items, "test_streak", "test_bonus")
	_check(accepted.ok and accepted.uid > 0, "实际签到与奖励登记同次提交")
	_check(game.get_streak_data().last_checkin_date == "2026-10-26" and game.find_in_flight_award(accepted.uid).items == items, "签到资格与奖励同时可见")
	var duplicate: Dictionary = game.commit_streak_checkin(next, items, "test_streak", "test_bonus")
	_check(duplicate.ok and duplicate.duplicate and duplicate.uid == accepted.uid, "实际签到重试不生成第二笔")
	_check(streak._data.last_checkin_date == "2026-10-26", "StreakManager 从同一核心状态更新")
	var award := root.get_node("AwardManager")
	_check(award._persist_award(accepted.uid), "实际 AwardManager 使用原子入账")
	_check(game.get_tool_count("hint") == 6, "实际发奖成功后页面库存更新")
	_check(award._persist_award(accepted.uid) and game.get_tool_count("hint") == 6, "实际 AwardManager 重试不重复入账")
	var render_award: Dictionary = game.get_economy_service().register_award([{"kind": "hint", "count": 1}], 1, "render_test")
	award.attach_award(render_award.uid)
	var render: RefCounted = award._renders[render_award.uid]
	var ended := [0]
	render.award_end.connect(func(_uid: int) -> void: ended[0] += 1)
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not render._on_page_closed() and ended[0] == 0 and not game.find_in_flight_award(render_award.uid).is_empty(), "奖励写失败不发送演出完成且保留可重试凭证")
	files.set_fault_injector_for_tests(Callable())
	_check(render._on_page_closed() and ended[0] == 1 and game.get_tool_count("hint") == 7, "重试入账成功才发送奖励完成")
	_check(not FileAccess.file_exists(game.SAVE_PATH_A) and not FileAccess.file_exists(game.SAVE_PATH_ENDGAME), "新业务不向旧玩家或残局文件双写")


func _new_product(case_name: String) -> RefCounted:
	var dir := _root_dir.path_join(case_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var player := FileStore.new(PASSWORD, dir, false, dir.path_join("legacy.cfg"))
	var endgame := FileStore.new(PASSWORD, dir, false, dir.path_join("endgame.cfg"))
	var product := ProductStore.new(dir, PASSWORD)
	_check(product.open(_profile(), player, endgame, dir.path_join("streak.cfg")).ok, "创建独立业务测试档 " + case_name)
	return product


func _test_restores_and_switches() -> void:
	var game := root.get_node("GameState")
	var files: RefCounted = game._product_store.files
	var now := int(Time.get_unix_time_from_system())
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile["restored_today_count"] = 0
	candidate.profile["reward_history_ts"] = [now, now, now]
	candidate.profile["today_date"] = Time.get_date_string_from_system()
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "准备广告补偿资格")
	var entry := {"show_id": "restore-once", "source": "props_normal_hint", "ts": now}
	game.add_pending_reward(entry)
	game.add_pending_reward(entry)
	_check(game.get_pending_rewards().size() == 1, "相同广告请求不会重复进入待补偿队列")
	var requests := [{"entry": entry}]
	var before: int = game.get_tool_count("hint")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.claim_restored_rewards(requests).ok, "补偿提交失败可见")
	_check(game.get_tool_count("hint") == before and game.get_pending_rewards().size() == 1 and game.get_restored_today_count() == 0, "补偿失败同时保留库存/资格/额度")
	files.set_fault_injector_for_tests(Callable())
	_check(game.claim_restored_rewards(requests).ok, "补偿一次提交成功")
	_check(game.get_tool_count("hint") == before + 1 and game.get_pending_rewards().is_empty() and game.get_restored_today_count() == 1, "补偿成功同时增加库存并消耗资格与额度")
	_check(game.claim_restored_rewards(requests).status == "already_applied" and game.get_tool_count("hint") == before + 1, "迟到补偿回调不再次发奖")
	var old_group: Dictionary = game.get_streak_data()
	old_group["last_group"] = 1
	_check(game.commit_streak_data(old_group), "准备切组资格")
	var next_group := old_group.duplicate(true)
	next_group["last_group"] = -1
	next_group["pending_switch_page"] = 1
	var switch_items := [{"kind": "hint", "count": 2}]
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.commit_streak_transition(next_group, switch_items, "test_switch").ok, "切组礼包提交失败可见")
	_check(game.get_streak_data().last_group == 1, "切组失败不提前消耗原分组资格")
	files.set_fault_injector_for_tests(Callable())
	var switched: Dictionary = game.commit_streak_transition(next_group, switch_items, "test_switch")
	_check(switched.ok and game.find_in_flight_award(switched.uid).items == switch_items, "切组状态与礼包资格同提交")
	var streak := root.get_node("StreakManager")
	streak.consume_pending_switch()
	_check(int(game.get_streak_data().switch_award_uid) == int(switched.uid), "消费弹窗标记不丢失礼包身份")
	before = game.get_tool_count("hint")
	streak.grant_switch_gift()
	streak.grant_switch_gift()
	_check(game.get_tool_count("hint") == before + 2, "切组弹窗重复关闭只发一次礼包")
	var sequence: int = game.get_core_store().snapshot().award_sequence
	var before_reset: Dictionary = game.get_core_store().snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.reset_all(), "重置写失败可见")
	_check(game.get_core_store().snapshot() == before_reset and game.get_tool_count("hint") == before + 2, "重置失败保留持久状态与公开库存")
	files.set_fault_injector_for_tests(Callable())
	_check(game.reset_all(), "重置成功后才发布完成")
	_check(game.get_tool_count("hint") == 5 and game.get_in_flight_awards().is_empty(), "全量重置统一清库存/待领奖状态")
	_check(game.get_core_store().snapshot().award_sequence == sequence, "重置不重复使用旧奖励ID")


func _test_settlements() -> void:
	var game := root.get_node("GameState")
	var files: RefCounted = game._product_store.files
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile["current_level"] = 51
	candidate.profile["current_strategy"] = 2
	candidate.profile["consecutive_clean_wins"] = 0
	candidate.profile["consecutive_fails"] = 0
	candidate.endgame["snapshot"] = {"version": 2, "level": 51}
	for field in candidate.round_runtime:
		candidate.round_runtime[field] = false
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "准备主线结算状态")
	var round_id := _start_test_round(game, "main", 51)
	var first_id := round_id + "/attempt#0"
	var played: int = game.get_today_played_count()
	_check(game.settle_main_round(first_id, 51, "win").get("status") == "round_not_won", "未完成棋盘不能只靠页面声明胜利")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.settle_main_round(first_id, 51, "win", {"board": [[1]]}).ok, "主线结算写失败可见")
	_check(game.get_current_level() == 51 and not game.get_endgame_snapshot().is_empty() and game.get_today_played_count() == played, "结算失败不提前改进度/残局/计局")
	files.set_fault_injector_for_tests(Callable())
	var won: Dictionary = game.settle_main_round(first_id, 51, "win", {"board": [[1]]})
	_check(won.ok and not won.duplicate, "主线首次结算成功")
	_check(game.get_current_level() == 52 and game.get_core_store().snapshot().profile.current_strategy == 3, "保留51关干净通关一次升档规则")
	_check(game.get_endgame_snapshot().is_empty() and game.get_today_played_count() == played + 1, "主线进度/残局清理/计局同提交")
	_check(game.settle_main_round(first_id, 51, "win").duplicate and game.get_today_played_count() == played + 1, "重复胜利不重复推进DDA或计局")
	_check(game.settle_main_round(first_id, 51, "fail").status == "settlement_conflict", "同尝试冲突终局被拒绝")
	var next_round_id := _start_test_round(game, "main", 52)
	_check(game.settle_main_round(first_id, 51, "win").status == "stale_round", "新局开始后旧关迟到回调被身份检查拒绝")
	game.mark_current_level_dirty()
	game.mark_dda_tool_or_revive_used()
	var persisted: Dictionary = game._product_store.files.load_result()
	var persisted_cfg: ConfigFile = persisted.config
	var persisted_state: Dictionary = persisted_cfg.get_value("core", "state")
	_check(persisted_state.round_runtime.current_level_dirty and persisted_state.round_runtime.dda_tool_or_revive_used, "DDA道具标记已持久化")
	var retry_params := {"retry_level": 52, "prebuilt_regions": [[0]], "prebuilt_solution": [0]}
	var failed: Dictionary = game.settle_main_round(next_round_id + "/attempt#0", 52, "fail", {"board": [[0]], "lives": 0, "history": []}, retry_params)
	_check(failed.ok and game.get_core_store().snapshot().profile.consecutive_fails == 1, "下一尝试失败按原规则累计失败")
	_check(game.get_retry_puzzle(52) == retry_params and game.get_core_store().snapshot().round_services["doku/main"].snapshot.lives == 0, "失败同时保存重试题面与host死亡状态")
	_check(game.settle_main_round(next_round_id + "/attempt#0", 52, "fail").duplicate and game.get_core_store().snapshot().profile.consecutive_fails == 1, "重复失败不重复累计DDA")
	_check(game.settle_main_round(next_round_id + "/attempt#2", 52, "win").status == "attempt_gap", "尝试序号跳跃被拒绝")
	_check(game.settle_main_round(next_round_id + "/attempt#1", 52, "win").status == "attempt_not_active", "未复活不能假造下一尝试")
	var revive_host := RoundHost.new(game.get_core_store())
	revive_host.register_module("doku", DokuModule.new())
	var record: Dictionary = game.get_core_store().snapshot().round_services["doku/main"]
	var revived: Dictionary = revive_host.action("doku", "main", next_round_id, int(record.last_sequence) + 1, "revive", {}, {}, {"revive_lives": 3})
	_check(revived.ok and revived.snapshot.attempt_sequence == 1, "通过真实模块复活才推进尝试序号")
	_check(game.settle_main_round(next_round_id + "/attempt#1", 52, "win", {"board": [[1]]}).ok, "复活后的下一尝试可以正常结算胜利")
	_check(game.get_core_store().snapshot().product_settlements.size() == 1, "主线结算只保留当前局最后尝试的水位")
	var daily_date := "2026-10-26"
	game.set_daily_started_date(daily_date)
	game.set_endgame_snapshot({"version": 2, "level": 53})
	var daily_round := _start_test_round(game, "daily", 0)
	var daily: Dictionary = game.settle_daily_round(daily_round + "/attempt#0", daily_date, "win", 69, 93.5, {"board": [[1]]})
	_check(daily.ok and game.get_daily_completed_date() == daily_date and game.get_daily_elapsed_sec() == 69, "每日通关成绩一次提交")
	_check(game.get_current_level() == 53 and not game.get_endgame_snapshot().is_empty(), "每日结算保留主线进度与停放残局")
	_check(game.settle_daily_round(daily_round + "/attempt#0", daily_date, "win", 69, 93.5).duplicate, "每日通关可幂等重试")
	var preview := _start_test_round(game, "preview", 0)
	_check(game.settle_preview_round(preview + "/attempt#0", "win", {"board": [[1]]}).ok, "题库预览使用独立结算命名空间")
	_check(game.get_current_level() == 53 and not game.get_endgame_snapshot().is_empty() and game.get_daily_completed_date() == daily_date, "题库预览不覆盖主线残局或每日成绩")
	var before_reset_sequence: int = game.get_core_store().snapshot().round_services["doku/main"].start_sequence
	game.reset_all()
	_check(game.get_core_store().snapshot().round_services["doku/main"].start_sequence == before_reset_sequence, "重置保留局号高水位")
	_check(game.get_core_store().snapshot().round_services["doku/main"].status == "reset", "重置后旧局不可继续恢复")
	_check(game.settle_main_round(next_round_id + "/attempt#1", 52, "win").status == "stale_round", "重置后旧结算回调被拒绝")
	var after_reset := _start_test_round(game, "main", 1)
	_check(after_reset != next_round_id and game.get_core_store().snapshot().round_services["doku/main"].start_sequence == before_reset_sequence + 1, "重置后的新局身份不重用")
	game.set_endgame_snapshot({"version": 2, "level": 1, "size": 1, "solution": [0], "placed_cats": [[0, 0]]})
	var count_before: int = game.get_today_played_count()
	_check(game.settle_legacy_completed_main(1).ok and game.get_current_level() == 2, "旧完整残局通过专用兼容入口收尾")
	_check(game.get_today_played_count() == count_before, "旧完整残局不猜测和重复累计已经写过的计局")
	_check(game.settle_legacy_completed_main(1).duplicate, "旧完整残局专用入口也可以幂等重试")


func _start_test_round(game: Node, mode: String, level: int) -> String:
	var host := RoundHost.new(game.get_core_store())
	host.register_module("doku", DokuModule.new())
	var records: Dictionary = game.get_core_store().snapshot().round_services
	var sequence := int(records.get("doku/" + mode, {}).get("start_sequence", 0)) + 1
	var started: Dictionary = host.start("doku", mode, sequence, {"board": [[0]], "regions": [[0]], "solution": [[true]], "content": {"level": level}})
	_check(started.ok, "通过真实 RoundService 创建测试局 " + mode)
	return str(started.get("round_id", ""))


func _profile() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", 1)
	cfg.set_value("progress", "tool_hint", 5)
	cfg.set_value("progress", "tool_locate", 5)
	cfg.set_value("progress", "tool_undo", 3)
	return cfg


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("TEST_FAILED: " + label)
