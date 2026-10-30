## 新增恢复提示独立于原始翻译资源；验证启动加载、地域回退和真实失败界面。
extends SceneTree

const KEYS: Array[String] = [
	"RECOVERY_RESULT_TITLE", "RECOVERY_RESULT_BODY", "RECOVERY_CHECKIN_TITLE",
	"RECOVERY_CHECKIN_BODY", "RECOVERY_CONTENT_ERROR", "RECOVERY_SAVE_ERROR",
]
const DISPLAY_TEXT: Dictionary = {
	"en": ["Result not saved", "Please retry saving this result. Closing returns home; unsaved results may be lost.", "Check-in not saved", "Your win is saved. Retry the check-in, or close to skip this check-in.", "Game content could not be loaded. Please restart the game.", "Action could not be saved. Please try again."],
	"zh_CN": ["结果未保存", "请重试保存本局结果。关闭将返回主页，未保存的结果可能丢失。", "签到未保存", "通关已保存，请重试签到。关闭将跳过本次签到。", "游戏内容读取失败，请重启游戏", "操作未能保存，请重试"],
	"zh_TW": ["結果未儲存", "請重試儲存本局結果。關閉將返回首頁，未儲存的結果可能遺失。", "簽到未儲存", "通關已儲存，請重試簽到。關閉將跳過本次簽到。", "遊戲內容讀取失敗，請重新啟動遊戲", "操作未能儲存，請重試"],
	"fr": ["Résultat non enregistré", "Réessayez d’enregistrer ce résultat. Fermer vous ramènera à l’accueil ; les résultats non enregistrés risquent d’être perdus.", "Connexion quotidienne non enregistrée", "Votre victoire est enregistrée. Réessayez de valider la connexion quotidienne, ou fermez pour l’ignorer cette fois-ci.", "Impossible de charger le contenu du jeu. Veuillez redémarrer le jeu.", "Impossible d’enregistrer cette action. Veuillez réessayer."],
	"ja": ["結果を保存できませんでした", "今回の結果の保存を再試行してください。閉じるとホームに戻り、未保存の結果が失われる場合があります。", "チェックインを保存できませんでした", "クリア結果は保存されています。チェックインを再試行するか、閉じて今回のチェックインをスキップしてください。", "ゲームのコンテンツを読み込めませんでした。ゲームを再起動してください。", "操作を保存できませんでした。もう一度お試しください。"],
}

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
	var previous_locale: String = TranslationServer.get_locale()
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	files = game.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	ab.dc_level.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.dc_start_toast.set_debug_override(0)
	_test_supported_locales()
	_test_embedded_image_translation()
	for locale: String in DISPLAY_TEXT:
		await _test_failed_settlement(locale)
		await _test_failed_checkin(locale)
		await _test_feature_failures(locale)
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	for name: String in ["game", "daily_game", "confirm", "tutorial", "award", "setting", "language", "reward_claim_popup"]:
		await ui.destroy_ui(name)
	TranslationServer.set_locale(previous_locale)
	await process_frame
	await process_frame
	print("GAME RECOVERY LOCALIZATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_supported_locales() -> void:
	var registered: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations")
	var original_count: int = 0
	for path: String in registered:
		if not path.ends_with(".translation"):
			continue
		original_count += 1
		var locale: String = path.get_file().trim_prefix("translations.").trim_suffix(".translation")
		var language: String = locale if locale.begins_with("zh_") else locale.get_slice("_", 0)
		var recovery_path: String = "res://products/meowdoku/assets/localization/recovery/" + language + ".po"
		_check(registered.has(recovery_path), locale + " recovery resource is registered for startup and export")
		if not ResourceLoader.exists(recovery_path):
			_check(false, locale + " recovery resource exists")
			continue
		var recovery: Translation = load(recovery_path)
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			var expected: String = recovery.get_message(key)
			_check(not expected.is_empty() and expected != key and TranslationServer.translate(key) == expected,
				locale + " resolves " + key + " through its own language")
		var original: Translation = load(path)
		_check(TranslationServer.translate("FAIL_TRY_AGAIN") == original.get_message("FAIL_TRY_AGAIN"),
			locale + " preserves the original retry translation")
	_check(original_count == 75, "all 75 recovered translations remain registered")


func _open(locale: String) -> Variant:
	ui.hide_all()
	await create_timer(0.1).timeout
	game.reset_all()
	game.set_sound_on(false)
	game.set_music_on(false)
	TranslationServer.set_locale(locale)
	var page: Variant = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.2).timeout
	page._on_appear_animation_finished()
	_check(page._ensure_business_round().get("ok", false), locale + " enters a durable round")
	return page


func _test_failed_settlement(locale: String) -> void:
	var page: Variant = await _open(locale)
	page._lives = 0
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	await page._on_game_fail()
	var dialog: Variant = ui.get_ui("confirm")
	_check(dialog != null and dialog.is_showing(), locale + " actual failed settlement opens recovery")
	if dialog != null:
		_check_dialog(dialog, locale, 0)
	files.set_fault_injector_for_tests(Callable())
	for index: int in [4, 5]:
		page._report_business_failure({"ok": false, "error": "content_unavailable", "logical_id": "doku/test"} if index == 4 else {"ok": false, "error": "write_failed"})
		var toast: Toast = Toast._current
		_check(is_instance_valid(toast) and toast.get_node("Panel/Label").text == DISPLAY_TEXT[locale][index],
			locale + " displays translated " + KEYS[index])
		# Let Toast finish its first-frame layout before cancelling this test presentation.
		await process_frame
		if is_instance_valid(toast):
			toast.queue_free()
		await process_frame
	ui.hide_all()
	await process_frame


func _test_failed_checkin(locale: String) -> void:
	var page: Variant = await _open(locale)
	var streak: Node = root.get_node("StreakManager")
	root.get_node("ABTestManager").daily_streak.set_debug_override(1)
	game.set_tutorial_done(true)
	var candidate: Dictionary = game.get_core_candidate()
	candidate.features.streak = {"current_streak": 6, "best_streak": 6, "reward_cycle_day": 6, "last_checkin_date": streak._date_offset_str(-1), "streak_start_weekday": 1, "last_group": 1, "pending_switch_page": 0}
	candidate.claims.erase("streak/checkin/" + streak._today_str())
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, locale + " persists check-in fixture")
	for row: int in page._level_config.size:
		for column: int in page._level_config.size:
			page._board_view.get_board_state().set_cell_state(row, column, CellState.CAT if page._puzzle.solution[row][column] else CellState.EMPTY)
	page._board_view.refresh_from_model()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	await page._on_game_win()
	await create_timer(0.3).timeout
	var dialog: Variant = ui.get_ui("confirm")
	_check(not page._is_complete and game.get_current_level() == 1, locale + " keeps failed atomic win/check-in uncommitted")
	_check(dialog != null and dialog.is_showing() and streak.get_data().current_streak == 6, locale + " actual failed atomic check-in opens recovery")
	if dialog != null:
		_check_dialog(dialog, locale, 0)
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.1).timeout


## 通过实际页面触发各保存失败分支；语言切换失败仍使用当前语言，重试资格不改变。
func _test_feature_failures(locale: String) -> void:
	ui.hide_all()
	await create_timer(0.1).timeout
	game.reset_all()
	game.set_sound_on(false)
	game.set_music_on(false)
	TranslationServer.set_locale(locale)
	var settings: Variant = ui.show_ui("setting")
	await _expect_feature_failure(locale, "settings", settings._on_vibration_btn_pressed)
	_check(settings.is_showing(), locale + " keeps failed settings available")
	var language: Variant = ui.show_ui("language")
	language._selected_index = 0
	await _expect_feature_failure(locale, "language", language._on_yes_pressed)
	_check(language.is_showing() and TranslationServer.get_locale() == locale, locale + " keeps current language on failed confirmation")
	ui.hide_all()
	await create_timer(0.1).timeout

	var registered: Dictionary = game.get_economy_service().register_award([{"kind": "hint", "count": 1}], 0, "recovery_test", "recovery_bonus")
	_check(registered.get("ok", false), locale + " prepares durable reward")
	var uid: int = int(registered.get("uid", -1))
	var awards: Node = root.get_node("AwardManager")
	var award: Variant = ui.show_ui("award")
	award._streak_uid = uid
	award._double_pending = true
	await _expect_feature_failure(locale, "reward bonus", award._on_collect_pressed)
	_check(award._double_pending and award.is_showing(), locale + " keeps failed bonus retryable")
	award._double_pending = false
	award._on_persisted = func() -> bool: return awards._persist_award(uid)
	await _expect_feature_failure(locale, "reward claim", award._on_collect_pressed)
	_check(award._on_persisted.is_valid() and award.is_showing(), locale + " keeps failed claim retryable")
	award._on_persisted = Callable()
	ui.hide_ui("award")

	# 原 switch1/2/3 已在 1.22 退休；同一持久奖励通过通用领取页保留失败重试合同。
	var reward: Variant = ui.show_ui("reward_claim_popup", {"items": [AwardItem.make("hint", 1)], "claim": func() -> bool: return awards._persist_award(uid)})
	await _expect_feature_failure(locale, "unified gift claim", reward._on_action_pressed)
	_check(reward._claim.is_valid() and not reward._claiming and reward.is_showing(), locale + " keeps failed gift claim retryable")
	ui.hide_ui("reward_claim_popup")

	var tutorial: Variant = ui.show_ui("tutorial")
	await _expect_feature_failure(locale, "tutorial", tutorial.complete_tutorial)
	_check(not tutorial._completion_committed and not game.is_tutorial_done(), locale + " keeps failed tutorial completion pending")
	ui.hide_ui("tutorial")
	ui.hide_all()
	await create_timer(0.1).timeout


func _expect_feature_failure(locale: String, feature: String, action: Callable) -> void:
	var fault := {"hit": false}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase != "before_replace":
			return false
		fault.hit = true
		return true
	)
	await action.call()
	files.set_fault_injector_for_tests(Callable())
	_check(fault.hit, locale + " " + feature + " reaches the intended save failure")
	var toast: Toast = Toast._current
	_check(is_instance_valid(toast) and toast.get_node("Panel/Label").text == DISPLAY_TEXT[locale][5], locale + " " + feature + " shows the localized save recovery")
	await process_frame
	if is_instance_valid(toast):
		toast.queue_free()
	await process_frame


func _check_dialog(dialog: Variant, locale: String, offset: int) -> void:
	_check(dialog.get_node("Root/Content/DialogRoot/TitleLabel").text == DISPLAY_TEXT[locale][offset], locale + " recovery title uses selected language")
	_check(dialog.get_node("Root/Content/DialogRoot/ContentLabel").text == DISPLAY_TEXT[locale][offset + 1], locale + " recovery explanation uses selected language")
	_check(dialog.get_node("Root/Content/DialogRoot/ActionButton").btn_text == TranslationServer.translate("FAIL_TRY_AGAIN"), locale + " keeps original translated retry action")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _test_embedded_image_translation() -> void:
	var remapper: Script = load("res://products/meowdoku/app/features/language/localized_resource_translation.gd")
	var mixed: String = "prose res://assets/example.png [img=12x14]res://assets/sprites/game/fish_full.png[/img] [img]res://products/meowdoku/assets/sprites/game/tool_cat_item.png[/img] [img]https://example.invalid/x.png[/img]"
	var expected: String = mixed.replace("[img=12x14]res://assets/", "[img=12x14]res://products/meowdoku/assets/")
	_check(remapper._remap_images(mixed) == expected, "translation image mapping preserves prose, external images and already migrated paths")
	_check(remapper._remap_images(remapper._remap_images(mixed)) == expected, "translation image mapping is idempotent")
	var image: RegEx = RegEx.new()
	image.compile("\\[img[^\\]]*\\](res://[^\\[]+)\\[/img\\]")
	var image_count: int = 0
	for path: String in ProjectSettings.get_setting("internationalization/locale/translations"):
		if not path.ends_with(".translation"):
			continue
		var original: Translation = load(path)
		TranslationServer.set_locale(original.locale)
		for key: String in ["RANK_OPEN_DESC", "RANK_OPEN_DESC_FISH", "HOME_COMPANION_HALLOWEEN_DESC"]:
			var source: String = original.get_message(key)
			if not source.contains("[img"):
				continue
			var visible: String = TranslationServer.translate(key)
			_check(visible == remapper._remap_images(source), original.locale + " maps every embedded resource without changing other translation text")
			for match: RegExMatch in image.search_all(visible):
				image_count += 1
				_check(ResourceLoader.exists(match.get_string(1)), original.locale + " embedded image resolves after relocation")
	_check(image_count >= 225, "all 75 locales exercise all three known recovered image message keys")
