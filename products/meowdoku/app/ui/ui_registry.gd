## 界面场景注册表：把页面名字映射到资源路径，并按当前配置选择结算页。
class_name UIRegistry
extends RefCounted

const PAGES := {
	UiName.SPLASH: "res://products/meowdoku/app/features/splash/ui/splash_page.tscn",
	UiName.HOME: "res://products/meowdoku/app/features/home/ui/home_page.tscn",
	UiName.HOME_COMPANION_GUIDE: "res://products/meowdoku/app/features/home/ui/home_companion_guide_page.tscn",
	UiName.HOME_COMPANION_REWARD: "res://products/meowdoku/app/features/home/ui/home_companion_reward_page.tscn",
	UiName.GAME: "res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn",
	UiName.BANK: "res://products/meowdoku/gameplay/presentation/bank/ui/bank_page.tscn",
	UiName.RECENT_LEVELS: "res://products/meowdoku/app/diagnostics/ui/recent_levels_page.tscn",
	UiName.TUTORIAL: "res://products/meowdoku/gameplay/presentation/tutorial/ui/tutorial_page.tscn",
	UiName.SETTING: "res://products/meowdoku/app/features/setting/ui/setting_page.tscn",
	UiName.LANGUAGE: "res://products/meowdoku/app/features/language/ui/language_page.tscn",
	UiName.DAILY_GAME: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_game_page.tscn",
	UiName.FEEDBACK: "res://products/meowdoku/app/features/feedback/ui/feedback_page.tscn",
	UiName.RATE_US_V2: "res://products/meowdoku/app/features/rate_us/ui/rate_us_page_v2.tscn",
	UiName.PRIVACY: "res://products/meowdoku/app/features/splash/ui/privacy_dialog.tscn",
	UiName.PRIVACY_V2: "res://products/meowdoku/app/features/splash/ui/privacy_dialog_v2.tscn",
	UiName.PRIVACY_V3: "res://products/meowdoku/app/features/splash/ui/privacy_dialog_v3.tscn",
	UiName.PRE_ATT_GUIDE: "res://products/meowdoku/app/features/splash/ui/pre_att_guide_page.tscn",
	UiName.PRE_ATT_GUIDE_V2: "res://products/meowdoku/app/features/splash/ui/pre_att_guide_page_v2.tscn",
	UiName.CONFIRM: "res://products/meowdoku/assets/prefab/confirm_dialog.tscn",
	UiName.WIN: "res://products/meowdoku/gameplay/presentation/result/ui/game_win_page.tscn",
	UiName.DAILY_WIN: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_win_page.tscn",
	UiName.FAIL: "res://products/meowdoku/gameplay/presentation/result/ui/game_fail_page.tscn",
	UiName.DAILY_FAIL: "res://products/meowdoku/gameplay/presentation/daily/ui/daily_fail_page.tscn",
	UiName.AD_REWARD_RESTORED: "res://products/meowdoku/gameplay/presentation/result/ui/ad_reward_restored_page.tscn",
	UiName.AWARD: "res://products/meowdoku/app/features/award/ui/award_page.tscn",
	UiName.RANK_FRAME_UNLOCK: "res://products/meowdoku/app/features/award/ui/award_page.tscn",
	UiName.REWARD_CLAIM_POPUP: "res://products/meowdoku/app/features/award/ui/reward_claim_popup.tscn",
	UiName.STREAK: "res://products/meowdoku/app/features/daily_streak/ui/streak_page.tscn",
	UiName.DAILY_STREAK_SUCCESS:
	"res://products/meowdoku/app/features/daily_streak/ui/daily_streak_success_page.tscn",
	UiName.STREAK_HOME: "res://products/meowdoku/app/features/daily_streak/ui/streak_home_page.tscn",
	UiName.STREAK_BACKFILL: "res://products/meowdoku/app/features/daily_streak/ui/streak_backfill_page.tscn",
	UiName.AB_SWITCH_POPUP: "res://products/meowdoku/app/features/ab_switch_popup/ui/ab_switch_popup.tscn",
	UiName.RANK_ACTIVITY_OPEN_POPUP:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_open_popup_page.tscn",
	UiName.RANK_ACTIVITY_HTP: "res://products/meowdoku/app/features/rank_activity/ui/rank_activity_htp_page.tscn",
	UiName.RANK_ACTIVITY_PAGE: "res://products/meowdoku/app/features/rank_activity/ui/rank_activity_page.tscn",
	UiName.RANK_ACTIVITY_CHANGE:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_change_page.tscn",
	UiName.RANK_ACTIVITY_CHANGE_V2:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_change_page_v2.tscn",
	UiName.PEEKABOO_CONFIRM: "res://products/meowdoku/app/features/peekaboo/ui/peekaboo_confirm_page.tscn",
	UiName.COMEBACK_WELCOME: "res://products/meowdoku/app/features/comeback/ui/comeback_welcome_page.tscn",
	UiName.RANK_ACTIVITY_PODIUM:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_podium_page.tscn",
	UiName.RANK_ACTIVITY_SOLO_PODIUM:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_solo_podium_page.tscn",
	UiName.RANK_ACTIVITY_OFFLINE:
	"res://products/meowdoku/app/features/rank_activity/ui/rank_activity_offline_page.tscn",
	UiName.PROFILE: "res://products/meowdoku/app/features/profile/ui/profile_page.tscn",
	UiName.SUBSCRIPTION: "res://products/meowdoku/app/features/purchase/ui/purchase_page.tscn",
	UiName.SUBSCRIPTION_SUCCESS: "res://products/meowdoku/app/features/purchase/ui/purchase_success_page.tscn",
	UiName.COMMON_LOADING: "res://products/meowdoku/assets/prefab/common_loading_page.tscn",
	UiName.ACCOUNT_RESULT: "res://products/meowdoku/app/features/account/ui/account_result_page.tscn",
	UiName.NO_CONNECTION: "res://products/meowdoku/app/features/account/ui/no_connection_page.tscn",
	UiName.DELETE_SUCCESS: "res://products/meowdoku/app/features/account/ui/delete_success_page.tscn",
	UiName.ACCOUNT_DELETED: "res://products/meowdoku/app/features/account/ui/account_deleted_page.tscn",
	UiName.SIGN_OUT_CONFIRM: "res://products/meowdoku/app/features/account/ui/sign_out_confirm_page.tscn",
	UiName.DELETE_ACCOUNT_CONFIRM:
	"res://products/meowdoku/app/features/account/ui/delete_account_confirm_page.tscn",
	UiName.LOGIN: "res://products/meowdoku/app/features/account/ui/login_page.tscn",
	UiName.PROGRESS_SELECT: "res://products/meowdoku/app/features/account/ui/progress_select_page.tscn",
	UiName.DC_COSTUME_UNLOCK: "res://products/meowdoku/gameplay/presentation/daily/ui/dc_costume_unlock_page.tscn",
	UiName.DC_COSTUME_TUTORIAL: "res://products/meowdoku/gameplay/presentation/daily/ui/dc_costume_tutorial_page.tscn",
	UiName.DC_REPLAY_CONFIRM: "res://products/meowdoku/gameplay/presentation/daily/ui/dc_replay_confirm_page.tscn",
}

## 调试页：Android 包不注册（不给玩家暴露调试入口）
const _DEBUG_PAGES := {
	UiName.DEBUG: "res://products/meowdoku/app/diagnostics/ui/debug_page.tscn",
	UiName.GENERATOR: "res://products/meowdoku/app/diagnostics/ui/generator_page.tscn",
}

const _DEV_PAGES := {
	UiName.PLAYTEST_SIMULATOR: "res://products/meowdoku/app/diagnostics/ui/playtest_simulator_page.tscn",
	UiName.AB_DEBUG: "res://products/meowdoku/app/diagnostics/ui/ab_debug_page.tscn",
	UiName.LEVEL_JSON_INPUT: "res://products/meowdoku/app/diagnostics/ui/level_json_input_page.tscn",
	UiName.DBG_RANK_BOARD: "res://products/meowdoku/app/diagnostics/ui/dbg_rank_board_page.tscn",
}

## 编辑器 mock 页：只有编辑器里能打开
const _EDITOR_PAGES := {
	UiName.MOCK_AD: "res://products/meowdoku/app/diagnostics/ui/mock_ad_page.tscn",
	UiName.MOCK_BANNER: "res://products/meowdoku/app/diagnostics/ui/mock_banner_page.tscn",
}


static func build_registry() -> Dictionary:
	var reg: Dictionary = PAGES.duplicate()
	if OS.is_debug_build() and not OS.has_feature("rel") and not OS.has_feature("android"):
		reg.merge(_DEBUG_PAGES)
	if OS.is_debug_build() and not OS.has_feature("rel"):
		reg.merge(_DEV_PAGES)
	if OS.is_debug_build() and not OS.has_feature("rel") and OS.has_feature("editor"):
		reg.merge(_EDITOR_PAGES)

	reg[UiName.WIN] = _resolve_win_path
	return reg


static func _resolve_win_path() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var experiments: Node = tree.root.get_node_or_null("ABTestManager") if tree != null else null
	if experiments != null and experiments.pass_page.is_g4():
		return "res://products/meowdoku/gameplay/presentation/result/ui/game_win_page_v2.tscn"
	return PAGES[UiName.WIN]
