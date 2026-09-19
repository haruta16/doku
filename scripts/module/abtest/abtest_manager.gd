# A/B 实验总入口：注册 70 个实验配置、转发 UniKit 事件、按染色时机批量刷新取值
extends Node

signal init_done # A/B 初始化完成，此时读取实验值才是安全的
signal params_updated(update_type: String, user_info: Dictionary) # SDK 推送参数更新，原样转发给业务层
signal remote_ready # 远端配置就绪且 app_start 档位已染色
signal locsrv_fetched(success: bool, error: String) # 地区服务(locsrv)参数拉取结束，error 为失败原因

# ---- 初始化与远端就绪状态 ----
var _is_init_done: bool = false # 是否已收到 abtest_ready

var _is_remote_ready: bool = false # 远端配置是否就绪（await 超时也会强行置位）

var _app_start_dyed: bool = false # app_start 档位是否已染色，保证只染一次
var _is_locsrv_fetched: bool = false # 地区服务参数是否拉取成功

# ---- 实验配置实例（_register_configs 里逐个 new 出来） ----
var region_color: RegionColorConfig # 区域配色方案
var size_cycle: SizeCycleConfig # 普通关棋盘尺寸循环
var rule_highlight: RuleHighlightConfig # 规则条高亮
var goal_emphasis: GoalEmphasisConfig # 目标(猫数)强调
var function_clear: FunctionClearConfig # 一键清空按钮
var normal_start_toast: NormalStartToastConfig # 普通关开局提示条
var thumb_up: ThumbUpConfig # 点赞/鼓掌反馈组合
var rule_normal_rank: RuleNormalRankConfig # 普通关难度与规则分组(A~K)
var tutorial_diagonal: TutorialDiagonalConfig # 新手教学：对角线复制
var normal_endgame_save: NormalEndgameSaveConfig # 普通关残局存档
var rate_us_pop: RateUsPopConfig # 评分弹窗触发时机
var warn_life: WarnLifeConfig # 生命不足告警
var life_icon: LifeIconConfig # 生命条图标
var fail_text: FailTextConfig # 失败页文案
var play_anim: PlayAnimConfig # 猫待机动画
var pass_text: PassTextConfig # 过关页文案
var draft_mode: DraftModeConfig # 草稿模式
var inter_unlock_level: InterUnlockLevelConfig # 插屏门槛：关卡数
var inter_unlock_session: InterUnlockSessionConfig # 插屏门槛：启动次数
var inter_unlock_memory: InterUnlockMemoryConfig # 插屏门槛：设备内存
var banner_unlock_level: BannerUnlockLevelConfig # banner 门槛：关卡数
var banner_unlock_session: BannerUnlockSessionConfig # banner 门槛：启动次数
var living_days: LivingDaysConfig # 按「存活天数」分段，供其它实验分档
var inter_cd_lc: InterCdLcConfig # 插屏冷却秒数
var inter_extra_protect_lc: InterExtraProtectLcConfig # 插屏额外保护方案
var inter_prob: InterProbConfig # 插屏展示概率
var banner_extra_protect_lc: BannerExtraProtectLcConfig # banner 额外保护方案
var banner_unlock_diff_lc: BannerUnlockDiffLcConfig # banner 尺寸白名单
var reward_unlock_level: RewardUnlockLevelConfig # 激励广告解锁门槛
var guide_feedback: GuideFeedbackConfig # 新手引导反馈形态
var idle_guide: IdleGuideConfig # 挂机引导
var auto_complete: AutoCompleteConfig # 自动补全/自动打叉
var third_rule_text: ThirdRuleTextConfig # 第三条规则文案
var progress_emphasis: ProgressEmphasisConfig # 进度强调方式
var daily_first_level_difficulty: DailyFirstLevelDifficultyConfig # 每日挑战首关难度
var revive_free_logic: ReviveFreeLogicConfig # 免费复活规则
var undo_btn: UndoBtnConfig # 撤销/高亮按钮
var no_dc: NoDcConfig # 每日挑战入口显隐

# ---- 实验配置实例（续） ----
var combo_encourage: ComboEncourageConfig # 连击鼓励表现
var att_dlg_logic: AttDlgLogicConfig # ATT 授权弹窗前的自定义引导
var dc_tag_ui: DcTagUiConfig # 每日挑战角标样式
var game_page_rules_ui: GamePageRulesUiConfig # 对局页规则栏位置
var rate_us_pop_ui: RateUsPopUiConfig # 评分弹窗 UI 版本
var common_rewardad_logic: CommonRewardadLogicConfig # 激励广告奖励补发
var daily_streak: DailyStreakConfig # 连续打卡
var error_feedback: ErrorFeedbackConfig # 错误反馈触发范围
var game_life_rule: GameLifeRuleConfig # 对局内生命 +1 规则
var rule_text: RuleTextConfig # 规则展示形态
var normal_level_10: NormalLevel10Config # 普通第 10 关特殊题
var ad_compliance_ui: AdComplianceUiConfig # 广告合规标识
var error_catface: ErrorCatfaceConfig # 错标时猫的表情
var swipe_protect: SwipeProtectConfig # 滑动防误触
var dda_rank: DdaRankConfig # 失败后 DDA 降档条件
var revive_life: ReviveLifeConfig # 复活补命数量
var eliminate_effect: EliminateEffectConfig # 消除特效
var game_auto_mark: GameAutoMarkConfig # 自动打叉与锁叉
var win_toast: WinToastConfig # 过关步数 toast 覆盖档位
var settings_language: SettingsLanguageConfig # 设置页语言切换入口
var tap_feedback: TapFeedbackConfig # 点击反馈(按下/抬起)
var bgm_test: BgmTestConfig # 背景音乐试听
var single_region_num: SingleRegionNumConfig # 单格区域数量限制
var push_local_text: PushLocalTextConfig # 本地推送文案池
var icon_crash: IconCrashConfig # 错标图标形态
var wrong_cat_effect: WrongCatEffectConfig # 错猫震动/音效强度
var combo_voice: ComboVoiceConfig # 连击语音包
var hint_ue: HintUeConfig # 提示交互流程
var prop_highlight: PropHighlightConfig # 道具高亮引导
var auto_screen_off: AutoScreenOffConfig # 挂机自动息屏
var dc_level: DcLevelConfig # 每日挑战题池尺寸/难度
var splash_slogan: SplashSloganConfig # 启动页标语

var _configs_by_key: Dictionary = {} # 实验 key → 配置实例，供 find_config 与按时机批量刷新使用

# ---- 染色时机：配置只在自己 timing 对应的时刻重新取值 ----
const TIMING_APP_START: String = "app_start" # 冷启动 A/B 就绪时
const TIMING_GAME_START: String = "game_start" # 每局开局时（普通与每日挑战都会调）

const TIMING_GAME_START_NORMAL: String = "game_start_normal" # 普通模式开局时

const TIMING_GAME_START_NORMAL_11: String = "game_start_normal_11" # 普通模式第 11 关起

const TIMING_GAME_START_NORMAL_21: String = "game_start_normal_21" # 普通模式第 21 关起

const TIMING_GAME_END: String = "game_end" # 本局失败结算时

const TIMING_GAME_START_DC: String = "game_start_dc" # 每日挑战开局时

const TIMING_HINT_USE: String = "hint_use" # 玩家使用提示道具时

const TIMING_NO_ACTION_270: String = "no_action_270" # 挂机 270 秒后


# ================= 生命周期与注册 =================
# 进树时注册全部配置，并订阅 UniKit 的 A/B 事件
func _ready() -> void:
	_register_configs()
	UniKitManager.abtest_ready.connect(_on_abtest_ready)
	UniKitManager.abtest_params_updated.connect(_on_abtest_params_updated)
	UniKitManager.abtest_remote_config_ready.connect(_on_abtest_remote_config_ready)
	UniKitManager.abtest_locsrv_fetched.connect(_on_abtest_locsrv_fetched)


# 逐个 new 出配置实例，init_default 后按 key 建索引；时机常量在染色时按字符串匹配
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


# ================= UniKit 事件回调 =================
# A/B 就绪回调：只认第一次，置位后广播 init_done
func _on_abtest_ready(_user_info: Dictionary) -> void:
	if _is_init_done:
		return
	_is_init_done = true
	print("[ABTestManager] init ready")
	init_done.emit()
	_finalize_app_start_dye()


# 远端配置就绪回调：与 init 谁后到谁负责收口染色
func _on_abtest_remote_config_ready() -> void:
	print("[ABTestManager] remote config ready")
	_finalize_app_start_dye()


# app_start 档位的一次性收口：染色 + 置 remote_ready（重复调用直接返回）
func _finalize_app_start_dye() -> void:
	if _app_start_dyed:
		return
	_app_start_dyed = true
	_is_remote_ready = true
	dye_at_app_start()
	remote_ready.emit()


# SDK 参数更新回调：原样转发，不主动刷新配置
func _on_abtest_params_updated(update_type: String, user_info: Dictionary) -> void:
	params_updated.emit(update_type, user_info)


# 地区服务拉取回调：记录成功与否并转发
func _on_abtest_locsrv_fetched(success: bool, error: String) -> void:
	_is_locsrv_fetched = success
	print("[ABTestManager] locsrv fetched: success=%s error=%s" % [success, error])
	locsrv_fetched.emit(success, error)


# ================= 等待就绪 =================
# 逐帧等待 A/B 初始化，超时（默认 2 秒）返回 false，不会无限阻塞
func await_ready(timeout_sec: float = 2.0) -> bool:
	if _is_init_done:
		return true
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	while not _is_init_done and timer.time_left > 0.0:
		await get_tree().process_frame
	return _is_init_done


# 等待远端配置就绪；超时则强制执行一次 app_start 染色，保证后续取值有兜底
func await_remote_ready(timeout_sec: float = 2.0) -> bool:
	if _is_remote_ready:
		return true
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	while not _is_remote_ready and timer.time_left > 0.0:
		await get_tree().process_frame
	if not _is_remote_ready:
		_finalize_app_start_dye()
	return _is_remote_ready


# ================= UniKit 转发：取值与染色 =================
# 转发 UniKit：按 key 取字符串型实验值
func get_ab_string(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_string(key, default_value)


# 转发 UniKit：按 key 取整数型实验值
func get_ab_int(key: String, default_value: int = 0) -> int:
	return UniKitManager.get_ab_int(key, default_value)


# 转发 UniKit：按 key 取浮点型实验值
func get_ab_float(key: String, default_value: float = 0.0) -> float:
	return UniKitManager.get_ab_float(key, default_value)


# 转发 UniKit：上报一次实验染色（影响后台统计口径）
func dye_ab(key: String) -> void:
	UniKitManager.dye_ab(key)


# 转发 UniKit：取全部实验分组（含未发布）
func get_all_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_ab_experiments()


# 转发 UniKit：只取已发布的实验分组
func get_all_publish_ab_experiments() -> Dictionary:
	return UniKitManager.get_all_publish_ab_experiments()


# 取当前已染色实验的汇总标签（上报用）
func get_ab_dyeing_tag() -> String:
	return UniKitManager.get_ab_dyeing_tag()


# 取全部实验的汇总标签（上报用）
func get_ab_all_tag() -> String:
	return UniKitManager.get_ab_all_tag()


# 取分流用的 group id
func get_ab_group_id() -> String:
	return UniKitManager.get_ab_group_id()


# 取分流用的国家/地区
func get_ab_country() -> String:
	return UniKitManager.get_ab_country()


# ================= UniKit 转发：地区服务 =================
# 取地区服务(locsrv)下发的实验参数
func get_ab_locsrv(key: String, default_value: String = "") -> String:
	return UniKitManager.get_ab_locsrv_param(key, default_value)


# 取地区服务下发的全部参数
func get_all_ab_locsrv() -> Dictionary:
	return UniKitManager.get_all_ab_locsrv_params()


# 异步拉取地区服务参数，结果通过 locsrv_fetched 信号回来
func fetch_ab_locsrv() -> void:
	UniKitManager.fetch_remote_ab_result()


# 上报某个地区服务参数的染色
func dye_ab_locsrv(key: String) -> void:
	UniKitManager.dye_ab_locsrv(key)


# 上报地区服务参数的自定义标签
func dye_ab_locsrv_tag(tag: String) -> void:
	UniKitManager.dye_ab_locsrv_tag(tag)


# 批量设置地区服务标签，参与后续上报
func set_ab_locsrv_all_tag(tags: Array[String]) -> void:
	UniKitManager.set_ab_locsrv_all_tag(tags)


# 取参与分流的用户信息（上报用）
func get_ab_user_info() -> Dictionary:
	return UniKitManager.get_ab_user_info()


# 强制指定 group id（调试/复现线上分组用）
func set_ab_group_id(group_id: String) -> void:
	UniKitManager.set_ab_group_id(group_id)


# 强制指定国家/地区（调试/复现线上分组用）
func set_ab_country(country: String) -> void:
	UniKitManager.set_ab_country(country)


# ================= 状态查询与配置查找 =================
# A/B 是否已初始化完成
func is_ab_init_done() -> bool:
	return _is_init_done


# 地区服务参数是否已成功拉到
func is_ab_locsrv_fetched() -> bool:
	return _is_locsrv_fetched


# 取全部配置实例（作弊面板遍历用），顺序为字典遍历序
func get_all_configs() -> Array[AbConfigBase]:
	var out: Array[AbConfigBase] = []
	for cfg: AbConfigBase in _configs_by_key.values():
		out.append(cfg)
	return out


# 按 key 找配置实例，找不到返回 null
func find_config(key: String) -> AbConfigBase:
	return _configs_by_key.get(key, null) as AbConfigBase


# ================= 按时机批量染色 =================
# 刷新 app_start 时机的配置（由 _finalize_app_start_dye 调用）
func dye_at_app_start() -> void:
	_dye_at_timing(TIMING_APP_START)


# 刷新每局开局时机的配置（普通关与每日挑战开局都调）
func dye_at_game_start() -> void:
	_dye_at_timing(TIMING_GAME_START)


# 刷新普通模式开局时机的配置（仅在普通模式调）
func dye_at_game_start_normal() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL)


# 刷新第 11 关起生效的配置（GamePage 判关卡 >= 11 后调）
func dye_at_game_start_normal_11() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_11)


# 刷新第 21 关起生效的配置（GamePage 判关卡 >= 21 后调）
func dye_at_game_start_normal_21() -> void:
	_dye_at_timing(TIMING_GAME_START_NORMAL_21)


# 刷新本局失败结算时机的配置
func dye_at_game_fail_end() -> void:
	_dye_at_timing(TIMING_GAME_END)


# 刷新每日挑战开局时机的配置
func dye_at_game_start_dc() -> void:
	_dye_at_timing(TIMING_GAME_START_DC)


# 刷新使用提示时机的配置
func dye_at_hint_use() -> void:
	_dye_at_timing(TIMING_HINT_USE)


# 刷新挂机 270 秒时机的配置（由 ScreenManager 空闲超时调用）
func dye_at_no_action_270() -> void:
	_dye_at_timing(TIMING_NO_ACTION_270)


# 遍历全部配置，把 timing 匹配的重新取值；reload_value 会写 SDK 染色标记
func _dye_at_timing(t: String) -> void:
	for cfg: AbConfigBase in _configs_by_key.values():
		if cfg.timing == t:
			cfg.reload_value()
