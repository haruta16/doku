## 页面路由表：UiName → 场景路径；按平台/构建类型分四张表，由 build_registry 合并
class_name UIRegistry
extends RefCounted

## 正式页面：任何构建都会注册
const PAGES := {
	UiName.SPLASH: "res://products/meowdoku/app/features/splash/ui/splash_page.tscn",
	UiName.HOME: "res://products/meowdoku/app/features/home/ui/home_page.tscn",
	UiName.GAME: "res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn",
	UiName.BANK: "res://products/meowdoku/gameplay/presentation/bank/ui/bank_page.tscn",
	UiName.TUTORIAL: "res://products/meowdoku/gameplay/presentation/tutorial/ui/tutorial_page.tscn",
	UiName.SETTING: "res://products/meowdoku/app/features/setting/ui/setting_page.tscn",
	UiName.LANGUAGE: "res://products/meowdoku/app/features/language/ui/language_page.tscn",
	UiName.HOW_TO_PLAY: "res://products/meowdoku/gameplay/presentation/how_to_play/ui/how_to_play_page.tscn",
	UiName.HOW_TO_PLAY_PAGED: "res://products/meowdoku/gameplay/presentation/how_to_play/ui/how_to_play_paged_page.tscn",
	UiName.DAILY_GAME: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_game_page.tscn",
	UiName.DAILY_AUTO_MARK_POPUP: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_auto_mark_popup.tscn",
	UiName.FEEDBACK: "res://products/meowdoku/app/features/feedback/ui/feedback_page.tscn",
	UiName.RATE_US: "res://products/meowdoku/app/features/rate_us/ui/rate_us_page.tscn",
	UiName.RATE_US_V2: "res://products/meowdoku/app/features/rate_us/ui/rate_us_page_v2.tscn",
	UiName.PRIVACY: "res://products/meowdoku/app/features/splash/ui/privacy_dialog.tscn",
	UiName.PRE_ATT_GUIDE: "res://products/meowdoku/app/features/splash/ui/pre_att_guide_page.tscn",
	UiName.PRE_ATT_GUIDE_V2: "res://products/meowdoku/app/features/splash/ui/pre_att_guide_page_v2.tscn",
	UiName.CONFIRM: "res://products/meowdoku/assets/prefab/confirm_dialog.tscn",
	UiName.WIN: "res://products/meowdoku/gameplay/presentation/result/ui/game_win_page.tscn",
	UiName.DAILY_WIN: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_win_page.tscn",
	UiName.FAIL: "res://products/meowdoku/gameplay/presentation/result/ui/game_fail_page.tscn",
	UiName.DAILY_FAIL: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_fail_page.tscn",
	UiName.AD_REWARD_RESTORED: "res://products/meowdoku/gameplay/presentation/result/ui/ad_reward_restored_page.tscn",
	UiName.AWARD: "res://products/meowdoku/app/features/award/ui/award_page.tscn",
	UiName.STREAK: "res://products/meowdoku/app/features/daily_streak/ui/streak_page.tscn",
	UiName.STREAK_SWITCH1: "res://products/meowdoku/app/features/daily_streak/ui/daily_streak_switch_page1.tscn",
	UiName.STREAK_SWITCH2: "res://products/meowdoku/app/features/daily_streak/ui/daily_streak_switch_page2.tscn",
	UiName.STREAK_SWITCH3: "res://products/meowdoku/app/features/daily_streak/ui/daily_streak_switch_page3.tscn",
	UiName.AB_SWITCH_POPUP: "res://products/meowdoku/app/features/ab_switch_popup/ui/ab_switch_popup.tscn",
}

## 调试页：只在非 Android 的 debug 构建注册
const _DEBUG_PAGES := {
	UiName.DEBUG: "res://products/meowdoku/app/diagnostics/ui/debug_page.tscn",
	UiName.GENERATOR: "res://products/meowdoku/app/diagnostics/ui/generator_page.tscn",
}

## 开发页：仅 debug 构建注册，rel 标签可额外关闭
const _DEV_PAGES := {
	UiName.AB_DEBUG: "res://products/meowdoku/app/diagnostics/ui/ab_debug_page.tscn",
	UiName.LEVEL_JSON_INPUT: "res://products/meowdoku/app/diagnostics/ui/level_json_input_page.tscn",
	UiName.PLAYTEST_SIMULATOR: "res://products/meowdoku/app/diagnostics/ui/playtest_simulator_page.tscn",
}

## 编辑器 mock 页：只有编辑器里能打开
const _EDITOR_PAGES := {
	UiName.MOCK_AD: "res://products/meowdoku/app/diagnostics/ui/mock_ad_page.tscn",
	UiName.MOCK_BANNER: "res://products/meowdoku/app/diagnostics/ui/mock_banner_page.tscn",
}


## 合并四张表，得到本次运行可用的注册表（UIManager._ready 调用一次）
static func build_registry() -> Dictionary:
	var reg: Dictionary = PAGES.duplicate() # 先复制基础表，避免 merge 污染 const 本身
	if OS.is_debug_build() and not OS.has_feature("rel"):
		if not OS.has_feature("android"): # Android 真机不挂调试页
			reg.merge(_DEBUG_PAGES) # debug、generator 两个页
		reg.merge(_DEV_PAGES) # ab_debug、level_json_input、playtest_simulator
		if OS.has_feature("editor"): # 只在编辑器里
			reg.merge(_EDITOR_PAGES) # mock_ad、mock_banner
	return reg # 结果存进 UIManager._registry，show_ui 用它查场景路径
