extends Node

signal init_done
signal params_updated(update_type: String, user_info: Dictionary)
signal remote_ready
signal locsrv_fetched(success: bool, error: String)

var _is_init_done: bool = false

var _is_remote_ready: bool = false

var _app_start_dyed: bool = false
var _is_locsrv_fetched: bool = false

var region_color: RegionColorConfig
var size_cycle: SizeCycleConfig
var rule_highlight: RuleHighlightConfig
var goal_emphasis: GoalEmphasisConfig
var function_clear: FunctionClearConfig
var normal_start_toast: NormalStartToastConfig
var thumb_up: ThumbUpConfig
var rule_normal_rank: RuleNormalRankConfig
var tutorial_diagonal: TutorialDiagonalConfig
var normal_endgame_save: NormalEndgameSaveConfig
var rate_us_pop: RateUsPopConfig
var warn_life: WarnLifeConfig
var life_icon: LifeIconConfig
var fail_text: FailTextConfig
var play_anim: PlayAnimConfig
var pass_text: PassTextConfig
var draft_mode: DraftModeConfig
var inter_unlock_level: InterUnlockLevelConfig
var inter_unlock_session: InterUnlockSessionConfig
var inter_unlock_memory: InterUnlockMemoryConfig
var banner_unlock_level: BannerUnlockLevelConfig
var banner_unlock_session: BannerUnlockSessionConfig
var living_days: LivingDaysConfig
var inter_cd_lc: InterCdLcConfig
var inter_extra_protect_lc: InterExtraProtectLcConfig
var inter_prob: InterProbConfig
var banner_extra_protect_lc: BannerExtraProtectLcConfig
var banner_unlock_diff_lc: BannerUnlockDiffLcConfig
var reward_unlock_level: RewardUnlockLevelConfig
var guide_feedback: GuideFeedbackConfig
var idle_guide: IdleGuideConfig
var auto_complete: AutoCompleteConfig
var third_rule_text: ThirdRuleTextConfig
var progress_emphasis: ProgressEmphasisConfig
var daily_first_level_difficulty: DailyFirstLevelDifficultyConfig
var revive_free_logic: ReviveFreeLogicConfig
var undo_btn: UndoBtnConfig
var no_dc: NoDcConfig

var combo_encourage: ComboEncourageConfig
var att_dlg_logic: AttDlgLogicConfig
var dc_tag_ui: DcTagUiConfig
var game_page_rules_ui: GamePageRulesUiConfig
var rate_us_pop_ui: RateUsPopUiConfig
var common_rewardad_logic: CommonRewardadLogicConfig
var daily_streak: DailyStreakConfig
var error_feedback: ErrorFeedbackConfig
var game_life_rule: GameLifeRuleConfig
var rule_text: RuleTextConfig
var normal_level_10: NormalLevel10Config
var ad_compliance_ui: AdComplianceUiConfig
var error_catface: ErrorCatfaceConfig
var swipe_protect: SwipeProtectConfig
var dda_rank: DdaRankConfig
var revive_life: ReviveLifeConfig
var eliminate_effect: EliminateEffectConfig
var game_auto_mark: GameAutoMarkConfig
var win_toast: WinToastConfig
var settings_language: SettingsLanguageConfig
var tap_feedback: TapFeedbackConfig
var bgm_test: BgmTestConfig
var single_region_num: SingleRegionNumConfig
var push_local_text: PushLocalTextConfig
var icon_crash: IconCrashConfig
var wrong_cat_effect: WrongCatEffectConfig
var combo_voice: ComboVoiceConfig
var hint_ue: HintUeConfig
var prop_highlight: PropHighlightConfig
var auto_screen_off: AutoScreenOffConfig
var dc_level: DcLevelConfig
var splash_slogan: SplashSloganConfig

var _configs_by_key: Dictionary = {}

const TIMING_APP_START: String = "app_start"
const TIMING_GAME_START: String = "game_start"

const TIMING_GAME_START_NORMAL: String = "game_start_normal"

const TIMING_GAME_START_NORMAL_11: String = "game_start_normal_11"

const TIMING_GAME_START_NORMAL_21: String = "game_start_normal_21"

const TIMING_GAME_END: String = "game_end"

const TIMING_GAME_START_DC: String = "game_start_dc"

const TIMING_HINT_USE: String = "hint_use"

const TIMING_NO_ACTION_270: String = "no_action_270"


func _ready() -> void:
	_register_configs()
	UniKitManager.abtest_ready.connect(_on_abtest_ready)
	UniKitManager.abtest_params_updated.connect(_on_abtest_params_updated)
	UniKitManager.abtest_remote_config_ready.connect(_on_abtest_remote_config_ready)
	UniKitManager.abtest_locsrv_fetched.connect(_on_abtest_locsrv_fetched)


func _register_configs() -> void:
	region_color = RegionColorConfig.new()
	size_cycle = SizeCycleConfig.new()
	rule_highlight = RuleHighlightConfig.new()
	goal_emphasis = GoalEmphasisConfig.new()
	function_clear = FunctionClearConfig.new()
	normal_start_toast = NormalStartToastConfig.new()
	thumb_up = ThumbUpConfig.new()
	rule_normal_rank = RuleNormalRankConfig.new()
	tutorial_diagonal = TutorialDiagonalConfig.new()
	normal_endgame_save = NormalEndgameSaveConfig.new()
	rate_us_pop = RateUsPopConfig.new()
	warn_life = WarnLifeConfig.new()
	life_icon = LifeIconConfig.new()
	fail_text = FailTextConfig.new()
	play_anim = PlayAnimConfig.new()
	pass_text = PassTextConfig.new()
	draft_mode = DraftModeConfig.new()
	inter_unlock_level = InterUnlockLevelConfig.new()
	inter_unlock_session = InterUnlockSessionConfig.new()
	inter_unlock_memory = InterUnlockMemoryConfig.new()
	banner_unlock_level = BannerUnlockLevelConfig.new()
	banner_unlock_session = BannerUnlockSessionConfig.new()
	living_days = LivingDaysConfig.new()
	inter_cd_lc = InterCdLcConfig.new()
	inter_extra_protect_lc = InterExtraProtectLcConfig.new()
	inter_prob = InterProbConfig.new()
	banner_extra_protect_lc = BannerExtraProtectLcConfig.new()
	banner_unlock_diff_lc = BannerUnlockDiffLcConfig.new()
	reward_unlock_level = RewardUnlockLevelConfig.new()
	guide_feedback = GuideFeedbackConfig.new()
	idle_guide = IdleGuideConfig.new()
	auto_complete = AutoCompleteConfig.new()
	third_rule_text = ThirdRuleTextConfig.new()
	progress_emphasis = ProgressEmphasisConfig.new()
	daily_first_level_difficulty = DailyFirstLevelDifficultyConfig.new()
	revive_free_logic = ReviveFreeLogicConfig.new()
	undo_btn = UndoBtnConfig.new()
	no_dc = NoDcConfig.new()
	combo_encourage = ComboEncourageConfig.new()
	att_dlg_logic = AttDlgLogicConfig.new()
	dc_tag_ui = DcTagUiConfig.new()
	game_page_rules_ui = GamePageRulesUiConfig.new()
	rate_us_pop_ui = RateUsPopUiConfig.new()
	common_rewardad_logic = CommonRewardadLogicConfig.new()
	daily_streak = DailyStreakConfig.new()
	error_feedback = ErrorFeedbackConfig.new()
	game_life_rule = GameLifeRuleConfig.new()
	rule_text = RuleTextConfig.new()
	normal_level_10 = NormalLevel10Config.new()
	ad_compliance_ui = AdComplianceUiConfig.new()
	error_catface = ErrorCatfaceConfig.new()
	swipe_protect = SwipeProtectConfig.new()
	dda_rank = DdaRankConfig.new()
	revive_life = ReviveLifeConfig.new()
	eliminate_effect = EliminateEffectConfig.new()
	game_auto_mark = GameAutoMarkConfig.new()
	settings_language = SettingsLanguageConfig.new()
	win_toast = WinToastConfig.new()
	tap_feedback = TapFeedbackConfig.new()
	bgm_test = BgmTestConfig.new()
	single_region_num = SingleRegionNumConfig.new()
	push_local_text = PushLocalTextConfig.new()
	icon_crash = IconCrashConfig.new()
	wrong_cat_effect = WrongCatEffectConfig.new()
	combo_voice = ComboVoiceConfig.new()
	hint_ue = HintUeConfig.new()
	prop_highlight = PropHighlightConfig.new()
	auto_screen_off = AutoScreenOffConfig.new()
	dc_level = DcLevelConfig.new()
	splash_slogan = SplashSloganConfig.new()

	for cfg: AbConfigBase in [
		region_color,
		size_cycle,
		rule_highlight,
		goal_emphasis,
		function_clear,
		normal_start_toast,
		thumb_up,
		rule_normal_rank,
		tutorial_diagonal,
		normal_endgame_save,
		rate_us_pop,
		warn_life,
		life_icon,
		fail_text,
		play_anim,
		pass_text,
		draft_mode,
		inter_unlock_level,
		inter_unlock_session,
		inter_unlock_memory,
		banner_unlock_level,
		banner_unlock_session,
		living_days,
		inter_cd_lc,
		inter_extra_protect_lc,
		inter_prob,
		banner_extra_protect_lc,
		banner_unlock_diff_lc,
		reward_unlock_level,
		guide_feedback,
		idle_guide,
		auto_complete,
		third_rule_text,
		progress_emphasis,
		daily_first_level_difficulty,
		revive_free_logic,
		undo_btn,
		no_dc,
		combo_encourage,
		att_dlg_logic,
		dc_tag_ui,
		game_page_rules_ui,
		rate_us_pop_ui,
		common_rewardad_logic,
		daily_streak,
		error_feedback,
		game_life_rule,
		rule_text,
		normal_level_10,
		ad_compliance_ui,
		error_catface,
		swipe_protect,
		dda_rank,
		revive_life,
		eliminate_effect,
		game_auto_mark,
		settings_language,
		win_toast,
		tap_feedback,
		bgm_test,
		single_region_num,
		push_local_text,
		icon_crash,
		wrong_cat_effect,
		combo_voice,
		hint_ue,
		prop_highlight,
		auto_screen_off,
		dc_level,
		splash_slogan,
	]:
		cfg.init_default()
		_configs_by_key[cfg.key] = cfg


func _on_abtest_ready(_user_info: Dictionary) -> void:
	if _is_init_done:
		return
	_is_init_done = true
	print("[ABTestManager] init ready")
	init_done.emit()
	_finalize_app_start_dye()


func _on_abtest_remote_config_ready() -> void:
	print("[ABTestManager] remote config ready")
	_finalize_app_start_dye()


func _finalize_app_start_dye() -> void:
	if _app_start_dyed:
		return
	_app_start_dyed = true
	_is_remote_ready = true
	dye_at_app_start()
	remote_ready.emit()


func _on_abtest_params_updated(update_type: String, user_info: Dictionary) -> void:
	params_updated.emit(update_type, user_info)


func _on_abtest_locsrv_fetched(success: bool, error: String) -> void:
	_is_locsrv_fetched = success
	print("[ABTestManager] locsrv fetched: success=%s error=%s" % [success, error])
	locsrv_fetched.emit(success, error)


func await_ready(timeout_sec: float = 2.0) -> bool:
	if _is_init_done:
		return true
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	while not _is_init_done and timer.time_left > 0.0:
		await get_tree().process_frame
	return _is_init_done


func await_remote_ready(timeout_sec: float = 2.0) -> bool:
	if _is_remote_ready:
		return true
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	while not _is_remote_ready and timer.time_left > 0.0:
		await get_tree().process_frame
	if not _is_remote_ready:
		_finalize_app_start_dye()
	return _is_remote_ready


func get_ab_string(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_string(key, default_value)


func get_ab_int(key: String, default_value: int = 0) -> int:
	return UniKitManager.get_ab_int(key, default_value)


func get_ab_float(key: String, default_value: float = 0.0) -> float:
	return UniKitManager.get_ab_float(key, default_value)


func dye_ab(key: String) -> void:
	UniKitManager.dye_ab(key)


func get_all_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_ab_experiments()


func get_all_publish_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_publish_ab_experiments()


func get_ab_dyeing_tag() -> String:
	return UniKitManager.get_ab_dyeing_tag()


func get_ab_all_tag() -> String:
	return UniKitManager.get_ab_all_tag()


func get_ab_group_id() -> String:
	return UniKitManager.get_ab_group_id()


func get_ab_country() -> String:
	return UniKitManager.get_ab_country()


func get_ab_locsrv(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_locsrv_param(key, default_value)


func get_all_ab_locsrv() -> Dictionary:
	return UniKitManager.get_all_ab_locsrv_params()


func fetch_ab_locsrv() -> void:
	UniKitManager.fetch_remote_ab_result()


func dye_ab_locsrv(key: String) -> void:
	UniKitManager.dye_ab_locsrv(key)


func dye_ab_locsrv_tag(tag: String) -> void:
	UniKitManager.dye_ab_locsrv_tag(tag)


func set_ab_locsrv_all_tag(tags: Array[String]) -> void:
	UniKitManager.set_ab_locsrv_all_tag(tags)


func get_ab_user_info() -> Dictionary:
	return UniKitManager.get_ab_user_info()


func set_ab_group_id(group_id: String) -> void:
	UniKitManager.set_ab_group_id(group_id)


func set_ab_country(country: String) -> void:
	UniKitManager.set_ab_country(country)


func is_ab_init_done() -> bool:
	return _is_init_done


func is_ab_locsrv_fetched() -> bool:
	return _is_locsrv_fetched


func get_all_configs() -> Array[AbConfigBase]:
	var out: Array[AbConfigBase] = []
	for cfg: AbConfigBase in _configs_by_key.values():
		out.append(cfg)
	return out


func find_config(key: String) -> AbConfigBase:
	return _configs_by_key.get(key, null) as AbConfigBase


func dye_at_app_start() -> void:
	_dye_at_timing(TIMING_APP_START)


func dye_at_game_start() -> void:
	_dye_at_timing(TIMING_GAME_START)


func dye_at_game_start_normal() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL)


func dye_at_game_start_normal_11() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_11)


func dye_at_game_start_normal_21() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_21)


func dye_at_game_fail_end() -> void:
	_dye_at_timing(TIMING_GAME_END)


func dye_at_game_start_dc() -> void:
	_dye_at_timing(TIMING_GAME_START_DC)


func dye_at_hint_use() -> void:
	_dye_at_timing(TIMING_HINT_USE)


func dye_at_no_action_270() -> void:
	_dye_at_timing(TIMING_NO_ACTION_270)


func _dye_at_timing(t: String) -> void:
	for cfg: AbConfigBase in _configs_by_key.values():
		if cfg.timing == t:
			cfg.reload_value()
