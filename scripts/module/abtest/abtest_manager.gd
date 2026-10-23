## 实验入口：注册配置对象，按时机加载取值，并协调 SDK 就绪、超时兜底和实验染色。
extends Node

signal init_done # A/B 初始化完成，此时读取实验值才是安全的
signal params_updated(update_type: String, user_info: Dictionary) # SDK 推送参数更新，原样转发给业务层
signal remote_ready # 远端配置就绪且 app_start 档位已染色
signal locsrv_fetched(success: bool)

signal values_reloaded(timing: String, keys: Array[String])

# ---- 初始化与远端就绪状态 ----
var _is_init_done: bool = false # 是否已收到 abtest_ready

var _is_remote_ready: bool = false # 远端配置是否就绪（await 超时也会强行置位）

var _app_start_dyed: bool = false # app_start 档位是否已染色，保证只染一次

var _all_values_loaded: bool = false

var _is_init_success_done: bool = false

var _home_page_10s_dyed: bool = false
var _is_locsrv_fetched: bool = false # 地区服务参数是否拉取成功

# ---- 实验配置实例（_register_configs 里逐个 new 出来） ----
var region_color: RegionColorConfig # 区域配色方案
var normal_start_toast: NormalStartToastConfig # 普通关开局提示条
var normal_start_toast_text: NormalStartToastTextConfig
var thumb_up: ThumbUpConfig # 点赞/鼓掌反馈组合
var normal_endgame_save: NormalEndgameSaveConfig # 普通关残局存档
var rate_us_pop: RateUsPopConfig # 评分弹窗触发时机
var life_icon: LifeIconConfig # 生命条图标
var fail_text: FailTextConfig # 失败页文案
var fail_ui: FailUiConfig
var pass_text: PassTextConfig # 过关页文案
var inter_unlock_level: InterUnlockLevelConfig # 插屏门槛：关卡数
var inter_unlock_session: InterUnlockSessionConfig # 插屏门槛：启动次数
var inter_unlock_memory: InterUnlockMemoryConfig # 插屏门槛：设备内存
var banner_unlock_level: BannerUnlockLevelConfig # banner 门槛：关卡数
var banner_unlock_session: BannerUnlockSessionConfig # banner 门槛：启动次数
var living_days: LivingDaysConfig # 按「存活天数」分段，供其它实验分档
var inter_cd_lc: InterCdLcConfig # 插屏冷却秒数
var inter_extra_protect_lc: InterExtraProtectLcConfig # 插屏额外保护方案
var banner_extra_protect_lc: BannerExtraProtectLcConfig # banner 额外保护方案
var banner_unlock_diff_lc: BannerUnlockDiffLcConfig # banner 尺寸白名单
var reward_unlock_level: RewardUnlockLevelConfig # 激励广告解锁门槛
var auto_complete: AutoCompleteConfig # 自动补全/自动打叉
var auto_x_fill_mode: AutoXFillModeConfig
var draft_mode: DraftModeConfig # 草稿模式

var att_dlg_logic: AttDlgLogicConfig # ATT 授权弹窗前的自定义引导
var common_rewardad_logic: CommonRewardadLogicConfig # 激励广告奖励补发
var daily_streak: DailyStreakConfig # 连续打卡
var daily_streak_encourage: DailyStreakEncourageConfig
var swipe_protect: SwipeProtectConfig # 滑动防误触
var swipe_logic: SwipeLogicConfig
var dda_rank: DdaRankConfig # 失败后 DDA 降档条件
var revive_countdown: ReviveCountdownConfig
var settings_language: SettingsLanguageConfig # 设置页语言切换入口
var single_region_num: SingleRegionNumConfig # 单格区域数量限制
var push_local_text: PushLocalTextConfig # 本地推送文案池
var push_sounds: PushSoundsConfig
var push_style: PushStyleConfig
var icon_crash: IconCrashConfig # 错标图标形态
var meow_feedback: MeowFeedbackConfig
var prop_highlight: PropHighlightConfig # 道具高亮引导
var auto_screen_off: AutoScreenOffConfig # 挂机自动息屏
var dc_level: DcLevelConfig # 每日挑战题池尺寸/难度
var mark_sound: MarkSoundConfig
var eliminate_effect: EliminateEffectConfig # 消除特效
var score_encourage: ScoreEncourageConfig
var push_permission: PushPermissionConfig
var push_unlock_level: PushUnlockLevelConfig
var pass_page: PassPageConfig
var loading_page_test: LoadingPageTestConfig
var pass_anim_cat: PassAnimCatConfig
var game_grid_ui: GameGridUiConfig
var bgm_test: BgmTestConfig # 背景音乐试听
var streak_protect: StreakProtectConfig
var hint_cat: HintCatConfig
var doubletap_protect: DoubletapProtectConfig
var vibrate_combo: VibrateComboConfig
var normal_top_ui: NormalTopUiConfig
var combo_text: ComboTextConfig
var combo_voice: ComboVoiceConfig # 连击语音包
var hard_button: HardButtonConfig
var normal_level: NormalLevelConfig
var home_entry_shape: HomeEntryShapeConfig
var dailystreak_icon: DailystreakIconConfig
var board_intro: BoardIntroConfig
var misplace_reaction: MisplaceReactionConfig
var blind_mod_entry: BlindModEntryConfig
var vibrate_add: VibrateAddConfig
var podium_per_game: PodiumPerGameConfig
var podium_per_leaderboard: PodiumPerLeaderboardConfig
var leaderboard_offline: LeaderboardOfflineConfig
var rank_1st_frame: Rank1stFrameConfig
var rank_bot_name: RankBotNameConfig
var is_vip: IsVipConfig
var vip_price: VipPriceConfig
var leaderboard_collection_levelwin: LeaderboardCollectionLevelwinConfig
var rank_like_func: RankLikeFuncConfig
var leaderboard_anim: LeaderboardAnimConfig
var unfinished_game_open: UnfinishedGameOpenConfig
var dc_beat_percent: DcBeatPercentConfig
var dc_pass_page: DcPassPageConfig
var dc_costume: DcCostumeConfig
var dc_start_toast: DcStartToastConfig
var font_test_en: FontTestEnConfig
var font_test_zh: FontTestZhConfig
var font_test_jp: FontTestJpConfig
var levelwin_anim: LevelWinAnimConfig
var prop_mouse: PropMouseConfig
var leaderboard_robot_logic: LeaderboardRobotLogicConfig
var dyeing_test: DyeingTestConfig
var app_login: AppLoginConfig
var win_red_mark: WinRedMarkConfig
var full_mark_feedback: FullMarkFeedbackConfig
var hint_func: HintFuncConfig
var art_game_end_title: ArtGameEndTitleConfig
var rank_state: RankStateConfig
var rank_offline_bar: RankOfflineBarConfig
var peekaboo_cat: PeekabooCatConfig
var cat_found_grid: CatFoundGridConfig
var health_points_rule: HealthPointsRuleConfig
var level_btn_continue: LevelBtnContinueConfig
var nu_guide: NuGuideConfig
var found_cat_animation: FoundCatAnimationConfig
var cat_toast: CatToastConfig
var grid_blast: GridBlastConfig
var barrage_func: BarrageFuncConfig
var guide_eliminate: GuideEliminateConfig
var text_highlight: TextHighlightConfig

var ad_compliance_ui: AdComplianceUiConfig # 广告合规标识
var blind_mod: BlindModConfig
var board_size_big: BoardSizeBigConfig
# ---- 实验配置实例（续） ----
var combo_encourage: ComboEncourageConfig # 连击鼓励表现
var daily_first_level_difficulty: DailyFirstLevelDifficultyConfig # 每日挑战首关难度
var inter_prob: InterProbConfig # 插屏展示概率
var leaderboard_func: LeaderboardFuncConfig
var pre_cat: PreCatConfig
var pre_cat_fx: PreCatFxConfig
var rate_us_pop_ui: RateUsPopUiConfig # 评分弹窗 UI 版本
var privacy_pop: PrivacyPopConfig
var revive_life: ReviveLifeConfig # 复活补命数量
var rule_normal_rank: RuleNormalRankConfig # 普通关难度与规则分组(A~K)
var size_cycle: SizeCycleConfig # 普通关棋盘尺寸循环
var third_rule_text: ThirdRuleTextConfig # 第三条规则文案
var win_toast: WinToastConfig # 过关步数 toast 覆盖档位
var win_encourage: WinEncourageConfig
var prop_position: PropPositionConfig
var blind_mod_color: BlindModColorConfig
var golden_fish_func: GoldenFishFuncConfig
var golden_fish_timing: GoldenFishTimingConfig
var no_network_remind: NoNetworkRemindConfig
var score_performance: ScorePerformanceConfig
var dc_number: DcNumberConfig
var multi_touch: MultiTouchConfig
var rank_win: RankWinConfig
var color_challenge_func: ColorChallengeFuncConfig
var first_win_encourage: FirstWinEncourageConfig
var daily_first_win_encourage: DailyFirstWinEncourageConfig
var inter_timing: InterTimingConfig
var comeback_func: ComebackFuncConfig
var system_dfps: SystemDfpsConfig
var leaderboard_reopen_timing: LeaderboardReopenTimingConfig
var home_companion_cat: HomeCompanionCatConfig
var golden_fish_precat: GoldenFishPrecatConfig
var near_death_fdb: NearDeathFdbConfig
var dc_endgame_save: DcEndgameSaveConfig
var wrong_zone_fdb: WrongZoneFdbConfig
var splash_slogan: SplashSloganConfig # 启动页标语

var daily_streak_success_page: DailyStreakSuccessPageConfig
var daily_streak_page: DailyStreakPageConfig

var _configs_by_key: Dictionary = {} # 实验 key → 配置实例，供 find_config 与按时机批量刷新使用

const _INIT_WAIT_TIMEOUT_SEC: float = 5.0

const _REMOTE_WAIT_TIMEOUT_SEC: float = 2.0

# ---- 染色时机：配置只在自己 timing 对应的时刻重新取值 ----
const TIMING_APP_START: String = "app_start" # 冷启动 A/B 就绪时
const TIMING_GAME_START: String = "game_start" # 每局开局时（普通与每日挑战都会调）

const TIMING_GAME_START_WITH_JP: String = "game_start_with_jp"

const TIMING_GAME_START_NORMAL: String = "game_start_normal" # 普通模式开局时

const TIMING_GAME_START_NORMAL_10: String = "game_start_normal_10"

const TIMING_GAME_START_NORMAL_11: String = "game_start_normal_11" # 普通模式第 11 关起

const TIMING_GAME_START_NORMAL_21: String = "game_start_normal_21" # 普通模式第 21 关起

const TIMING_GAME_START_NORMAL_34: String = "game_start_normal_34"

const TIMING_GAME_START_ONEFISH: String = "game_start_goldenfish"

const TIMING_GAME_START_PASS4_GOLDENFISH: String = "game_start_pass4goldenfish"

const TIMING_GAME_END: String = "game_end" # 本局失败结算时
const TIMING_GAME_FAIL: String = "game_fail"

const TIMING_GAME_END_NORMAL_20: String = "game_end_normal_20"

const TIMING_GAME_END_NORMAL_11: String = "game_end_normal_11"

const TIMING_GAME_END_NORMAL_10: String = "game_end_normal_10"

const TIMING_GAME_END_NORMAL_1: String = "game_end_normal_1"

const TIMING_GAME_START_DC: String = "game_start_dc" # 每日挑战开局时

const TIMING_HINT_USE: String = "hint_use" # 玩家使用提示道具时

const TIMING_NO_ACTION_270: String = "no_action_270" # 挂机 270 秒后

const TIMING_OPEN_SETTING: String = "open_setting"

const TIMING_OFF_DAYS_3: String = "off_days_3"
const TIMING_OFF_DAYS_2: String = "off_days_2"

const TIMING_LEVEL_REACH_51: String = "level_reach_51"

const TIMING_RANK_ACTIVITY_ING: String = "rank_activity_ing"

const TIMING_APP_START_NORMAL_50: String = "app_start_normal_50"

const TIMING_APP_START_WITH_EN: String = "app_start_with_en"

const TIMING_APP_START_WITH_ZH: String = "app_start_with_zh"

const TIMING_APP_START_WITH_JP: String = "app_start_with_jp"

const TIMING_HOME_PAGE_10S: String = "home_page_10s"

const TIMING_ONE_FISH_CAT: String = "one_fish_cat"


# ================= 生命周期与注册 =================
## 进树时注册全部配置，并订阅 UniKit 的 A/B 事件
func _ready() -> void:
	_register_configs()
	UniKitManager.abtest_ready.connect(_on_abtest_ready)
	UniKitManager.abtest_params_updated.connect(_on_abtest_params_updated)
	UniKitManager.abtest_remote_config_ready.connect(_on_abtest_remote_config_ready)
	UniKitManager.abtest_locsrv_fetched.connect(_on_abtest_locsrv_fetched)


func _register_configs() -> void:
	region_color = RegionColorConfig.new()
	normal_start_toast = NormalStartToastConfig.new()
	normal_start_toast_text = NormalStartToastTextConfig.new()
	thumb_up = ThumbUpConfig.new()
	normal_endgame_save = NormalEndgameSaveConfig.new()
	rate_us_pop = RateUsPopConfig.new()
	life_icon = LifeIconConfig.new()
	fail_text = FailTextConfig.new()
	fail_ui = FailUiConfig.new()
	pass_text = PassTextConfig.new()
	inter_unlock_level = InterUnlockLevelConfig.new()
	inter_unlock_session = InterUnlockSessionConfig.new()
	inter_unlock_memory = InterUnlockMemoryConfig.new()
	banner_unlock_level = BannerUnlockLevelConfig.new()
	banner_unlock_session = BannerUnlockSessionConfig.new()
	living_days = LivingDaysConfig.new()
	inter_cd_lc = InterCdLcConfig.new()
	inter_extra_protect_lc = InterExtraProtectLcConfig.new()
	banner_extra_protect_lc = BannerExtraProtectLcConfig.new()
	banner_unlock_diff_lc = BannerUnlockDiffLcConfig.new()
	reward_unlock_level = RewardUnlockLevelConfig.new()
	auto_complete = AutoCompleteConfig.new()
	auto_x_fill_mode = AutoXFillModeConfig.new()
	draft_mode = DraftModeConfig.new()
	att_dlg_logic = AttDlgLogicConfig.new()
	common_rewardad_logic = CommonRewardadLogicConfig.new()
	daily_streak = DailyStreakConfig.new()
	daily_streak_encourage = DailyStreakEncourageConfig.new()
	swipe_protect = SwipeProtectConfig.new()
	swipe_logic = SwipeLogicConfig.new()
	dda_rank = DdaRankConfig.new()
	revive_countdown = ReviveCountdownConfig.new()
	settings_language = SettingsLanguageConfig.new()
	single_region_num = SingleRegionNumConfig.new()
	push_local_text = PushLocalTextConfig.new()
	push_sounds = PushSoundsConfig.new()
	push_style = PushStyleConfig.new()
	icon_crash = IconCrashConfig.new()
	meow_feedback = MeowFeedbackConfig.new()
	prop_highlight = PropHighlightConfig.new()
	auto_screen_off = AutoScreenOffConfig.new()
	dc_level = DcLevelConfig.new()
	mark_sound = MarkSoundConfig.new()
	eliminate_effect = EliminateEffectConfig.new()
	score_encourage = ScoreEncourageConfig.new()
	push_permission = PushPermissionConfig.new()
	push_unlock_level = PushUnlockLevelConfig.new()
	pass_page = PassPageConfig.new()
	loading_page_test = LoadingPageTestConfig.new()
	pass_anim_cat = PassAnimCatConfig.new()
	game_grid_ui = GameGridUiConfig.new()
	bgm_test = BgmTestConfig.new()
	streak_protect = StreakProtectConfig.new()
	hint_cat = HintCatConfig.new()
	doubletap_protect = DoubletapProtectConfig.new()
	vibrate_combo = VibrateComboConfig.new()
	normal_top_ui = NormalTopUiConfig.new()
	combo_text = ComboTextConfig.new()
	combo_voice = ComboVoiceConfig.new()
	hard_button = HardButtonConfig.new()
	normal_level = NormalLevelConfig.new()
	home_entry_shape = HomeEntryShapeConfig.new()
	dailystreak_icon = DailystreakIconConfig.new()
	board_intro = BoardIntroConfig.new()
	misplace_reaction = MisplaceReactionConfig.new()
	blind_mod_entry = BlindModEntryConfig.new()
	vibrate_add = VibrateAddConfig.new()
	podium_per_game = PodiumPerGameConfig.new()
	podium_per_leaderboard = PodiumPerLeaderboardConfig.new()
	leaderboard_offline = LeaderboardOfflineConfig.new()
	rank_1st_frame = Rank1stFrameConfig.new()
	rank_bot_name = RankBotNameConfig.new()
	is_vip = IsVipConfig.new()
	vip_price = VipPriceConfig.new()
	leaderboard_collection_levelwin = LeaderboardCollectionLevelwinConfig.new()
	rank_like_func = RankLikeFuncConfig.new()
	leaderboard_anim = LeaderboardAnimConfig.new()
	unfinished_game_open = UnfinishedGameOpenConfig.new()
	dc_beat_percent = DcBeatPercentConfig.new()
	dc_pass_page = DcPassPageConfig.new()
	dc_costume = DcCostumeConfig.new()
	dc_start_toast = DcStartToastConfig.new()
	font_test_en = FontTestEnConfig.new()
	font_test_zh = FontTestZhConfig.new()
	font_test_jp = FontTestJpConfig.new()
	levelwin_anim = LevelWinAnimConfig.new()
	prop_mouse = PropMouseConfig.new()
	leaderboard_robot_logic = LeaderboardRobotLogicConfig.new()
	dyeing_test = DyeingTestConfig.new()
	app_login = AppLoginConfig.new()
	win_red_mark = WinRedMarkConfig.new()
	full_mark_feedback = FullMarkFeedbackConfig.new()
	hint_func = HintFuncConfig.new()
	art_game_end_title = ArtGameEndTitleConfig.new()
	rank_state = RankStateConfig.new()
	rank_offline_bar = RankOfflineBarConfig.new()
	peekaboo_cat = PeekabooCatConfig.new()
	cat_found_grid = CatFoundGridConfig.new()
	health_points_rule = HealthPointsRuleConfig.new()
	level_btn_continue = LevelBtnContinueConfig.new()
	nu_guide = NuGuideConfig.new()
	found_cat_animation = FoundCatAnimationConfig.new()
	grid_blast = GridBlastConfig.new()
	barrage_func = BarrageFuncConfig.new()
	guide_eliminate = GuideEliminateConfig.new()
	text_highlight = TextHighlightConfig.new()

	ad_compliance_ui = AdComplianceUiConfig.new()
	blind_mod = BlindModConfig.new()
	board_size_big = BoardSizeBigConfig.new()
	combo_encourage = ComboEncourageConfig.new()
	daily_first_level_difficulty = DailyFirstLevelDifficultyConfig.new()
	inter_prob = InterProbConfig.new()
	leaderboard_func = LeaderboardFuncConfig.new()
	pre_cat = PreCatConfig.new()
	pre_cat_fx = PreCatFxConfig.new()
	rate_us_pop_ui = RateUsPopUiConfig.new()
	privacy_pop = PrivacyPopConfig.new()
	revive_life = ReviveLifeConfig.new()
	rule_normal_rank = RuleNormalRankConfig.new()
	size_cycle = SizeCycleConfig.new()
	third_rule_text = ThirdRuleTextConfig.new()
	win_toast = WinToastConfig.new()
	win_encourage = WinEncourageConfig.new()
	prop_position = PropPositionConfig.new()
	blind_mod_color = BlindModColorConfig.new()
	golden_fish_func = GoldenFishFuncConfig.new()
	golden_fish_timing = GoldenFishTimingConfig.new()
	no_network_remind = NoNetworkRemindConfig.new()
	score_performance = ScorePerformanceConfig.new()
	cat_toast = CatToastConfig.new()
	dc_number = DcNumberConfig.new()
	multi_touch = MultiTouchConfig.new()
	rank_win = RankWinConfig.new()
	color_challenge_func = ColorChallengeFuncConfig.new()
	first_win_encourage = FirstWinEncourageConfig.new()
	daily_first_win_encourage = DailyFirstWinEncourageConfig.new()
	inter_timing = InterTimingConfig.new()
	comeback_func = ComebackFuncConfig.new()
	system_dfps = SystemDfpsConfig.new()
	leaderboard_reopen_timing = LeaderboardReopenTimingConfig.new()
	home_companion_cat = HomeCompanionCatConfig.new()
	golden_fish_precat = GoldenFishPrecatConfig.new()
	near_death_fdb = NearDeathFdbConfig.new()
	dc_endgame_save = DcEndgameSaveConfig.new()
	wrong_zone_fdb = WrongZoneFdbConfig.new()
	daily_streak_success_page = DailyStreakSuccessPageConfig.new()
	daily_streak_page = DailyStreakPageConfig.new()
	splash_slogan = SplashSloganConfig.new()

	for cfg: AbConfigBase in [
		region_color,
		normal_start_toast,
		normal_start_toast_text,
		thumb_up,
		normal_endgame_save,
		rate_us_pop,
		life_icon,
		fail_text,
		fail_ui,
		pass_text,
		inter_unlock_level,
		inter_unlock_session,
		inter_unlock_memory,
		banner_unlock_level,
		banner_unlock_session,
		living_days,
		inter_cd_lc,
		inter_extra_protect_lc,
		banner_extra_protect_lc,
		banner_unlock_diff_lc,
		reward_unlock_level,
		auto_complete,
		auto_x_fill_mode,
		draft_mode,
		att_dlg_logic,
		common_rewardad_logic,
		daily_streak,
		daily_streak_encourage,
		swipe_protect,
		swipe_logic,
		dda_rank,
		revive_countdown,
		settings_language,
		single_region_num,
		push_local_text,
		push_sounds,
		push_style,
		icon_crash,
		meow_feedback,
		prop_highlight,
		auto_screen_off,
		dc_level,
		mark_sound,
		eliminate_effect,
		score_encourage,
		push_permission,
		push_unlock_level,
		pass_page,
		streak_protect,
		hint_cat,
		doubletap_protect,
		game_grid_ui,
		bgm_test,
		vibrate_combo,
		normal_top_ui,
		combo_text,
		combo_voice,
		hard_button,
		normal_level,
		home_entry_shape,
		dailystreak_icon,
		board_intro,
		misplace_reaction,
		blind_mod_entry,
		vibrate_add,
		podium_per_game,
		podium_per_leaderboard,
		leaderboard_offline,
		rank_1st_frame,
		rank_bot_name,
		is_vip,
		vip_price,
		leaderboard_collection_levelwin,
		rank_like_func,
		leaderboard_anim,
		pass_anim_cat,
		unfinished_game_open,
		dc_beat_percent,
		dc_pass_page,
		dc_costume,
		dc_start_toast,
		font_test_en,
		font_test_zh,
		font_test_jp,
		levelwin_anim,
		prop_mouse,
		leaderboard_robot_logic,
		dyeing_test,
		app_login,
		win_red_mark,
		full_mark_feedback,
		hint_func,
		loading_page_test,
		art_game_end_title,
		rank_state,
		rank_offline_bar,
		peekaboo_cat,
		cat_found_grid,
		health_points_rule,
		level_btn_continue,
		nu_guide,
		found_cat_animation,
		barrage_func,
		score_performance,
		cat_toast,
		dc_number,
		grid_blast,
		system_dfps,
		guide_eliminate,
		rank_win,
		text_highlight,
		inter_timing,
		golden_fish_timing,
		ad_compliance_ui,
		blind_mod,
		board_size_big,
		combo_encourage,
		daily_first_level_difficulty,
		inter_prob,
		leaderboard_func,
		pre_cat,
		pre_cat_fx,
		rate_us_pop_ui,
		privacy_pop,
		revive_life,
		rule_normal_rank,
		size_cycle,
		third_rule_text,
		win_toast,
		win_encourage,
		prop_position,
		blind_mod_color,
		golden_fish_func,
		no_network_remind,
		multi_touch,
		color_challenge_func,
		first_win_encourage,
		daily_first_win_encourage,
		comeback_func,
		leaderboard_reopen_timing,
		home_companion_cat,
		golden_fish_precat,
		near_death_fdb,
		dc_endgame_save,
		wrong_zone_fdb,
		daily_streak_success_page,
		daily_streak_page,
		splash_slogan,
	]:
		cfg.init_default()
		_configs_by_key[cfg.key] = cfg
	_apply_editor_only_overrides()


func _apply_editor_only_overrides() -> void:
	if not OS.has_feature("editor"):
		return

	if not home_entry_shape.is_value_loaded():
		home_entry_shape.set_debug_override(HomeEntryShapeConfig.VALUE_RANK_SIDE)
	if not peekaboo_cat.is_value_loaded():
		peekaboo_cat.set_debug_override(PeekabooCatConfig.VALUE_AD_POPUP)
	if not home_companion_cat.is_value_loaded():
		home_companion_cat.set_debug_override(HomeCompanionCatConfig.VALUE_SATIETY)
	print(
		"[ABTest] 仅编辑器：无本地覆盖的 home_entry_shape / peekaboo_cat / home_companion_cat 使用编辑器默认分组，导出包不受影响"
	)


func _on_abtest_ready(_user_info: Dictionary) -> void:
	if _is_init_done:
		return
	_is_init_done = true
	if _is_init_success_done:
		_finalize_app_start_dye()
	print("[ABTestManager] init ready")


func _on_abtest_remote_config_ready() -> void:
	print("[ABTestManager] remote config ready")
	_is_remote_ready = true


func _finalize_app_start_dye() -> void:
	if _app_start_dyed:
		return
	_app_start_dyed = true

	_load_all_values()
	dye_at_app_start()
	if GameState.get_login_gap_days() >= 2:
		dye_at_off_days_2()
	if GameState.get_login_gap_days() >= 3:
		dye_at_off_days_3()

	var cur_lv: int = GameState.get_current_level()
	if cur_lv >= 50:
		print("[UnfinishedOpen] dye app_start_normal_50 (level=%d)" % cur_lv)
		dye_at_app_start_normal_50()
	else:
		print("[UnfinishedOpen] app_start_normal_50 skip: level=%d<50" % cur_lv)

	if RankActivityManager.is_running():
		dye_at_rank_activity_ing()

	RankActivityManager.period_opened.connect(_on_rank_period_opened)

	match LanguageManager.resolve_language_family():
		"en":
			dye_at_app_start_with_en()
		"zh":
			dye_at_app_start_with_zh()
		"jp":
			dye_at_app_start_with_jp()
	if _is_init_done:
		init_done.emit()
	if _is_remote_ready:
		remote_ready.emit()


func _on_rank_period_opened(_period_count: int) -> void:
	dye_at_rank_activity_ing()


## SDK 参数更新回调：原样转发，不主动刷新配置
func _on_abtest_params_updated(update_type: String, user_info: Dictionary) -> void:
	params_updated.emit(update_type, user_info)


func _on_abtest_locsrv_fetched(success: bool) -> void:
	_is_locsrv_fetched = success
	print("[ABTestManager] locsrv fetched: success=%s" % success)
	locsrv_fetched.emit(success)


func _should_skip_init_wait() -> bool:
	var cached: int = GameState.get_saved_ab_group(dyeing_test.key)
	var skip: bool = DyeingTestConfig.should_skip_for_cached(cached)
	print("[ABTestManager] init_wait: cached=%d skip=%s" % [cached, skip])
	return skip


func init_success() -> void:
	if OS.has_feature("editor"):
		_is_init_done = true
		_is_remote_ready = true
	var ready_wait: float = _INIT_WAIT_TIMEOUT_SEC
	await _await_ready(ready_wait)
	print("[ABTestManager] init_wait: 第①步开始等 abtest_init,上限 %.1fs" % ready_wait)
	var remote_arrived: bool = await _await_remote_ready(_REMOTE_WAIT_TIMEOUT_SEC)
	if not remote_arrived:
		print("[ABTestManager] 远端配置 %.1fs 内未到,APP_START 按本地配置染色" % _REMOTE_WAIT_TIMEOUT_SEC)
		_is_remote_ready = true

	if not _is_init_done and (OS.has_feature("android") or OS.has_feature("ios")):
		var cause: String = (
			"UniKit plugin unavailable"
			if not UniKitManager.is_available()
			else "abtest_init timeout(%.1fs)" % _INIT_WAIT_TIMEOUT_SEC
		)
		print("ABTestManager: %s,APP_START 将染 default_value" % cause)
	if _is_init_done:
		_finalize_app_start_dye()
	_is_init_success_done = true


func _await_ready(timeout_sec: float) -> bool:
	if _is_init_done:
		return true
	while not _is_init_done:
		await get_tree().process_frame
	return _is_init_done


func _await_remote_ready(timeout_sec: float) -> bool:
	if _is_remote_ready:
		return true
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	while not _is_remote_ready and timer.time_left > 0.0:
		await get_tree().process_frame
	return _is_remote_ready


# ================= UniKit 转发：取值与染色 =================
## 转发 UniKit：按 key 取字符串型实验值
func get_ab_string(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_string(key, default_value)


## 转发 UniKit：按 key 取整数型实验值
func get_ab_int(key: String, default_value: int = 0) -> int:
	return UniKitManager.get_ab_int(key, default_value)


## 转发 UniKit：按 key 取浮点型实验值
func get_ab_float(key: String, default_value: float = 0.0) -> float:
	return UniKitManager.get_ab_float(key, default_value)


## 转发 UniKit：上报一次实验染色（影响后台统计口径）
func dye_ab(key: String) -> void:
	UniKitManager.dye_ab(key)


## 转发 UniKit：取全部实验分组（含未发布）
func get_all_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_ab_experiments()


## 转发 UniKit：只取已发布的实验分组
func get_all_publish_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_publish_ab_experiments()


func is_ab_dyeing(key: String) -> bool:
	return UniKitManager.is_ab_dyeing(key)


func get_ab_group_status(key: String) -> String:
	return UniKitManager.get_ab_group_status(key)


func get_ab_dyeing_time(key: String) -> String:
	return UniKitManager.get_ab_dyeing_time(key)


func get_all_ab_dyeing_times() -> Dictionary:
	return UniKitManager.get_all_ab_dyeing_times()


## 取当前已染色实验的汇总标签（上报用）
func get_ab_dyeing_tag() -> String:
	return UniKitManager.get_ab_dyeing_tag()


## 取全部实验的汇总标签（上报用）
func get_ab_all_tag() -> String:
	return UniKitManager.get_ab_all_tag()


## 取分流用的 group id
func get_ab_group_id() -> String:
	return UniKitManager.get_ab_group_id()


## 取分流用的国家/地区
func get_ab_country() -> String:
	return UniKitManager.get_ab_country()


# ================= UniKit 转发：地区服务 =================
## 取地区服务(locsrv)下发的实验参数
func get_ab_locsrv(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_locsrv_param(key, default_value)


## 取地区服务下发的全部参数
func get_all_ab_locsrv() -> Dictionary:
	return UniKitManager.get_all_ab_locsrv_params()


## 异步拉取地区服务参数，结果通过 locsrv_fetched 信号回来
func fetch_ab_locsrv() -> void:
	UniKitManager.fetch_remote_ab_result()


## 上报某个地区服务参数的染色
func dye_ab_locsrv(key: String) -> void:
	UniKitManager.dye_ab_locsrv(key)


## 上报地区服务参数的自定义标签
func dye_ab_locsrv_tag(tag: String) -> void:
	UniKitManager.dye_ab_locsrv_tag(tag)


## 批量设置地区服务标签，参与后续上报
func set_ab_locsrv_all_tag(tags: Array[String]) -> void:
	UniKitManager.set_ab_locsrv_all_tag(tags)


## 取参与分流的用户信息（上报用）
func get_ab_user_info() -> Dictionary:
	return UniKitManager.get_ab_user_info()


## 强制指定 group id（调试/复现线上分组用）
func set_ab_group_id(group_id: String) -> void:
	UniKitManager.set_ab_group_id(group_id)


## 强制指定国家/地区（调试/复现线上分组用）
func set_ab_country(country: String) -> void:
	UniKitManager.set_ab_country(country)


# ================= 状态查询与配置查找 =================
## A/B 是否已初始化完成
func is_ab_init_done() -> bool:
	return _is_init_done


func is_app_start_dyed() -> bool:
	return _app_start_dyed


## 地区服务参数是否已成功拉到
func is_ab_locsrv_fetched() -> bool:
	return _is_locsrv_fetched


## 取全部配置实例（作弊面板遍历用），顺序为字典遍历序
func get_all_configs() -> Array[AbConfigBase]:
	var out: Array[AbConfigBase] = []
	for cfg: AbConfigBase in _configs_by_key.values():
		out.append(cfg)
	return out


## 按 key 找配置实例，找不到返回 null
func find_config(key: String) -> AbConfigBase:
	return _configs_by_key.get(key, null) as AbConfigBase


# ================= 按时机批量染色 =================
## 刷新 app_start 时机的配置（由 _finalize_app_start_dye 调用）
func dye_at_app_start() -> void:
	_dye_at_timing(TIMING_APP_START)


## 刷新每局开局时机的配置（普通关与每日挑战开局都调）
func dye_at_game_start() -> void:
	_dye_at_timing(TIMING_GAME_START)


func dye_at_game_start_with_jp() -> void:
	_dye_at_timing(TIMING_GAME_START_WITH_JP)


## 刷新普通模式开局时机的配置（仅在普通模式调）
func dye_at_game_start_normal() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL)


func dye_at_game_start_normal_10() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_10)


## 刷新第 11 关起生效的配置（GamePage 判关卡 >= 11 后调）
func dye_at_game_start_normal_11() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_11)


## 刷新第 21 关起生效的配置（GamePage 判关卡 >= 21 后调）
func dye_at_game_start_normal_21() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_21)


func dye_at_game_start_normal_34() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_34)


func dye_at_game_start_onefish() -> void:
	_dye_at_timing(TIMING_GAME_START_ONEFISH)


func dye_at_game_start_pass4_goldenfish() -> void:
	_dye_at_timing(TIMING_GAME_START_PASS4_GOLDENFISH)


func dye_at_game_fail_end() -> void:
	_dye_at_timing(TIMING_GAME_END)
	_dye_at_timing(TIMING_GAME_FAIL)


func dye_at_game_win_end() -> void:
	_dye_at_timing(TIMING_GAME_END)


func dye_at_game_end_normal_20() -> void:
	_dye_at_timing(TIMING_GAME_END_NORMAL_20)


func dye_at_game_end_normal_11() -> void:
	_dye_at_timing(TIMING_GAME_END_NORMAL_11)


func dye_at_game_end_normal_10() -> void:
	_dye_at_timing(TIMING_GAME_END_NORMAL_10)


func dye_at_game_end_normal_1() -> void:
	_dye_at_timing(TIMING_GAME_END_NORMAL_1)


## 刷新每日挑战开局时机的配置
func dye_at_game_start_dc() -> void:
	_dye_at_timing(TIMING_GAME_START_DC)


## 刷新使用提示时机的配置
func dye_at_hint_use() -> void:
	_dye_at_timing(TIMING_HINT_USE)


## 刷新挂机 270 秒时机的配置（由 ScreenManager 空闲超时调用）
func dye_at_no_action_270() -> void:
	_dye_at_timing(TIMING_NO_ACTION_270)


func dye_at_open_setting() -> void:
	_dye_at_timing(TIMING_OPEN_SETTING)


func dye_at_off_days_3() -> void:
	_dye_at_timing(TIMING_OFF_DAYS_3)


func dye_at_off_days_2() -> void:
	_dye_at_timing(TIMING_OFF_DAYS_2)


func dye_at_level_reach_51() -> void:
	_dye_at_timing(TIMING_LEVEL_REACH_51)


func dye_at_app_start_normal_50() -> void:
	_dye_at_timing(TIMING_APP_START_NORMAL_50)


func dye_at_rank_activity_ing() -> void:
	_dye_at_timing(TIMING_RANK_ACTIVITY_ING)


func dye_at_app_start_with_en() -> void:
	_dye_at_timing(TIMING_APP_START_WITH_EN)


func dye_at_app_start_with_zh() -> void:
	_dye_at_timing(TIMING_APP_START_WITH_ZH)


func dye_at_app_start_with_jp() -> void:
	_dye_at_timing(TIMING_APP_START_WITH_JP)


func dye_at_home_page_10s() -> void:
	if _home_page_10s_dyed:
		return
	_home_page_10s_dyed = true
	_dye_at_timing(TIMING_HOME_PAGE_10S)


func dye_at_one_fish_cat() -> void:
	_dye_at_timing(TIMING_ONE_FISH_CAT)


func _load_all_values() -> void:
	if _all_values_loaded:
		return
	_all_values_loaded = true

	var all_exp: Dictionary = get_all_ab_experiments()
	var loaded: int = 0
	for cfg: AbConfigBase in _configs_by_key.values():
		if not all_exp.has(cfg.key):
			GameState.erase_saved_peek_ab_group(cfg.key)
			continue
		cfg.load_value()
		loaded += 1

	print(
		(
			"[ABTestManager] 全量提前赋值完成 loaded=%d / 注册=%d / SDK下发=%d"
			% [loaded, _configs_by_key.size(), all_exp.size()]
		)
	)


func _dye_at_timing(t: String) -> void:
	var reloaded: Array[String] = []
	for cfg: AbConfigBase in _configs_by_key.values():
		if get_ab_dyeing_time(cfg.key) != t:
			continue

		cfg.load_value()
		cfg.dye()
		reloaded.append(cfg.key)

	if not reloaded.is_empty():
		values_reloaded.emit(t, reloaded)
		_emit_timeline_tag(t, reloaded.size())


func _emit_timeline_tag(t: String, n: int) -> void:
	if not is_instance_valid(EventBus):
		return
	(
		EventBus
		. emit_event(
			EventName.AB_TAG,
			{
				"timing": t,
				"n": n,
				"tag": get_ab_dyeing_tag(),
			}
		)
	)
