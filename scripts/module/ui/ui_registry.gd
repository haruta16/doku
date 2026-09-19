# 页面路由表：UiName → 场景路径；按平台/构建类型分四张表，由 build_registry 合并
class_name UIRegistry
extends RefCounted

# 正式页面：任何构建都会注册
const PAGES := {
	UiName.SPLASH: "res://scripts/module/splash/ui/splash_page.tscn",
	UiName.HOME: "res://scripts/module/home/ui/home_page.tscn",
	UiName.GAME: "res://scripts/module/game/ui/game_page.tscn",
	UiName.BANK: "res://scripts/module/bank/ui/bank_page.tscn",
	UiName.TUTORIAL: "res://scripts/module/tutorial/ui/tutorial_page.tscn",
	UiName.SETTING: "res://scripts/module/setting/ui/setting_page.tscn",
	UiName.LANGUAGE: "res://scripts/module/language/ui/language_page.tscn",
	UiName.HOW_TO_PLAY: "res://scripts/module/how_to_play/ui/how_to_play_page.tscn",
	UiName.HOW_TO_PLAY_PAGED: "res://scripts/module/how_to_play/ui/how_to_play_paged_page.tscn",
	UiName.DAILY_GAME: "res://scripts/module/daily/ui/daily_game_page.tscn",
	UiName.DAILY_AUTO_MARK_POPUP: "res://scripts/module/daily/ui/daily_auto_mark_popup.tscn",
	UiName.FEEDBACK: "res://scripts/module/feedback/ui/feedback_page.tscn",
	UiName.RATE_US: "res://scripts/module/rate_us/ui/rate_us_page.tscn",
	UiName.RATE_US_V2: "res://scripts/module/rate_us/ui/rate_us_page_v2.tscn",
	UiName.PRIVACY: "res://scripts/module/splash/ui/privacy_dialog.tscn",
	UiName.PRE_ATT_GUIDE: "res://scripts/module/splash/ui/pre_att_guide_page.tscn",
	UiName.PRE_ATT_GUIDE_V2: "res://scripts/module/splash/ui/pre_att_guide_page_v2.tscn",
	UiName.CONFIRM: "res://assets/prefab/confirm_dialog.tscn",
	UiName.WIN: "res://scripts/module/result/ui/game_win_page.tscn",
	UiName.DAILY_WIN: "res://scripts/module/daily/ui/daily_win_page.tscn",
	UiName.FAIL: "res://scripts/module/result/ui/game_fail_page.tscn",
	UiName.DAILY_FAIL: "res://scripts/module/daily/ui/daily_fail_page.tscn",
	UiName.AD_REWARD_RESTORED: "res://scripts/module/result/ui/ad_reward_restored_page.tscn",
	UiName.AWARD: "res://scripts/module/award/ui/award_page.tscn",
	UiName.STREAK: "res://scripts/module/daily_streak/ui/streak_page.tscn",
	UiName.STREAK_SWITCH1: "res://scripts/module/daily_streak/ui/daily_streak_switch_page1.tscn",
	UiName.STREAK_SWITCH2: "res://scripts/module/daily_streak/ui/daily_streak_switch_page2.tscn",
	UiName.STREAK_SWITCH3: "res://scripts/module/daily_streak/ui/daily_streak_switch_page3.tscn",
	UiName.AB_SWITCH_POPUP: "res://scripts/module/ab_switch_popup/ui/ab_switch_popup.tscn",
}

# 调试页：Android 包不注册（不给玩家暴露调试入口）
const _DEBUG_PAGES := {
	UiName.DEBUG: "res://scripts/module/debug/ui/debug_page.tscn",
	UiName.GENERATOR: "res://scripts/module/debug/ui/generator_page.tscn",
}

# 开发页：非 release 构建（OS.has_feature("rel") 为假）才注册
const _DEV_PAGES := {
	UiName.AB_DEBUG: "res://scripts/module/debug/ui/ab_debug_page.tscn",
	UiName.LEVEL_JSON_INPUT: "res://scripts/module/debug/ui/level_json_input_page.tscn",
	UiName.PLAYTEST_SIMULATOR: "res://scripts/module/debug/ui/playtest_simulator_page.tscn",
}

# 编辑器 mock 页：只有编辑器里能打开
const _EDITOR_PAGES := {
	UiName.MOCK_AD: "res://scripts/module/debug/ui/mock_ad_page.tscn",
	UiName.MOCK_BANNER: "res://scripts/module/debug/ui/mock_banner_page.tscn",
}


# 合并四张表，得到本次运行可用的注册表（UIManager._ready 调用一次）
static func build_registry() -> Dictionary:
	var reg: Dictionary = PAGES.duplicate() # 先复制基础表，避免 merge 污染 const 本身
	if not OS.has_feature("android"): # Android 真机不挂调试页
		reg.merge(_DEBUG_PAGES) # debug、generator 两个页
	if not OS.has_feature("rel"): # 非 release 构建
		reg.merge(_DEV_PAGES) # ab_debug、level_json_input、playtest_simulator
	if OS.has_feature("editor"): # 只在编辑器里
		reg.merge(_EDITOR_PAGES) # mock_ad、mock_banner
	return reg # 结果存进 UIManager._registry，show_ui 用它查场景路径
