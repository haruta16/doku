## 界面名字表：为 UIManager 和场景注册表提供统一页面标识。
class_name UiName
extends RefCounted

# ================= 主流程页面（所有构建都注册） =================
const SPLASH: StringName = &"splash" # 启动闪屏页
const HOME: StringName = &"home" # 主页
const HOME_COMPANION_GUIDE: StringName = &"home_companion_guide"
const HOME_COMPANION_REWARD: StringName = &"home_companion_reward"
const GAME: StringName = &"game" # 普通对局页
const BANK: StringName = &"bank" # 题库页
const RECENT_LEVELS: StringName = &"recent_levels"
const TUTORIAL: StringName = &"tutorial" # 新手引导页
const SETTING: StringName = &"setting" # 设置页
const LANGUAGE: StringName = &"language" # 语言选择页
const DAILY_GAME: StringName = &"daily_game" # 每日挑战对局页
const FEEDBACK: StringName = &"feedback" # 反馈页
const RATE_US_V2: StringName = &"rate_us_v2" # 评分引导页（AB 新版）
const PRIVACY: StringName = &"privacy" # 隐私政策对话框（启动时先弹）
const PRIVACY_V2: StringName = &"privacy_v2"
const PRIVACY_V3: StringName = &"privacy_v3"
const PRE_ATT_GUIDE: StringName = &"pre_att_guide" # ATT 授权前置说明页
const PRE_ATT_GUIDE_V2: StringName = &"pre_att_guide_v2" # ATT 授权前置说明页（AB 新版）
const CONFIRM: StringName = &"confirm" # 通用确认对话框
const WIN: StringName = &"win" # 普通模式胜利结算页
const DAILY_WIN: StringName = &"daily_win" # 每日挑战胜利结算页
const FAIL: StringName = &"fail" # 普通模式失败结算页
const DAILY_FAIL: StringName = &"daily_fail" # 每日挑战失败结算页
const AD_REWARD_RESTORED: StringName = &"ad_reward_restored" # 广告奖励补发提示页
const AWARD: StringName = &"award" # 奖励领取页

const RANK_FRAME_UNLOCK: StringName = &"rank_frame_unlock"

const REWARD_CLAIM_POPUP: StringName = &"reward_claim_popup"
const STREAK: StringName = &"streak" # 连胜打卡页
const DAILY_STREAK_SUCCESS: StringName = &"daily_streak_success"
const STREAK_HOME: StringName = &"streak_home"

const STREAK_BACKFILL: StringName = &"streak_backfill"
const AB_SWITCH_POPUP: StringName = &"ab_switch_popup" # AB 分流切换弹窗
const RANK_ACTIVITY_OPEN_POPUP: StringName = &"rank_activity_open_popup"
const RANK_ACTIVITY_HTP: StringName = &"rank_activity_htp"
const RANK_ACTIVITY_PAGE: StringName = &"rank_activity_page"
const RANK_ACTIVITY_CHANGE: StringName = &"rank_activity_change"

const RANK_ACTIVITY_CHANGE_V2: StringName = &"rank_activity_change_v2"
const RANK_ACTIVITY_PODIUM: StringName = &"rank_activity_podium"
const RANK_ACTIVITY_SOLO_PODIUM: StringName = &"rank_activity_solo_podium"
const RANK_ACTIVITY_OFFLINE: StringName = &"rank_activity_offline"
const PROFILE: StringName = &"profile"
const SUBSCRIPTION: StringName = &"subscription"
const SUBSCRIPTION_SUCCESS: StringName = &"subscription_success"
const COMMON_LOADING: StringName = &"subscription_loading"

const ACCOUNT_RESULT: StringName = &"account_result"
const NO_CONNECTION: StringName = &"no_connection"
const DELETE_SUCCESS: StringName = &"delete_success"
const ACCOUNT_DELETED: StringName = &"account_deleted"
const SIGN_OUT_CONFIRM: StringName = &"sign_out_confirm"
const DELETE_ACCOUNT_CONFIRM: StringName = &"delete_account_confirm"
const LOGIN: StringName = &"login"
const PROGRESS_SELECT: StringName = &"progress_select"

const PEEKABOO_CONFIRM: StringName = &"peekaboo_confirm"

const COMEBACK_WELCOME: StringName = &"comeback_welcome"

const DC_COSTUME_UNLOCK: StringName = &"dc_costume_unlock"

const DC_COSTUME_TUTORIAL: StringName = &"dc_costume_tutorial"

const DC_REPLAY_CONFIRM: StringName = &"dc_replay_confirm"

# ================= 调试页（非 Android 包才注册） =================
const DEBUG: StringName = &"debug" # 调试主页面
const GENERATOR: StringName = &"generator" # 题目生成器页

# ================= 开发页（非 release 构建才注册） =================
const AB_DEBUG: StringName = &"ab_debug" # AB 分流调试页
const DBG_RANK_BOARD: StringName = &"dbg_rank_board"
const LEVEL_JSON_INPUT: StringName = &"level_json_input" # 手输 JSON 开局页

# ================= 编辑器专用 mock 页 =================
const MOCK_AD: StringName = &"mock_ad" # 模拟广告页（仅编辑器）
const MOCK_BANNER: StringName = &"mock_banner" # 模拟 banner 页（仅编辑器）
