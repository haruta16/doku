## 界面场景注册表：把页面名字映射到资源路径，并按当前配置选择结算页。
class_name UIRegistry
extends RefCounted

const PAGES := {
	UiName.SPLASH: "res://scripts/module/splash/ui/splash_page.tscn",
	UiName.HOME: "res://scripts/module/home/ui/home_page.tscn",
	UiName.HOME_COMPANION_GUIDE: "res://scripts/module/home/ui/home_companion_guide_page.tscn",
	UiName.HOME_COMPANION_REWARD: "res://scripts/module/home/ui/home_companion_reward_page.tscn",
	UiName.GAME: "res://scripts/module/game/ui/game_page.tscn",
	UiName.BANK: "res://scripts/module/bank/ui/bank_page.tscn",
	UiName.RECENT_LEVELS: "res://scripts/module/debug/ui/recent_levels_page.tscn",
	UiName.TUTORIAL: "res://scripts/module/tutorial/ui/tutorial_page.tscn",
	UiName.SETTING: "res://scripts/module/setting/ui/setting_page.tscn",
	UiName.LANGUAGE: "res://scripts/module/language/ui/language_page.tscn",
	UiName.DAILY_GAME: "res://scripts/module/daily/ui/daily_game_page.tscn",
	UiName.FEEDBACK: "res://scripts/module/feedback/ui/feedback_page.tscn",
	UiName.RATE_US_V2: "res://scripts/module/rate_us/ui/rate_us_page_v2.tscn",
	UiName.PRIVACY: "res://scripts/module/splash/ui/privacy_dialog.tscn",
	UiName.PRIVACY_V2: "res://scripts/module/splash/ui/privacy_dialog_v2.tscn",
	UiName.PRIVACY_V3: "res://scripts/module/splash/ui/privacy_dialog_v3.tscn",
	UiName.PRE_ATT_GUIDE: "res://scripts/module/splash/ui/pre_att_guide_page.tscn",
	UiName.PRE_ATT_GUIDE_V2: "res://scripts/module/splash/ui/pre_att_guide_page_v2.tscn",
	UiName.CONFIRM: "res://assets/prefab/confirm_dialog.tscn",
	UiName.WIN: "res://scripts/module/result/ui/game_win_page.tscn",
	UiName.DAILY_WIN: "res://scripts/module/daily/ui/daily_win_page.tscn",
	UiName.FAIL: "res://scripts/module/result/ui/game_fail_page.tscn",
	UiName.DAILY_FAIL: "res://scripts/module/daily/ui/daily_fail_page.tscn",
	UiName.AD_REWARD_RESTORED: "res://scripts/module/result/ui/ad_reward_restored_page.tscn",
	UiName.AWARD: "res://scripts/module/award/ui/award_page.tscn",
	UiName.RANK_FRAME_UNLOCK: "res://scripts/module/award/ui/award_page.tscn",
	UiName.REWARD_CLAIM_POPUP: "res://scripts/module/award/ui/reward_claim_popup.tscn",
	UiName.STREAK: "res://scripts/module/daily_streak/ui/streak_page.tscn",
	UiName.DAILY_STREAK_SUCCESS:
	"res://scripts/module/daily_streak/ui/daily_streak_success_page.tscn",
	UiName.STREAK_HOME: "res://scripts/module/daily_streak/ui/streak_home_page.tscn",
	UiName.STREAK_BACKFILL: "res://scripts/module/daily_streak/ui/streak_backfill_page.tscn",
	UiName.AB_SWITCH_POPUP: "res://scripts/module/ab_switch_popup/ui/ab_switch_popup.tscn",
	UiName.RANK_ACTIVITY_OPEN_POPUP:
	"res://scripts/module/rank_activity/ui/rank_activity_open_popup_page.tscn",
	UiName.RANK_ACTIVITY_HTP: "res://scripts/module/rank_activity/ui/rank_activity_htp_page.tscn",
	UiName.RANK_ACTIVITY_PAGE: "res://scripts/module/rank_activity/ui/rank_activity_page.tscn",
	UiName.RANK_ACTIVITY_CHANGE:
	"res://scripts/module/rank_activity/ui/rank_activity_change_page.tscn",
	UiName.RANK_ACTIVITY_CHANGE_V2:
	"res://scripts/module/rank_activity/ui/rank_activity_change_page_v2.tscn",
	UiName.PEEKABOO_CONFIRM: "res://scripts/module/peekaboo/ui/peekaboo_confirm_page.tscn",
	UiName.COMEBACK_WELCOME: "res://scripts/module/comeback/ui/comeback_welcome_page.tscn",
	UiName.RANK_ACTIVITY_PODIUM:
	"res://scripts/module/rank_activity/ui/rank_activity_podium_page.tscn",
	UiName.RANK_ACTIVITY_SOLO_PODIUM:
	"res://scripts/module/rank_activity/ui/rank_activity_solo_podium_page.tscn",
	UiName.RANK_ACTIVITY_OFFLINE:
	"res://scripts/module/rank_activity/ui/rank_activity_offline_page.tscn",
	UiName.PROFILE: "res://scripts/module/profile/ui/profile_page.tscn",
	UiName.SUBSCRIPTION: "res://scripts/module/purchase/ui/purchase_page.tscn",
	UiName.SUBSCRIPTION_SUCCESS: "res://scripts/module/purchase/ui/purchase_success_page.tscn",
	UiName.COMMON_LOADING: "res://assets/prefab/common_loading_page.tscn",
	UiName.ACCOUNT_RESULT: "res://scripts/module/account/ui/account_result_page.tscn",
	UiName.NO_CONNECTION: "res://scripts/module/account/ui/no_connection_page.tscn",
	UiName.DELETE_SUCCESS: "res://scripts/module/account/ui/delete_success_page.tscn",
	UiName.ACCOUNT_DELETED: "res://scripts/module/account/ui/account_deleted_page.tscn",
	UiName.SIGN_OUT_CONFIRM: "res://scripts/module/account/ui/sign_out_confirm_page.tscn",
	UiName.DELETE_ACCOUNT_CONFIRM:
	"res://scripts/module/account/ui/delete_account_confirm_page.tscn",
	UiName.LOGIN: "res://scripts/module/account/ui/login_page.tscn",
	UiName.PROGRESS_SELECT: "res://scripts/module/account/ui/progress_select_page.tscn",
	UiName.DC_COSTUME_UNLOCK: "res://scripts/module/daily/ui/dc_costume_unlock_page.tscn",
	UiName.DC_COSTUME_TUTORIAL: "res://scripts/module/daily/ui/dc_costume_tutorial_page.tscn",
	UiName.DC_REPLAY_CONFIRM: "res://scripts/module/daily/ui/dc_replay_confirm_page.tscn",
}

## 调试页：Android 包不注册（不给玩家暴露调试入口）
const _DEBUG_PAGES := {
	UiName.DEBUG: "res://scripts/module/debug/ui/debug_page.tscn",
	UiName.GENERATOR: "res://scripts/module/debug/ui/generator_page.tscn",
}

const _DEV_PAGES := {
	UiName.AB_DEBUG: "res://scripts/module/debug/ui/ab_debug_page.tscn",
	UiName.LEVEL_JSON_INPUT: "res://scripts/module/debug/ui/level_json_input_page.tscn",
	UiName.DBG_RANK_BOARD: "res://scripts/module/debug/ui/dbg_rank_board_page.tscn",
}

## 编辑器 mock 页：只有编辑器里能打开
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

	reg[UiName.WIN] = _resolve_win_path
	return reg


static func _resolve_win_path() -> String:
	if ABTestManager.pass_page.is_g4():
		return "res://scripts/module/result/ui/game_win_page_v2.tscn"
	return PAGES[UiName.WIN]
