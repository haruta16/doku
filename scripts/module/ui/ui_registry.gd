class_name UIRegistry
extends RefCounted

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

const _DEBUG_PAGES := {
	UiName.DEBUG: "res://scripts/module/debug/ui/debug_page.tscn",
	UiName.GENERATOR: "res://scripts/module/debug/ui/generator_page.tscn",
}

const _DEV_PAGES := {
	UiName.AB_DEBUG: "res://scripts/module/debug/ui/ab_debug_page.tscn",
	UiName.LEVEL_JSON_INPUT: "res://scripts/module/debug/ui/level_json_input_page.tscn",
	UiName.PLAYTEST_SIMULATOR: "res://scripts/module/debug/ui/playtest_simulator_page.tscn",
}

const _EDITOR_PAGES := {
	UiName.MOCK_AD: "res://scripts/module/debug/ui/mock_ad_page.tscn",
	UiName.MOCK_BANNER: "res://scripts/module/debug/ui/mock_banner_page.tscn",
}


static func build_registry() -> Dictionary:
	var reg: Dictionary = PAGES.duplicate()
	if not OS.has_feature("android"):
		reg.merge(_DEBUG_PAGES)
	if not OS.has_feature("rel"):
		reg.merge(_DEV_PAGES)
	if OS.has_feature("editor"):
		reg.merge(_EDITOR_PAGES)
	return reg
