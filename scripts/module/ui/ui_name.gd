# UI 名册：UiName.XXX 既是 UIManager 的路由 key，也是 UIRegistry 各张表的键
class_name UiName
extends RefCounted

# ================= 主流程页面（所有构建都注册） =================
const SPLASH: StringName = &"splash" # 启动闪屏页
const HOME: StringName = &"home" # 主页
const GAME: StringName = &"game" # 普通对局页
const BANK: StringName = &"bank" # 题库页
const TUTORIAL: StringName = &"tutorial" # 新手引导页
const SETTING: StringName = &"setting" # 设置页
const LANGUAGE: StringName = &"language" # 语言选择页
const HOW_TO_PLAY: StringName = &"how_to_play" # 玩法说明页
const HOW_TO_PLAY_PAGED: StringName = &"how_to_play_paged" # 玩法说明页（分页版）
const DAILY_GAME: StringName = &"daily_game" # 每日挑战对局页
const DAILY_AUTO_MARK_POPUP: StringName = &"daily_auto_mark_popup" # 每日挑战自动标记引导弹窗
const FEEDBACK: StringName = &"feedback" # 反馈页
const RATE_US: StringName = &"rate_us" # 评分引导页
const RATE_US_V2: StringName = &"rate_us_v2" # 评分引导页（AB 新版）
const PRIVACY: StringName = &"privacy" # 隐私政策对话框（启动时先弹）
const PRE_ATT_GUIDE: StringName = &"pre_att_guide" # ATT 授权前置说明页
const PRE_ATT_GUIDE_V2: StringName = &"pre_att_guide_v2" # ATT 授权前置说明页（AB 新版）
const CONFIRM: StringName = &"confirm" # 通用确认对话框
const WIN: StringName = &"win" # 普通模式胜利结算页
const DAILY_WIN: StringName = &"daily_win" # 每日挑战胜利结算页
const FAIL: StringName = &"fail" # 普通模式失败结算页
const DAILY_FAIL: StringName = &"daily_fail" # 每日挑战失败结算页
const AD_REWARD_RESTORED: StringName = &"ad_reward_restored" # 广告奖励补发提示页
const AWARD: StringName = &"award" # 奖励领取页
const STREAK: StringName = &"streak" # 连胜打卡页

# ================= 连胜 / AB 分流页 =================
const STREAK_SWITCH1: StringName = &"streak_switch1" # 连胜活动切换页 1
const STREAK_SWITCH2: StringName = &"streak_switch2" # 连胜活动切换页 2
const STREAK_SWITCH3: StringName = &"streak_switch3" # 连胜活动切换页 3
const AB_SWITCH_POPUP: StringName = &"ab_switch_popup" # AB 分流切换弹窗

# ================= 调试页（非 Android 包才注册） =================
const DEBUG: StringName = &"debug" # 调试主页面
const GENERATOR: StringName = &"generator" # 题目生成器页

# ================= 开发页（非 release 构建才注册） =================
const AB_DEBUG: StringName = &"ab_debug" # AB 分流调试页
const LEVEL_JSON_INPUT: StringName = &"level_json_input" # 手输 JSON 开局页
const PLAYTEST_SIMULATOR: StringName = &"playtest_simulator" # 玩家行为模拟页

# ================= 编辑器专用 mock 页 =================
const MOCK_AD: StringName = &"mock_ad" # 模拟广告页（仅编辑器）
const MOCK_BANNER: StringName = &"mock_banner" # 模拟 banner 页（仅编辑器）
