## 调试命令执行器：把面板输入分派到存档、玩法、活动和平台服务的调试入口。
extends Node

const RemoteConsoleAccess: GDScript = preload("res://scripts/module/cheat/remote_console_access.gd")

const DebugOverrideStore: GDScript = preload(
	"res://scripts/module/abtest/debug_ab_override_store.gd"
)

const HomeCompanionSystem: GDScript = preload(
	"res://scripts/module/home/core/home_companion_system.gd"
)

const HomeCompanionService: GDScript = preload(
	"res://scripts/module/home/home_companion_service.gd"
)

var _command_defs: Array = []
var _companion_reset_busy: bool = false

var _tabs: Array[CheatTabBase] = []

var _clickdbg_enabled: bool = false

var _safe_area_overlay: CanvasLayer = null

var _streak_history_session: RefCounted = null


## 发布特性构建直接跳过；开发运行清空旧注册后建立命令表、实验参数和页签。
func _ready() -> void:
	if OS.has_feature("rel"):
		return

	CheatBus.clear_commands()
	CheatBus.clear_tabs()
	CheatBus.clear_ab_params()
	_register_ab_params()
	_command_defs = [
		{
			"name": "re_login",
			"label": "重新登录看splash(空=当日首次/keep=同日后续)",
			"default_args": "",
			"handler": _cmd_re_login
		},
		{
			"name": "returned_user",
			"label": "模拟回流并立即重进当前主线关",
			"handler": _cmd_returned_user,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "datasync",
			"label": "数据同步开关(on/off,默认toggle,跨session持久)",
			"default_args": "toggle",
			"handler": _cmd_datasync
		},
		{
			"name": "rec",
			"label": "拉服务端推荐题(契约探针,参数:历史条数 [ab_group] [本地队列条数,0=不带该字段])",
			"default_args": "15",
			"handler": _cmd_rec
		},
		{"name": "rec_status", "label": "推荐队列状态(剩余/历史条数/预取中)", "handler": _cmd_rec_status},
		{"name": "rec_prefetch", "label": "强制触发推荐预取", "handler": _cmd_rec_prefetch},
		{"name": "rec_clear", "label": "清空推荐队列", "handler": _cmd_rec_clear},
		{"name": "reset_tutorial", "label": "重置引导", "handler": _cmd_reset_tutorial},
		{"name": "clear", "label": "清空全部存档与AB并退出", "handler": _cmd_clear},
		{
			"name": "today_stats",
			"label": "设今日战绩(猫数 叉数,测pass_text组6/7/8里程碑)",
			"default_args": "48 490",
			"handler": _cmd_today_stats
		},
		{"name": "savetest", "label": "存档容错自检(8 case)", "handler": _cmd_savetest},
		{"name": "speed", "label": "设置游戏速度倍率", "handler": _cmd_speed, "default_args": "1.0"},
		{"name": "kill", "label": "杀死进程", "handler": _cmd_kill},
		{"name": "vibrate", "label": "测试震动", "default_args": "2", "handler": _cmd_vibrate},
		{"name": "feedback", "label": "打开反馈页", "handler": _cmd_feedback},
		{"name": "privacy_v2", "label": "打开隐私弹窗v2", "handler": _cmd_privacy_v2},
		{"name": "privacy_v3", "label": "打开隐私弹窗v3", "handler": _cmd_privacy_v3},
		{
			"name": "streak_push",
			"label": "断签召回push重算注册(打印baseline/条件判定)",
			"handler": _cmd_streak_push
		},
		{"name": "show_cmp", "label": "强制显示CMP行并开设置", "handler": _cmd_show_cmp},
		{"name": "win", "label": "立即胜利", "tab": CheatCommand.Tab.GAMEPLAY},
		{"name": "draft", "label": "进入草稿模式(不扣道具)", "tab": CheatCommand.Tab.GAMEPLAY},
		{"name": "draft_win", "label": "草稿全填假设猫+Apply", "tab": CheatCommand.Tab.GAMEPLAY},
		{
			"name": "score",
			"label": "设置当前分数(测结算)",
			"default_args": "8888",
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "time",
			"label": "设置当前时间秒(测结算)",
			"default_args": "90",
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "level",
			"label": "跳关",
			"default_args": "1",
			"handler": _cmd_level,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "pre_cat",
			"label": "强制预放猫(可选 on/off;省略=开并重进本关)",
			"default_args": "",
			"handler": _cmd_pre_cat,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{"name": "lives", "label": "设置生命", "default_args": "3", "tab": CheatCommand.Tab.GAMEPLAY},
		{
			"name": "elo_debug",
			"label": "ELO 调试面板(R3/R4/R5,0关1开)",
			"default_args": "1",
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "thumb_delay",
			"label": "thumb_up 遗漏叉延迟(默认10;off恢复)",
			"default_args": "1",
			"handler": _cmd_thumb_delay,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "locate",
			"label": "增加定位",
			"default_args": "3",
			"handler": _cmd_locate,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "hint",
			"label": "增加提示",
			"default_args": "3",
			"handler": _cmd_hint,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "mouse",
			"label": "增加老鼠",
			"default_args": "3",
			"handler": _cmd_mouse,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "cat_cans",
			"label": "主页猫:增加罐头库存(上限999)",
			"default_args": "10",
			"handler": _cmd_cat_cans
		},
		{
			"name": "cat_satiety",
			"label": "主页猫:设置组4饱食度(0~100,需已初始化)",
			"default_args": "60",
			"handler": _cmd_cat_satiety
		},
		{
			"name": "cat_satiety_get",
			"label": "主页猫:打印当前实时饱食度(只读)",
			"handler": _cmd_cat_satiety_get,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "cat_decay",
			"label": "主页猫:饱腹消耗倍率(空=查看,0=暂停,1440=每分钟40点,reset=正常)",
			"handler": _cmd_cat_decay,
			"tab": CheatCommand.Tab.ACTIVITY,
			"editor_only": true
		},
		{
			"name": "cat_event_date",
			"label": "主页猫:覆盖万圣活动日期(YYYY-MM-DD,空=查看,reset=真实日期;活动期10-25~11-07)",
			"default_args": "2026-10-27",
			"handler": _cmd_cat_event_date,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "cat_candy",
			"label": "主页猫:增加糖果累计进度(至最后奖励档)",
			"default_args": "20",
			"handler": _cmd_cat_candy
		},
		{
			"name": "cat_reset",
			"label": "主页猫:重置陪伴数据及全部教学(保留已发奖励)",
			"handler": _cmd_cat_reset,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "draft_add",
			"label": "增加草稿",
			"default_args": "3",
			"handler": _cmd_draft_add,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "misplace_repro",
			"label": "复现 misplace_react=2 期间 locate 猫头 CatIconAppear 被打断(delay 秒后触发错位双击,默认0.2s)",
			"default_args": "0.2",
			"handler": _cmd_misplace_repro,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "misplace_stress",
			"label":
			"压测 misplace_react=2 + locate 交替触发(count 轮,默认5轮,每轮 locate→短延迟→双击错猜→短延迟→locate)",
			"default_args": "5",
			"handler": _cmd_misplace_stress,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "gold_flash_bug",
			"label": "回归验证:on 时跳过 CatGlow 粒子池清理→回退到修复前 bug 行为(on/off/toggle;默认toggle)",
			"default_args": "toggle",
			"handler": _cmd_gold_flash_bug,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "time_scale",
			"label": "游戏时间流速倍率(0.25=1/4x慢放, 1.0=正常, 2.0=2x快放;默认0.25)",
			"default_args": "0.25",
			"handler": _cmd_time_scale
		},
		{
			"name": "pwr",
			"label":
			"功耗实验:max_fps lowproc(0/1) [sleep_usec];ref=冻结画面参照/unref=恢复;trace=读缓存/帧率/触摸帧级轨迹;taparm k x y=下次缓存接管后第k帧注入单击",
			"default_args": "60 0",
			"handler": _cmd_pwr
		},
		{
			"name": "pwr_saver",
			"label": "局内省电(空闲30fps+透明层剔除) on/off",
			"default_args": "off",
			"handler": _cmd_pwr_saver
		},
		{
			"name": "pwr_probe",
			"label": "功耗探针:打印此刻在每帧推进的东西(动画/粒子/Spine/tween/_process)到日志",
			"handler": _cmd_pwr_probe
		},
		{
			"name": "free",
			"label": "道具免费态(hint/locate/all/off)",
			"default_args": "all",
			"handler": _cmd_free,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{"name": "daily", "label": "每日挑战", "handler": _cmd_daily, "tab": CheatCommand.Tab.GAMEPLAY},
		{
			"name": "direct_open",
			"label": "unfinished_game_open: 强触发直进(需 home 在最上,跳过全部 gate)",
			"handler": _cmd_direct_open,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "daily_top",
			"label": "设置每日Top%",
			"default_args": "4.1",
			"handler": _cmd_daily_top,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "daily_clear",
			"label": "清当日每日挑战完成记录(回未完成态;不开局、不动日期override)",
			"handler": _cmd_daily_clear,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "daily_first_win_reset",
			"label": "重测每日首胜(仅清本实验日期)",
			"handler": _cmd_daily_first_win_reset,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_dump",
			"label": "外观:打印分组/当日外观/持有剩余/解锁日/红点/教学/DC入口态",
			"handler": _cmd_costume_dump,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_unlock",
			"label": "外观:强制解锁当日外观(等价三命通关DC)",
			"handler": _cmd_costume_unlock,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_unlock_all",
			"label": "外观:解锁全部外观(各给24h体验,不烧当日解锁名额)",
			"handler": _cmd_costume_unlock_all,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_clear",
			"label": "外观:清全部外观记录(体验/解锁日/装备/红点)",
			"handler": _cmd_costume_clear,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_expire",
			"label": "外观:全部体验立即到期(验切回预设造型)",
			"handler": _cmd_costume_expire,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_day",
			"label": "外观:指定当日外观id(空/off=回真实日期;同时切DC题面那天)",
			"default_args": "2",
			"handler": _cmd_costume_day,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_equip",
			"label": "外观:装备指定id(未持有会拒绝,先 costume_day + costume_unlock)",
			"default_args": "2",
			"handler": _cmd_costume_equip,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_tutorial_reset",
			"label": "外观:重置三命教学标志(生涯一次→可重看)",
			"handler": _cmd_costume_tutorial_reset,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "costume_geom",
			"label": "外观:量测猫头几何(墨迹矩形/视觉中心/裁剪)+渲染性能;batch_off/batch_on 做合批A/B",
			"default_args": "",
			"handler": _cmd_costume_geom,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "spine_probe",
			"label": "猫头开销诊断:无参=统计;off_hidden/off_all=停骨架每帧更新;on=恢复",
			"default_args": "",
			"handler": _cmd_spine_probe,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "gf_fx",
			"label": "立即胜利+下一关变一命关(连点反复看通关动效;局外只置下一关)",
			"handler": _cmd_gf_fx_outside,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "gf_pending",
			"label": "下一关立刻出插入式一命关",
			"handler": _cmd_gf_pending,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "gf_state",
			"label": "打印一命关全部状态",
			"handler": _cmd_gf_state,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "gf_reset",
			"label": "清一命关生涯履历(教学+首个7×7+题库游标)",
			"handler": _cmd_gf_reset,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "cc_pending",
			"label": "下一关立刻出颜色挑战(自动补足解锁门槛)",
			"handler": _cmd_cc_pending,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "cc_state",
			"label": "打印颜色挑战全部状态",
			"handler": _cmd_cc_state,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "cc_reset",
			"label": "清颜色挑战生涯履历(首个7×7+题库游标+防打扰)",
			"handler": _cmd_cc_reset,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "robotsim",
			"label": "机器人模拟器(24h 时间轴 + 五组对比)",
			"handler": _cmd_robot_sim,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak",
			"label": "打卡主页",
			"handler": _cmd_streak_open,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_first",
			"label": "首日待打卡",
			"handler": _cmd_streak_first,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_months",
			"label": "跨月多段历史",
			"handler": _cmd_streak_months,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_history",
			"label": "指定日期/历史造数",
			"default_args": "help",
			"handler": _cmd_streak_history,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_clear",
			"label": "清今日打卡",
			"handler": _cmd_streak_clear,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_skip",
			"label": "跨天",
			"handler": _cmd_streak_skip,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_6",
			"label": "6天已打+今未打",
			"handler": _cmd_streak_6,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_set",
			"label": "打卡到第N天(参数:N)",
			"default_args": "3",
			"handler": _cmd_streak_set,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_broken",
			"label": "造断签(断了几天,断前几天)",
			"default_args": "1 5",
			"handler": _cmd_streak_broken,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_broken_6",
			"label": "6天已打+断签1天(测补签跨宝箱)",
			"handler": _cmd_streak_broken_6,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_icon",
			"label": "打卡icon切组(0/4)",
			"default_args": "4",
			"handler": _cmd_streak_icon,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "streak_at",
			"label": "指定时刻打卡+开结算页(hh:mm [鼓励条组])",
			"default_args": "5:30",
			"handler": _cmd_streak_at,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_open",
			"label": "强开排名活动(触发开启弹窗)",
			"handler": _cmd_rank_open,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_like_reset",
			"label": "重置点赞数据",
			"handler": _cmd_rank_like_reset,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_gift",
			"label": "排名领奖(名次1/2/3,默认1)",
			"default_args": "1",
			"handler": _cmd_rank_gift,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_rise",
			"label": "排名上浮(from to [total])",
			"default_args": "5 1 5",
			"handler": _cmd_rank_rise,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_score",
			"label": "设置排名得分",
			"default_args": "100",
			"handler": _cmd_rank_score,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_streak",
			"label": "设排名连胜场数(n [refreeze=1 重冻本期规则])",
			"default_args": "3",
			"handler": _cmd_rank_streak,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_set_rank",
			"label": "设指定名次+1s结束(n)",
			"default_args": "3",
			"handler": _cmd_rank_set_rank,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_spread",
			"label": "岔开机器人分数(gap [top])",
			"default_args": "3",
			"handler": _cmd_rank_spread,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_win_to",
			"label": "局内:通关后升到第N名(to [from])",
			"default_args": "2 5",
			"handler": _cmd_rank_win_to,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_end10",
			"label": "排名倒计时N秒后结束(默认10)",
			"default_args": "10",
			"handler": _cmd_rank_end10,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_solo_podium",
			"label": "预览4-6名单人领奖台(名次4/5/6,默认4)",
			"default_args": "4",
			"handler": _cmd_rank_solo_podium,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_lock_frame",
			"label": "第一名框设为未获得",
			"handler": _cmd_rank_lock_frame,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_frame_wins",
			"label": "设第一名框统计次数(n)",
			"default_args": "6",
			"handler": _cmd_rank_frame_wins,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_frame_form",
			"label": "强制装备形态(f,跳过解锁校验)",
			"default_args": "2",
			"handler": _cmd_rank_frame_form,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_frame_reset_backfill",
			"label": "清首登补发标记(可复测)",
			"handler": _cmd_rank_frame_reset_backfill,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "rank_frame_dump",
			"label": "打印第一名框档位/角标概率表/机器人形态",
			"handler": _cmd_rank_frame_dump,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "comeback_show",
			"label": "回流欢迎表演:立即预览(不判分组/天数)",
			"handler": _cmd_comeback_show,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "comeback_returnee",
			"label": "回流欢迎表演:模拟离开N天+下次冷启按组(天数 组)",
			"default_args": "4 1",
			"handler": _cmd_comeback_returnee,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo",
			"label": "躲猫猫:强制出猫(可选 道具0-4 坐标0-4)",
			"default_args": "",
			"handler": _cmd_peekaboo,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_reset",
			"label": "躲猫猫:重置当日领奖额度(可重领)",
			"handler": _cmd_peekaboo_reset,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_group",
			"label": "躲猫猫:切组(0对照/1送1鱼干/2弹窗)",
			"default_args": "1",
			"handler": _cmd_peekaboo_group,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_dump",
			"label": "躲猫猫:打印组/落盘状态/发奖判定/落点",
			"handler": _cmd_peekaboo_dump,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_pos",
			"label": "躲猫猫:挪到指定落点(0-4,保留当前道具)",
			"default_args": "0",
			"handler": _cmd_peekaboo_pos,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_next",
			"label": "躲猫猫:下一个落点(连点遍历5个位置)",
			"handler": _cmd_peekaboo_next,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "peekaboo_boxes",
			"label": "躲猫猫:一次画出5个落点框(再点一次清掉)",
			"handler": _cmd_peekaboo_boxes,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "mock_offline",
			"label": "模拟无网(on/off/toggle;默认toggle)",
			"default_args": "toggle",
			"handler": _cmd_mock_offline,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "mock_no_fill",
			"label": "模拟激励视频无填充(on/off/toggle;默认toggle)",
			"default_args": "toggle",
			"handler": _cmd_mock_no_fill
		},
		{
			"name": "nonet",
			"label": "无网标识场景(断网/断网有广告/有网/有网无广告 [组号])",
			"default_args": "断网 1",
			"handler": _cmd_nonet
		},
		{
			"name": "robot_dump",
			"label": "打印机器人列表数据(arr/陪伴/上限/数量/步长)",
			"handler": _cmd_robot_dump,
			"tab": CheatCommand.Tab.ACTIVITY
		},
		{
			"name": "native_util_dump",
			"label": "打印 NativeUtil / UniKitManager 6 接口返回值对比",
			"handler": _cmd_native_util_dump
		},
		{
			"name": "usertag",
			"label": "打印 UniKit UserTag inner 标签(验 device_ram/brand)",
			"handler": _cmd_usertag
		},
		{
			"name": "usertag_ms",
			"label": "写 localTag media_source(参数:值;空=回读验证)",
			"default_args": "",
			"handler": _cmd_usertag_ms
		},
		{
			"name": "usertag_debug",
			"label": "写 usertag_debug.json 改 inner media_source(值/off=删,需重启,仅dev包)",
			"default_args": "",
			"handler": _cmd_usertag_debug
		},
		{"name": "bank", "label": "打开题库", "handler": _cmd_bank},
		{
			"name": "latest",
			"label": "查看最近关卡缩略图+同构检测(参数:关数,默认30)",
			"default_args": "30",
			"handler": _cmd_latest
		},
		{
			"name": "fastjump",
			"label": "连续通关N局(真实取题+推进难度,默认30,配合latest测同构)",
			"default_args": "30",
			"handler": _cmd_fastjump
		},
		{"name": "level_json", "label": "json开局", "handler": _cmd_level_json},
		{
			"name": "dumpjson",
			"label": "导出题目JSON(0=局面 1=初始)",
			"default_args": "1",
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "bank_preview",
			"label": "预览题库关卡+变换",
			"default_args": "1 0 reg_10_3",
			"handler": _cmd_bank_preview
		},
		{
			"name": "size12",
			"label": "12×12 试玩(rank 默认3, idx 默认1)",
			"default_args": "3 1",
			"handler": _cmd_size12,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{"name": "reset_rate_us", "label": "重置评分弹窗", "handler": _cmd_reset_rate_us},
		{"name": "ad_debug", "label": "打开广告调试器", "handler": _cmd_ad_debug},
		{"name": "hide_ui", "label": "隐藏UI", "handler": _cmd_hide_ui},
		{"name": "ui_stack", "label": "打印UI栈+显隐状态(定位卡死/僵尸/孤儿)", "handler": _cmd_ui_stack},
		{
			"name": "blocker_repro",
			"label": "复现 blocker 出树后收触摸抬起→is_inside_tree 断言(按下与抬起间隔秒,默认0.3)",
			"default_args": "0.3",
			"handler": _cmd_blocker_repro
		},
		{
			"name": "mock_ad_fail",
			"label": "模拟广告加载失败回调(iOS,验证MVAdError桥接)",
			"handler": _cmd_mock_ad_fail
		},
		{"name": "inter", "label": "弹插屏", "handler": _cmd_inter},
		{"name": "reward", "label": "弹激励视频", "handler": _cmd_reward},
		{
			"name": "mock_reward_miss",
			"label": "模拟视频奖励补发(0正常发奖/1漏奖补发)",
			"default_args": "1",
			"handler": _cmd_mock_reward_miss
		},
		{
			"name": "push_restore",
			"label": "推假待补发,回home触发弹窗(空=仅hint / both=hint+locate)",
			"default_args": "",
			"handler": _cmd_push_restore
		},
		{
			"name": "inter_prob_count",
			"label": "设置本 session 激励视频次数(inter_prob 激励闸)",
			"default_args": "3",
			"handler": _cmd_inter_prob_count
		},
		{
			"name": "inter_prob_games",
			"label": "设置本 session 已开局数(inter_prob 开局数闸,组4/5/6)",
			"default_args": "51",
			"handler": _cmd_inter_prob_games
		},
		{"name": "add_session", "label": "增加Session", "handler": _cmd_add_session},
		{"name": "ab", "label": "设置AB参数", "default_args": "region_color 0", "handler": _cmd_ab},
		{
			"name": "ab_persist",
			"label": "AB参数存档开关(on/off/toggle)",
			"default_args": "toggle",
			"handler": _cmd_ab_persist
		},
		{"name": "ab_debug", "label": "ABTest分流调试", "handler": _cmd_ab_debug},
		{
			"name": "font_zh_old_save",
			"label": "恢复中文字体旧存档并退出(zh=2)",
			"handler": _cmd_font_zh_old_save
		},
		{
			"name": "switch_popup",
			"label": "直接开AB切组弹窗(both双道具/hint/locate/none,验prop_position顺序)",
			"default_args": "both",
			"handler": _cmd_switch_popup
		},
		{"name": "ab_tag", "label": "打印染色", "handler": _cmd_ab_tag},
		{
			"name": "clickdbg",
			"label": "打印点击命中节点(on/off/toggle)",
			"default_args": "toggle",
			"handler": _cmd_clickdbg
		},
		{"name": "dc", "label": "悬浮球下方常驻显示当前DC(on/off)", "default_args": "on", "handler": _cmd_dc},
		{"name": "safe_area", "label": "显示安全区(刘海/手势区可视化)", "handler": _cmd_safe_area},
		{
			"name": "adapt_holders",
			"label": "打印 VBox 各 AdaptHolder 高度(设置值/实际物理px)",
			"handler": _cmd_adapt_holders
		},
		{
			"name": "resort_fail",
			"label": "强制刷新失败页按钮 VBox 布局(验证是否容器未更新)",
			"handler": _cmd_resort_fail
		},
		{
			"name": "swipe_viz",
			"label": "保护区可视化(锁定行/列滑动范围)",
			"handler": _cmd_swipe_viz,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "swipe_tc_tol",
			"label": "v4 目标色格容差 override (组10/11 目标颜色保护)",
			"handler": _cmd_swipe_tc_tol,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "swipe_logic_viz",
			"label": "swipe_logic 扩展环可视化(红框)",
			"handler": _cmd_swipe_logic_viz,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "swipe_logic_slop",
			"label": "swipe_logic 扩展环占格宽比例 override (0-1,0=清除)",
			"default_args": "0.2",
			"handler": _cmd_swipe_logic_slop,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "touch_viz",
			"label": "多指触点可视化(淡紫圆,直径=2 格边长)",
			"handler": _cmd_touch_viz,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "highspeed_set",
			"label": "doubletap_protect 高频参数一次性设置(时间窗口 高频操作窗口 高频操作CD 禁操作CD,单位ms;空=打印,reset=恢复默认)",
			"default_args": "300 650 660 250",
			"handler": _cmd_highspeed_set,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "dt_freq_state",
			"label": "doubletap_protect 高频操作状态(打印;on=强制进入方便测组5/6/7,off=清空)",
			"handler": _cmd_dt_freq_state,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "cat_dim_alpha",
			"label": "已找到猫色区淡化 alpha override(空=打印,0~1,reset=回分组值)",
			"handler": _cmd_cat_dim_alpha,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{
			"name": "reset_first_easy",
			"label": "重置首局降档",
			"handler": _cmd_reset_first_easy,
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{"name": "buy", "label": "发起订阅购买(空=首个/序号/商品id)", "default_args": "0", "handler": _cmd_buy},
		{"name": "restore", "label": "恢复购买(商店已购订阅)", "handler": _cmd_restore},
		{
			"name": "sub_loading",
			"label": "预览恢复购买loading(秒数,默认6)",
			"default_args": "6",
			"handler": _cmd_sub_loading
		},
		{"name": "vip", "label": "打印VIP状态(是否VIP/到期/商品数)", "handler": _cmd_vip},
		{"name": "vip_refresh", "label": "查商店刷新VIP", "handler": _cmd_vip_refresh},
		{"name": "vip_gift", "label": "领取VIP每日赠送(1提示+1定位)", "handler": _cmd_vip_gift},
		{
			"name": "vip_clear",
			"label": "清本地购买记录(加 all 连模拟商店一起清=真退订)",
			"default_args": "",
			"handler": _cmd_vip_clear
		},
		{"name": "vip_inter", "label": "备好组2插屏位订阅页(清当天配额+把计数顶到阈值前一发)", "handler": _cmd_vip_inter},
		{"name": "toast", "label": "弹Toast", "default_args": "Hello Toast!", "handler": _cmd_toast},
		{"name": "luid", "label": "获取LUID并复制", "handler": _cmd_luid},
		{"name": "uuid", "label": "获取UUID并复制", "handler": _cmd_uuid},
		{"name": "http_headers", "label": "打印HttpClient公共Header", "handler": _cmd_http_headers},
		{"name": "nettype", "label": "打印当前网络类型", "handler": _cmd_nettype},
		{"name": "test_att", "label": "测试ATT流程", "handler": _cmd_test_att, "editor_only": true},
		{
			"name": "test_err_cheat",
			"label": "推错误A(来自cheat_commands,验Crashlytics分组)",
			"handler": _cmd_test_err_cheat
		},
		{
			"name": "test_err_page",
			"label": "推错误B(来自game_page,验Crashlytics分组;需在游戏页内点)",
			"tab": CheatCommand.Tab.GAMEPLAY
		},
		{"name": "thumb_reset", "label": "重置LIKE计时(立刻满足间隔条件)", "tab": CheatCommand.Tab.GAMEPLAY},
		{"name": "thumb_r4", "label": "打印当前R4+解格坐标", "tab": CheatCommand.Tab.GAMEPLAY},
		{
			"name": "toast_text",
			"label": "切 normal_start_toast_text 组 (⚠️已固化组2,切组无效果)",
			"default_args": "1",
			"handler": _cmd_toast_text
		},
		{
			"name": "pace_reset",
			"label": "清 BankSorter 排序缓存(pace 排序实验 debug 用;normal_level 切组时自动清)",
			"handler": _cmd_pace_reset
		},
		{
			"name": "dup_puzzle",
			"label": "构造 DUPLICATE_PUZZLE 重复题复现存档 (尺寸 rank lk_idx 关号)",
			"default_args": "8 4 9 991",
			"handler": _cmd_dup_puzzle
		},
		{
			"name": "gamble_user",
			"label": "直设 is_gamble_user 三态(-1未打标/0推理/1赌博;V1.15.0 差异化难度分布)",
			"default_args": "0",
			"handler": _cmd_gamble_user
		},
		{
			"name": "gamble_status",
			"label": "打印差异化难度分布 pipeline 状态(tag + 打标聚合位 + 11503 counter + 派生占比)",
			"handler": _cmd_gamble_status
		},
		{"name": "logout", "label": "登出(真机;之后自动重新 guest 登录)", "handler": _cmd_logout},
		{"name": "delacc", "label": "删号(真机;云端+本地清空,之后应是新匿名账号)", "handler": _cmd_del_acc},
		{
			"name": "authstate",
			"label": "打印当前登录态(登录/渠道/device_id/进度选择未决态)",
			"handler": _cmd_auth_state
		},
		{
			"name": "acc_deleted",
			"label": "模拟服务端判「账号已销毁」(1003;编辑器/真机均可;回 home 应弹告知窗,确认后清本地+退出进程)",
			"handler": _cmd_acc_deleted
		},
		{"name": "rc", "label": "远程控制台开关(on/off,空=看状态)", "default_args": "on", "handler": _cmd_rc},
	]
	_register_commands()
	_register_tabs()
	CheatBus.command_issued.connect(_on_command_issued)


func _register_tabs() -> void:
	_tabs = [
		CheatTabCommand.new(),
		CheatTabGameplay.new(),
		CheatTabActivity.new(),
		CheatTabAb.new(),
		CheatTabLog.new(),
		CheatTabAd.new(),
		CheatTabLang.new(),
		CheatTabPuzzle.new(),
		CheatTabInfo.new(),
	]
	for t: CheatTabBase in _tabs:
		CheatBus.register_tab(t.title(), t.build)


func _register_ab_params() -> void:
	for cfg: AbConfigBase in ABTestManager.get_all_configs():
		CheatBus.register_ab_param(cfg.key, cfg.cheat_label(), cfg.cheat_value_str)


func _register_commands() -> void:
	for def: Dictionary in _command_defs:
		if def.get("editor_only", false) and not OS.has_feature("editor"):
			continue
		var cmd := CheatCommand.new()
		cmd.name = def["name"]
		cmd.label = def["label"]
		cmd.default_args = def.get("default_args", "")

		cmd.tab = def.get("tab", CheatCommand.Tab.COMMAND)
		CheatBus.register_command(cmd)


## 按命令名寻找处理 Callable 并传入参数，具体副作用集中在对应命令函数。
func _on_command_issued(cmd_name: String, args: Array[String]) -> void:
	for def: Dictionary in _command_defs:
		if def["name"] == cmd_name and def.has("handler"):
			(def["handler"] as Callable).call(args)
			return


func _input(event: InputEvent) -> void:
	if not _clickdbg_enabled:
		return
	var t: String = Time.get_time_string_from_system()

	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		print(
			(
				"[ClickDbg][%s] btn=%d pos=%s → (no control hovered)"
				% [t, mb.button_index, mb.position]
			)
		)
	else:
		print(
			(
				"[ClickDbg][%s] btn=%d pos=%s → %s mouse_filter=%d"
				% [t, mb.button_index, mb.position, hovered.get_path(), hovered.mouse_filter]
			)
		)


func _cmd_returned_user(_args: Array[String]) -> void:
	var group: int = ABTestManager.normal_level.value()
	if group != 12001 and group != 12002:
		print("[Cheat] returned_user: 当前 normal_level=%d 不是回流实验组" % group)
		return
	var level: int = GameState.get_current_level()
	GameState.cheat_mark_returned_user()
	UIManager.hide_ui(UiName.GAME)
	UIManager.show_ui(UiName.GAME, {"level_index": level})
	UIManager.hide_ui(UiName.HOME)
	print("[Cheat] returned_user: normal_level=%d, 重进 Lv%d" % [group, level])


func _cmd_re_login(args: Array[String]) -> void:
	var keep_date: bool = args.size() > 0 and args[0] == "keep"
	if not keep_date:
		GameState.set_last_splash_date("")
	UIManager.hide_all()
	var splash := UIManager.show_ui(UiName.SPLASH) as SplashPage

	splash.loading_complete.connect(
		func() -> void:
			UIManager.hide_ui(UiName.SPLASH)
			UIManager.show_ui(UiName.HOME),
		CONNECT_ONE_SHOT
	)

	get_tree().create_timer(3.0).timeout.connect(
		func() -> void:
			if splash != null and splash.is_showing():
				splash.force_complete()
	)


func _cmd_reset_tutorial(_args: Array[String]) -> void:
	GameState.set_tutorial_done(false)
	GameState.set_current_level(1)
	UIManager.show_ui(UiName.TUTORIAL)


func _cmd_today_stats(args: Array[String]) -> void:
	var cat_total: int = int(args[0]) if args.size() > 0 else 48
	var mark_total: int = int(args[1]) if args.size() > 1 else 490

	GameState.cheat_set_today_win_stats(cat_total, mark_total, int(ABTestManager.pass_text.value()))
	push_warning(
		(
			"[cheat] 今日战绩已设为 猫=%d 叉=%d(下次主线通关生效)"
			% [GameState.get_today_cat_found(), GameState.get_today_mark_placed()]
		)
	)


## 重置调试实验、游戏存档与推荐队列后退出进程，这是实际清档操作。
func _cmd_clear(_args: Array[String]) -> void:
	if OS.has_feature("rel") or not DebugOverrideStore.reset_all():
		return
	GameState.reset_all()
	LevelRecManager.reset_all()
	get_tree().quit()


func _cmd_toast(args: Array[String]) -> void:
	var msg: String = " ".join(args) if args.size() > 0 else "Hello Toast!"
	Toast.popup(msg, self)


func _cmd_kill(_args: Array[String]) -> void:
	OS.kill(OS.get_process_id())


const _VIB_LEVEL_MAP: Dictionary = {
	1: VibrateManager.Level.LEVEL1,
	2: VibrateManager.Level.LEVEL2,
	3: VibrateManager.Level.LEVEL3,
	4: VibrateManager.Level.LEVEL4,
	5: VibrateManager.Level.LEVEL5,
	6: VibrateManager.Level.LEVEL6,
	7: VibrateManager.Level.LEVEL7,
	10: VibrateManager.Level.LEVEL10,
}


func _cmd_vibrate(args: Array[String]) -> void:
	if args.size() > 0 and args[0].to_lower() == "all":
		var seq: Array = _VIB_LEVEL_MAP.keys()
		for i in seq.size():
			var level_num: int = seq[i]
			VibrateManager.play_vibrate(_VIB_LEVEL_MAP[level_num])
			Toast.popup("vibrate: LEVEL%d (%d/8)" % [level_num, i + 1], self)
			await get_tree().create_timer(1.0).timeout
		return
	var n: int = int(args[0]) if args.size() > 0 else 2
	if not _VIB_LEVEL_MAP.has(n):
		Toast.popup("vibrate: 无效等级 %d (有效:1-7/10 或 all)" % n, self)
		return
	VibrateManager.play_vibrate(_VIB_LEVEL_MAP[n])
	Toast.popup("vibrate: LEVEL%d" % n, self)


func _cmd_feedback(_args: Array[String]) -> void:
	var page := UIManager.show_ui(UiName.FEEDBACK)
	await page.closed
	UIManager.hide_ui(UiName.FEEDBACK)
	UIManager.show_ui(UiName.HOME)


func _cmd_privacy_v2(_args: Array[String]) -> void:
	var dialog := UIManager.show_ui(UiName.PRIVACY_V2)
	await dialog.accepted
	UIManager.hide_ui(UiName.PRIVACY_V2)
	print("[Cheat] privacy_v2: 已同意并关闭")


func _cmd_privacy_v3(_args: Array[String]) -> void:
	var dialog := UIManager.show_ui(UiName.PRIVACY_V3)
	await dialog.accepted
	UIManager.hide_ui(UiName.PRIVACY_V3)
	print("[Cheat] privacy_v3: 已同意并关闭")


func _cmd_streak_push(_args: Array[String]) -> void:
	print(
		(
			"[Cheat] streak_push: push_style=%d last_checkin=%s missed_days=%d unlocked=%s"
			% [
				ABTestManager.push_style.value(),
				StreakManager.get_data().last_checkin_date,
				StreakManager.missed_days(),
				StreakManager.is_unlocked(),
			]
		)
	)
	StreakPushScheduler.reevaluate("cheat")


func _cmd_show_cmp(_args: Array[String]) -> void:
	SettingPage.debug_force_show_cmp = true
	UIManager.show_ui(UiName.SETTING)
	print("[Cheat] show_cmp: 已强制显示 CMP 行并打开设置页")


## 修改存档主线进度后打开指定关卡，同时隐藏首页。
func _cmd_level(args: Array[String]) -> void:
	var idx: int = int(args[0]) if args.size() > 0 else 1
	GameState.cheat_jump_to_level(idx)
	UIManager.show_ui(UiName.GAME, {"level_index": idx})

	UIManager.hide_ui(UiName.HOME)


func _cmd_pre_cat(args: Array[String]) -> void:
	var arg: String = args[0].to_lower() if args.size() > 0 else ""
	if arg == "off":
		GamePage.debug_force_pre_cat = false
		print("[Cheat] pre_cat: 强制预放猫已关闭(注意本关的关级锁仍在,通关或 clear 才清)")
		return
	GamePage.debug_force_pre_cat = true

	if not GameState.get_endgame_snapshot().is_empty():
		GameState.clear_endgame_snapshot()
		print("[Cheat] pre_cat: 已丢弃当前关残局快照(残局复原会抢在强制预放之前,不清则 cheat 不生效)")
	if arg == "on":
		print("[Cheat] pre_cat: 强制预放猫已开启,下次进关生效")
		return

	var game: Node = UIManager.get_ui(UiName.GAME)
	if game == null or not game.visible:
		print("[Cheat] pre_cat: 强制预放猫已开启;当前不在局内,进关后生效")
		return
	var lv: int = GameState.get_current_level()
	print("[Cheat] pre_cat: 强制预放猫已开启,重进第 %d 关" % lv)
	UIManager.show_ui(UiName.GAME, {"level_index": lv})


func _cmd_cat_decay(args: Array[String]) -> void:
	if not OS.has_feature("editor") or OS.has_feature("rel"):
		return
	if args.size() > 1:
		print("[Cheat] 用法: cat_decay [0~86400的倍率|reset]; 空参数查看, 1=正常")
		return
	if args.size() == 1:
		var input: String = args[0]
		if input != "reset" and not input.is_valid_float():
			print("[Cheat] cat_decay: 非法倍率, 保留原值; 用法: cat_decay [0~86400|reset]")
			return
		var scale: float = 1.0 if input == "reset" else float(input)
		var service: RefCounted = HomeCompanionService.new()
		if not service.set_debug_satiety_decay_scale(scale):
			print("[Cheat] cat_decay: 倍率必须是0~86400的有限数值, 保留原值")
			return
	var current_scale: float = HomeCompanionService.debug_satiety_decay_scale()
	print(
		(
			"[Cheat] cat_decay: %.3fx, 每分钟消耗%.3f点; 仅编辑器本进程有效, 重启恢复1x; 已扣饱腹值不会恢复"
			% [current_scale, HomeCompanionSystem.DECAY_PER_SECOND * current_scale * 60.0]
		)
	)


func _cmd_cat_event_date(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	if args.size() > 1:
		print("[Cheat] 用法: cat_event_date [YYYY-MM-DD|reset]; 空参数查看")
		return
	if args.size() == 1:
		var date_text: String = "" if args[0] == "reset" else args[0]
		if not HomeCompanionService.set_debug_event_date(date_text):
			print("[Cheat] cat_event_date: 日期非法, 保留原值; 格式 YYYY-MM-DD")
			return
	var current: String = HomeCompanionService.debug_event_date()
	var ended: bool = bool(GameState.get_home_companion_data().get("event_ended", false))
	print(
		(
			"[Cheat] cat_event_date: %s; 活动结束标记=%s(为true时回活动期需先cat_reset); 重进主页生效, 重启恢复"
			% [current if not current.is_empty() else "真实日期", ended]
		)
	)


func _cmd_cat_satiety_get(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	if not args.is_empty():
		print("[Cheat] 用法: cat_satiety_get (无需参数)")
		return
	var service: RefCounted = HomeCompanionService.new()
	var data: Dictionary = service.snapshot()
	if not bool(data.get("satiety_enabled", false)):
		print("[Cheat] cat_satiety_get: 饱食度尚未初始化")
		return
	print("[Cheat] cat_satiety_get: %.3f" % float(data["satiety"]))


func _cmd_cat_satiety(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	if args.size() != 1 or not args[0].is_valid_float():
		print("[Cheat] 用法: cat_satiety <0~100的饱食度>")
		return
	var satiety: float = float(args[0])
	if not is_finite(satiety) or satiety < 0.0 or satiety > 100.0:
		print("[Cheat] cat_satiety: 数值必须在0~100之间, 保留原值")
		return
	if not ABTestManager.home_companion_cat.has_satiety():
		print("[Cheat] cat_satiety: 当前不是饱腹陪伴组, 请先切换 home_companion_cat 到组4")
		return
	var data: Dictionary = GameState.get_home_companion_data()
	if not bool(data.get("satiety_enabled", false)):
		print("[Cheat] cat_satiety: 饱腹尚未初始化, 请先获得罐头并进入组4主页")
		return

	var calendar: Dictionary = Time.get_datetime_dict_from_system()
	data["satiety"] = satiety
	data["satiety_at"] = Time.get_unix_time_from_datetime_dict(calendar)
	data["satiety_active"] = true
	GameState.set_home_companion_data(data)
	print("[Cheat] cat_satiety: 已设置为%.3f; 继续自然衰减, 不改变罐头库存/教学/分组" % satiety)


func _cmd_cat_cans(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	var amount: int = _companion_add_amount(args, 10, "cat_cans")
	if amount <= 0:
		return
	var data: Dictionary = GameState.get_home_companion_data()
	var previous: int = clampi(int(data.get("cans", 0)), 0, HomeCompanionSystem.INVENTORY_CAP)
	var added: int = mini(amount, HomeCompanionSystem.INVENTORY_CAP - previous)
	data["cans"] = previous + added
	GameState.set_home_companion_data(data)
	print("[Cheat] cat_cans: +%d, 库存=%d; 不改变通关获取进度/饱腹/教学" % [added, data["cans"]])


func _cmd_cat_candy(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	var amount: int = _companion_add_amount(args, 20, "cat_candy")
	if amount <= 0:
		return
	var data: Dictionary = GameState.get_home_companion_data()
	var previous: int = maxi(0, int(data.get("candy_total", 0)))
	var final_threshold: int = HomeCompanionSystem.REWARD_THRESHOLDS.back()
	var added: int = mini(amount, maxi(0, final_threshold - previous))
	data["candy_total"] = previous + added
	GameState.set_home_companion_data(data)
	print("[Cheat] cat_candy: +%d, 累计=%d; 仅增加进度, 不直接发奖/重置已领奖记录" % [added, data["candy_total"]])


func _cmd_cat_reset(args: Array[String]) -> void:
	if OS.has_feature("rel") or _companion_reset_busy:
		return
	if not args.is_empty():
		print("[Cheat] 用法: cat_reset")
		return
	_companion_reset_busy = true
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	var reopen_home: bool = home != null and home.is_showing()
	await UIManager.hide_ui(UiName.HOME_COMPANION_GUIDE)
	await UIManager.hide_ui(UiName.HOME_COMPANION_REWARD)
	if reopen_home:
		await UIManager.hide_ui(UiName.HOME)
	var previous: Dictionary = GameState.get_home_companion_data()

	var reset_data: Dictionary = (
		HomeCompanionSystem
		. new(
			{
				"tutorials": {},
				"granted": previous.get("granted", {}),
				"shown": previous.get("shown", {})
			}
		)
		. snapshot()
	)
	GameState.set_home_companion_data(reset_data)
	if reopen_home:
		UIManager.show_ui(UiName.HOME)
	_companion_reset_busy = false
	print("[Cheat] cat_reset: 陪伴糖果/罐头/获取进度/全部教学标识/饱腹已重置; 关卡、分组、其他系统与已发奖励保留; 罐头与饱腹教学需重新获得罐头后回主页触发")


func _companion_add_amount(args: Array[String], default_amount: int, command: String) -> int:
	if args.is_empty():
		return default_amount
	if args.size() == 1 and args[0].is_valid_int():
		var digits: String = args[0].trim_prefix("+").lstrip("0")
		if digits.length() < 19 or (digits.length() == 19 and digits <= "9223372036854775807"):
			var amount: int = int(args[0])
			if amount > 0:
				return amount
	print("[Cheat] 用法: %s [正整数增加量]" % command)
	return 0


func _cmd_locate(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	page.set_tool_count("locate", GameState.get_tool_count("locate") + amount)


func _cmd_hint(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	page.set_tool_count("hint", GameState.get_tool_count("hint") + amount)


func _cmd_mouse(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	page.set_tool_count(ToolKind.MOUSE, GameState.get_tool_count(ToolKind.MOUSE) + amount)


func _cmd_draft_add(args: Array[String]) -> void:
	var amount: int = int(args[0]) if args.size() > 0 else 3
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null or not page.has_method("set_tool_count"):
		return
	page.set_tool_count(ToolKind.DRAFT, GameState.get_tool_count(ToolKind.DRAFT) + amount)


func _cmd_misplace_repro(args: Array[String]) -> void:
	var delay: float = float(args[0]) if args.size() > 0 else 0.2
	delay = clampf(delay, 0.0, 2.0)
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[Cheat] misplace_repro: 无活跃 game_page,请先进关")
		return
	if not page.has_method("_on_locate_btn_pressed") or not page.has_method("do_wrong_guess_mark"):
		print("[Cheat] misplace_repro: 页面缺 _on_locate_btn_pressed / do_wrong_guess_mark")
		return
	if ABTestManager.misplace_reaction.value() != MisplaceReactionConfig.VALUE_CONFLICT:
		ABTestManager.misplace_reaction.set_debug_override(MisplaceReactionConfig.VALUE_CONFLICT)
		print(
			"[Cheat] misplace_repro: 已切 misplace_react = %d" % MisplaceReactionConfig.VALUE_CONFLICT
		)

	if GameState.get_tool_count("locate") <= 0 and page.has_method("set_tool_count"):
		page.set_tool_count("locate", 1)

	var cats_before: Array[Vector2i] = _misplace_repro_collect_cats(page)
	print(
		(
			"[Cheat] misplace_repro: locate 前已放 %d 只 CAT,触发 locate 后等 %.2fs 触发错位双击"
			% [cats_before.size(), delay]
		)
	)
	page._on_locate_btn_pressed()
	var cats_after: Array[Vector2i] = _misplace_repro_collect_cats(page)
	var new_cats: Array[Vector2i] = _misplace_repro_diff_cats(cats_before, cats_after)
	if new_cats.size() != 1:
		print(
			(
				"[Cheat] misplace_repro: locate 未成功放猫或放了多只(before=%d after=%d),中止"
				% [cats_before.size(), cats_after.size()]
			)
		)
		return
	var locate_cell: Vector2i = new_cats[0]
	print("[Cheat] misplace_repro: L = (%d,%d)" % [locate_cell.x, locate_cell.y])
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(page):
		return

	var target: Vector2i = _misplace_repro_find_target_conflicting_only_with(page, locate_cell)
	if target.x < 0:
		print("[Cheat] misplace_repro: 找不到「只跟 L 冲突」的空非解格(L 附近可能被其他 CAT 挤占),换关重试")
		return

	var puzzle: Dictionary = page.get("_puzzle") if page.get("_puzzle") != null else {}
	var regions: Array = puzzle.get("regions", [])
	var expected_rule: int = QueendokuCore.classify_violation(
		target.x, target.y, [locate_cell], regions
	)
	print(
		(
			"[Cheat] misplace_repro: 触发错位双击 @ (%d,%d) 预期冲突猫=L=(%d,%d) rule=%s"
			% [
				target.x,
				target.y,
				locate_cell.x,
				locate_cell.y,
				_misplace_repro_rule_name(expected_rule)
			]
		)
	)
	page.do_wrong_guess_mark(target.x, target.y)


func _misplace_repro_collect_cats(page: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var board_view: Variant = page.get("_board_view")
	if board_view == null or not board_view.has_method("get_board"):
		return out
	var board: Array = board_view.get_board()
	for r in range(board.size()):
		var row: Array = board[r] as Array
		if row == null:
			continue
		for c in range(row.size()):
			if int(row[c]) == CellState.CAT:
				out.append(Vector2i(r, c))
	return out


func _misplace_repro_diff_cats(before: Array[Vector2i], after: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v in after:
		if not before.has(v):
			out.append(v)
	return out


func _misplace_repro_find_target_conflicting_only_with(
	page: Node, locate_cell: Vector2i
) -> Vector2i:
	var puzzle: Dictionary = page.get("_puzzle") if page.get("_puzzle") != null else {}
	if puzzle.is_empty():
		return Vector2i(-1, -1)
	var regions: Array = puzzle.get("regions", [])
	var solution: Array = puzzle.get("solution", [])
	var level_config: Dictionary = (
		page.get("_level_config") if page.get("_level_config") != null else {}
	)
	var sz: int = level_config.get("size", 4)
	var board_view: Variant = page.get("_board_view")
	if board_view == null:
		return Vector2i(-1, -1)
	var board: Array = board_view.get_board()

	var other_placed: Array[Vector2i] = []
	for pos in _misplace_repro_collect_cats(page):
		if pos != locate_cell:
			other_placed.append(pos)
	for r in range(sz):
		for c in range(sz):
			if not CellState.is_blank(board[r][c]):
				continue
			var sol_row: Array = solution[r] as Array if r < solution.size() else []
			if c < sol_row.size() and bool(sol_row[c]):
				continue

			if (
				QueendokuCore.classify_violation(r, c, [locate_cell], regions)
				== QueendokuCore.Rule.NONE
			):
				continue

			if (
				not other_placed.is_empty()
				and (
					QueendokuCore.classify_violation(r, c, other_placed, regions)
					!= QueendokuCore.Rule.NONE
				)
			):
				continue
			return Vector2i(r, c)
	return Vector2i(-1, -1)


func _misplace_repro_rule_name(rule: int) -> String:
	match rule:
		QueendokuCore.Rule.SAME_COLOR:
			return "SAME_COLOR"
		QueendokuCore.Rule.SAME_LINE:
			return "SAME_LINE"
		QueendokuCore.Rule.NO_TOUCH:
			return "NO_TOUCH"
		_:
			return "NONE"


func _cmd_misplace_stress(args: Array[String]) -> void:
	var count: int = int(args[0]) if args.size() > 0 else 5
	count = clampi(count, 1, 20)
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[Cheat] misplace_stress: 无活跃 game_page,请先进关")
		return
	if not page.has_method("_on_locate_btn_pressed") or not page.has_method("do_wrong_guess_mark"):
		print("[Cheat] misplace_stress: 页面缺方法")
		return
	if ABTestManager.misplace_reaction.value() != MisplaceReactionConfig.VALUE_CONFLICT:
		ABTestManager.misplace_reaction.set_debug_override(MisplaceReactionConfig.VALUE_CONFLICT)
		print(
			(
				"[Cheat] misplace_stress: 已切 misplace_react = %d"
				% MisplaceReactionConfig.VALUE_CONFLICT
			)
		)

	if page.has_method("set_tool_count"):
		page.set_tool_count("locate", 999)

	var lead_delay: float = 0.15
	var mid_delay: float = 0.1
	var tail_delay: float = 1.75
	for i in range(count):
		print("[Cheat] misplace_stress: 轮 %d/%d ─────" % [i + 1, count])

		var wg0: bool = bool(page.get("_wrong_guess_pending"))
		var lives0: int = int(page.get("_lives")) if page.get("_lives") != null else -1
		var cat_before: int = _misplace_count_cats(page)
		print(
			(
				"  [pre]  _wrong_guess_pending=%s _lives=%d cats_on_board=%d"
				% [str(wg0), lives0, cat_before]
			)
		)

		page._on_locate_btn_pressed()
		var cat_after1: int = _misplace_count_cats(page)
		print("  [L1]   locate1 后 cats_on_board=%d (+%d)" % [cat_after1, cat_after1 - cat_before])
		await get_tree().create_timer(lead_delay).timeout
		if not is_instance_valid(page):
			return

		var target: Vector2i = _misplace_repro_find_conflict_target(page)
		if target.x < 0:
			print("  [skip] 找不到冲突目标,可能盘面已被之前几轮填满/无非解空格;跳过本轮 tail")
			await get_tree().create_timer(tail_delay).timeout
			continue
		print("  [dbl]  do_wrong_guess_mark @ (%d,%d)" % [target.x, target.y])
		page.do_wrong_guess_mark(target.x, target.y)

		await get_tree().create_timer(mid_delay).timeout
		if not is_instance_valid(page):
			return
		var wg_mid: bool = bool(page.get("_wrong_guess_pending"))
		var conflict_pos_mid: Vector2i = (
			page.get("_conflict_target_pos")
			if page.get("_conflict_target_pos") != null
			else Vector2i(-1, -1)
		)
		print(
			(
				"  [mid]  _wrong_guess_pending=%s _conflict_target_pos=%s (期望 true, 非(-1,-1))"
				% [str(wg_mid), str(conflict_pos_mid)]
			)
		)

		var cat_before2: int = _misplace_count_cats(page)
		page._on_locate_btn_pressed()
		var cat_after2: int = _misplace_count_cats(page)
		var delta2: int = cat_after2 - cat_before2
		print(
			(
				"  [L2]   locate2 后 cats_on_board=%d (delta=%d) — %s"
				% [
					cat_after2,
					delta2,
					"⚠️GUARD 失效: 有额外 CAT 落到棋盘上" if delta2 > 0 else "guard 生效, 无新增 CAT"
				]
			)
		)

		await get_tree().create_timer(tail_delay).timeout
	print("[Cheat] misplace_stress: 完成 %d 轮" % count)


func _misplace_count_cats(page: Node) -> int:
	var board_view: Variant = page.get("_board_view")
	if board_view == null or not board_view.has_method("get_board"):
		return -1
	var board: Array = board_view.get_board()
	var n: int = 0
	for row in board:
		if row is Array:
			for st in row:
				if int(st) == CellState.CAT:
					n += 1
	return n


func _misplace_repro_find_conflict_target(page: Node) -> Vector2i:
	var puzzle: Dictionary = page.get("_puzzle") if page.get("_puzzle") != null else {}
	if puzzle.is_empty():
		return Vector2i(-1, -1)
	var regions: Array = puzzle.get("regions", [])
	var solution: Array = puzzle.get("solution", [])
	var level_config: Dictionary = (
		page.get("_level_config") if page.get("_level_config") != null else {}
	)
	var sz: int = level_config.get("size", 4)
	var board_view: Variant = page.get("_board_view")
	if (
		board_view == null
		or not board_view.has_method("get_board")
		or not board_view.has_method("get_cell_state")
	):
		return Vector2i(-1, -1)
	var board: Array = board_view.get_board()
	var placed: Array[Vector2i] = []
	for r in range(sz):
		for c in range(sz):
			if board[r][c] == CellState.CAT:
				placed.append(Vector2i(r, c))
	if placed.is_empty():
		return Vector2i(-1, -1)
	for r in range(sz):
		for c in range(sz):
			if not CellState.is_blank(board[r][c]):
				continue
			var sol_row: Array = solution[r] as Array if r < solution.size() else []
			if c < sol_row.size() and bool(sol_row[c]):
				continue
			var rule: int = QueendokuCore.classify_violation(r, c, placed, regions)
			if rule != QueendokuCore.Rule.NONE:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _cmd_swipe_viz(_args: Array[String]) -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[Cheat] swipe_viz: 当前无活跃游戏页")
		return
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("toggle_swipe_zone_viz"):
		print("[Cheat] swipe_viz: board_view 不可用")
		return
	var on: bool = bv.toggle_swipe_zone_viz()
	print("[Cheat] 保护区可视化: %s (画×滑动锁定行/列后可见)" % ("开" if on else "关"))
	if on:
		_print_swipe_viz_context(bv)


func _print_swipe_viz_context(bv: Variant) -> void:
	var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
	var group_value: int = int(cfg.value())
	var tol_pct: float = SwipeProtectConfig.HOTZONE_TOL_PCT
	var guard_type: String = "SwipeAxisGuard(行/列锁)"
	if cfg.has_target_color_protection():
		guard_type = "SwipeAxisGuard + 目标颜色保护"
	var slot_px: int = bv.get_grid_slot() if bv.has_method("get_grid_slot") else -1
	var pad_px: int = bv.get_grid_padding() if bv.has_method("get_grid_padding") else -1
	var tol_px: float = tol_pct * BoardView.CELL_PX
	print("[Cheat]   swipe_protect=%d %s" % [group_value, _swipe_group_desc(group_value)])
	print("[Cheat]   guard=%s" % guard_type)
	print(
		(
			"[Cheat]   几何: cell=%d px, slot=%d px(含 gap), padding=%d px"
			% [BoardView.CELL_PX, slot_px, pad_px]
		)
	)
	print("[Cheat]   正交越界 tol=%.1f%% × %d = %.1f px" % [tol_pct * 100.0, BoardView.CELL_PX, tol_px])

	if cfg.has_target_color_protection():
		var tc_tol_pct: float = cfg.target_color_tol_pct()
		print(
			(
				"[Cheat]   目标色格 tol = %.1f%% × %d = %.1f px%s (越界进目标色格时取代上面的正交 tol)"
				% [
					tc_tol_pct * 100.0,
					BoardView.CELL_PX,
					tc_tol_pct * BoardView.CELL_PX,
					(
						"  [OVERRIDDEN by swipe_tc_tol]"
						if SwipeProtectConfig.debug_tc_tol_pct_is_overridden()
						else ""
					),
				]
			)
		)
		print("[Cheat]   目标色 = 本累积段内滑过格同属的色区;出现第二个色区即失效(本段内不可恢复),段边界 = 每次解锁")
		print("[Cheat]   viz 图例: 绿带=正交越界 tol(非目标色格) / 青段+亮青线=目标色格实际解锁线(更近)")

	var win_sz: Vector2i = DisplayServer.window_get_size()
	var vp_sz: Vector2 = bv.get_viewport().get_visible_rect().size
	var bv_gpos: Vector2 = bv.global_position
	var bv_scale: Vector2 = bv.scale
	print(
		(
			"[Cheat]   设备度量: window(物理像素)=%dx%d  viewport(游戏空间)=%.0fx%.0f"
			% [win_sz.x, win_sz.y, vp_sz.x, vp_sz.y]
		)
	)
	print(
		(
			"[Cheat]              BoardView global_position=(%.0f, %.0f)  scale=%.3f"
			% [bv_gpos.x, bv_gpos.y, bv_scale.x]
		)
	)


func _swipe_group_desc(group_value: int) -> String:
	match group_value:
		SwipeProtectConfig.VALUE_HOTZONE_40:
			return "(组1:响应热区 40%)"
		SwipeProtectConfig.VALUE_TARGET_COLOR_20:
			return "(组10:目标颜色保护 20%)"
		SwipeProtectConfig.VALUE_TARGET_COLOR_0:
			return "(组11:目标颜色保护 0%)"
		_:
			return "(已删 / 未知,落组1 40%)"


func _cmd_swipe_tc_tol(args: Array[String]) -> void:
	var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
	if args.is_empty():
		var v: int = int(cfg.value())

		var eff_pct: float = SwipeProtectConfig.target_color_tol_pct_for(
			SwipeProtectConfig.VALUE_TARGET_COLOR_20
		)
		var applies_now: bool = SwipeProtectConfig.has_target_color_protection_for(v)
		print(
			(
				"[Cheat] swipe_tc_tol: 当前=%.2f %s(组10 默认 %.2f / 组11 默认 %.2f) (当前 swipe_protect=%d %s,%s生效)"
				% [
					eff_pct,
					"[OVERRIDDEN] " if SwipeProtectConfig.debug_tc_tol_pct_is_overridden() else "",
					SwipeProtectConfig.TARGET_COLOR_TOL_PCT_20,
					SwipeProtectConfig.TARGET_COLOR_TOL_PCT_0,
					v,
					_swipe_group_desc(v),
					"" if applies_now else "override 不",
				]
			)
		)
		return
	if args[0].to_lower() == "reset":
		SwipeProtectConfig.debug_set_tc_tol_pct_override(-1.0)
		print(
			(
				"[Cheat] swipe_tc_tol: 已恢复分组默认(组10=%.2f / 组11=%.2f)"
				% [
					SwipeProtectConfig.TARGET_COLOR_TOL_PCT_20,
					SwipeProtectConfig.TARGET_COLOR_TOL_PCT_0
				]
			)
		)
		return
	var pct: float = args[0].to_float()
	if pct < 0.0 or pct > 1.0:
		print("[Cheat] swipe_tc_tol: 非法输入 '%s',保留原值。用法:0<=pct<=1,或 reset" % args[0])
		return
	SwipeProtectConfig.debug_set_tc_tol_pct_override(pct)
	print("[Cheat] swipe_tc_tol: %.2f (仅组10/11 的目标色格生效,只影响下一笔画;非目标色格仍 40%% 基线)" % pct)


func _cmd_swipe_logic_viz(_args: Array[String]) -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[Cheat] swipe_logic_viz: 当前无活跃游戏页")
		return
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("toggle_swipe_extra_zone_viz"):
		print("[Cheat] swipe_logic_viz: board_view 不可用")
		return
	var on: bool = bv.toggle_swipe_extra_zone_viz()
	print("[Cheat] swipe_logic 扩展环可视化: %s (对照组 slop=0 无框;实验组1 默认 20%%)" % ("开" if on else "关"))


func _cmd_touch_viz(_args: Array[String]) -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[Cheat] touch_viz: 当前无活跃游戏页")
		return
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("toggle_touch_point_viz"):
		print("[Cheat] touch_viz: board_view 不可用")
		return
	var on: bool = bv.toggle_touch_point_viz()
	print("[Cheat] 多指触点可视化: %s (对照组恒只一个圆;多指组每指一个)" % ("开" if on else "关"))


func _cmd_swipe_logic_slop(args: Array[String]) -> void:
	var cfg: SwipeLogicConfig = ABTestManager.swipe_logic
	if args.is_empty():
		print(
			(
				"[Cheat] swipe_logic_slop: 当前=%.3f %s(默认 %.2f,组=%d)"
				% [
					SwipeLogicConfig.effective_slop_pct(),
					"[OVERRIDDEN] " if SwipeLogicConfig.debug_slop_pct_is_overridden() else "",
					SwipeLogicConfig.DEFAULT_SLOP_PCT,
					int(cfg.value()),
				]
			)
		)
		return
	if args[0].to_lower() == "reset":
		SwipeLogicConfig.debug_set_slop_pct_override(-1.0)
		print("[Cheat] swipe_logic_slop: 已恢复默认 %.2f" % SwipeLogicConfig.DEFAULT_SLOP_PCT)
		return
	var v: float = args[0].to_float()
	if v == 0.0:
		SwipeLogicConfig.debug_set_slop_pct_override(-1.0)
		print(
			"[Cheat] swipe_logic_slop: 0 → 清除 override,回默认 %.2f" % SwipeLogicConfig.DEFAULT_SLOP_PCT
		)
		return
	if v < 0.0 or v > 1.0:
		print("[Cheat] swipe_logic_slop: 非法输入 '%s',保留原值。用法:0.0-1.0 小数,0=清除,或 reset" % args[0])
		return
	SwipeLogicConfig.debug_set_slop_pct_override(v)
	print("[Cheat] swipe_logic_slop: %.3f = %.1fpx (仅组1 生效,下次 press 起效)" % [v, v * 100.0])


func _cmd_cat_dim_alpha(args: Array[String]) -> void:
	var cfg: CatFoundGridConfig = ABTestManager.cat_found_grid
	if args.is_empty():
		print(
			(
				"[Cheat] cat_dim_alpha: 当前=%.3f %s(分组值=%d, 淡化已启用=%s)"
				% [
					cfg.dim_alpha(),
					"[OVERRIDDEN] " if cfg.has_cheat_alpha_override() else "",
					int(cfg.value()),
					str(cfg.is_dim_enabled()),
				]
			)
		)
		return
	if args[0].to_lower() == "reset":
		cfg.set_cheat_alpha_override(CatFoundGridConfig.ALPHA_NO_OVERRIDE)

		var reset_repainted: bool = _refresh_cat_found_grid_dim()
		print(
			(
				"[Cheat] cat_dim_alpha: 已清除覆盖,回分组值 %.3f%s"
				% [cfg.dim_alpha(), "" if reset_repainted else "(无活跃游戏页,下次进关生效)"]
			)
		)
		return

	if not args[0].is_valid_float():
		print("[Cheat] cat_dim_alpha: 非法输入 '%s',保留原值。用法:0<=alpha<=1,或 reset" % args[0])
		return
	var a: float = args[0].to_float()
	if a < 0.0 or a > 1.0:
		print("[Cheat] cat_dim_alpha: 非法输入 '%s',保留原值。用法:0<=alpha<=1,或 reset" % args[0])
		return
	cfg.set_cheat_alpha_override(a)

	var repainted: bool = _refresh_cat_found_grid_dim()
	print("[Cheat] cat_dim_alpha: %.3f%s" % [a, "" if repainted else "(无活跃游戏页,下次进关生效)"])


func _refresh_cat_found_grid_dim() -> bool:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		return false
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("refresh_all_region_dim"):
		return false
	bv.refresh_all_region_dim()
	return true


func _resync_cat_found_grid_dim() -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		return
	var bv: Variant = page.get("_board_view")
	if bv == null or not bv.has_method("set_region_dim_enabled"):
		print("[Cheat] cat_found_grid 切组:活跃页无可用 BoardView,棋盘淡化闸门未重注入(下次进关生效)")
		return

	bv.set_region_dim_enabled(ABTestManager.cat_found_grid.is_dim_enabled())
	print(
		(
			"[Cheat] cat_found_grid 切组,已重注入棋盘淡化闸门(%s)"
			% str(ABTestManager.cat_found_grid.is_dim_enabled())
		)
	)


func _cmd_highspeed_set(args: Array[String]) -> void:
	if args.is_empty():
		print(
			(
				"[Cheat] highspeed_set: 当前(ms) 时间窗口=%.0f%s 高频操作窗口=%.0f%s 高频操作CD=%.0f%s 禁操作CD=%.0f%s"
				% [
					ABTestManager.doubletap_protect.window_300_sec() * 1000.0,
					"[O]" if DoubletapProtectConfig.debug_window_300_is_overridden() else "",
					ABTestManager.doubletap_protect.high_freq_window_sec() * 1000.0,
					"[O]" if DoubletapProtectConfig.debug_high_freq_window_is_overridden() else "",
					ABTestManager.doubletap_protect.high_freq_cd_sec() * 1000.0,
					"[O]" if DoubletapProtectConfig.debug_high_freq_cd_is_overridden() else "",
					ABTestManager.doubletap_protect.high_freq_lock_cd_sec() * 1000.0,
					"[O]" if DoubletapProtectConfig.debug_high_freq_lock_cd_is_overridden() else "",
				]
			)
		)
		print(
			"[Cheat] highspeed_set: 默认(ms) 300 650 660 250 / 用法:highspeed_set <时间窗口> <高频操作窗口> <高频操作CD> <禁操作CD>,或 reset"
		)
		return
	if args[0].to_lower() == "reset":
		DoubletapProtectConfig.debug_set_window_300_override(-1.0)
		DoubletapProtectConfig.debug_set_high_freq_window_override(-1.0)
		DoubletapProtectConfig.debug_set_high_freq_cd_override(-1.0)
		DoubletapProtectConfig.debug_set_high_freq_lock_cd_override(-1.0)
		print("[Cheat] highspeed_set: 已恢复默认(ms) 300 650 660 250")
		return
	if args.size() != 4:
		print(
			(
				"[Cheat] highspeed_set: 参数数量应为 4 个,实收 %d 个。用法:highspeed_set <时间窗口> <高频操作窗口> <高频操作CD> <禁操作CD>(ms),或 reset"
				% args.size()
			)
		)
		return
	var window_ms: float = args[0].to_float()
	var freq_window_ms: float = args[1].to_float()
	var freq_cd_ms: float = args[2].to_float()
	var lock_cd_ms: float = args[3].to_float()
	if window_ms <= 0.0 or freq_window_ms <= 0.0 or freq_cd_ms <= 0.0 or lock_cd_ms < 0.0:
		print("[Cheat] highspeed_set: 非法输入,保留原值。用法:前三项 > 0、禁操作CD >= 0(单位 ms)")
		return
	DoubletapProtectConfig.debug_set_window_300_override(window_ms / 1000.0)
	DoubletapProtectConfig.debug_set_high_freq_window_override(freq_window_ms / 1000.0)
	DoubletapProtectConfig.debug_set_high_freq_cd_override(freq_cd_ms / 1000.0)
	DoubletapProtectConfig.debug_set_high_freq_lock_cd_override(lock_cd_ms / 1000.0)
	print(
		(
			"[Cheat] highspeed_set: 已设置(ms) 时间窗口=%.0f 高频操作窗口=%.0f 高频操作CD=%.0f 禁操作CD=%.0f"
			% [
				window_ms,
				freq_window_ms,
				freq_cd_ms,
				lock_cd_ms,
			]
		)
	)


func _cmd_dt_freq_state(args: Array[String]) -> void:
	var cfg: DoubletapProtectConfig = ABTestManager.doubletap_protect
	if args.is_empty():
		print(
			(
				"[Cheat] dt_freq_state: doubletap_protect=%d 高频操作状态=%s"
				% [
					int(cfg.value()),
					"开" if cfg.is_high_freq_active() else "关",
				]
			)
		)
		return
	var mode: String = args[0].to_lower()
	if mode == "off":
		cfg.reset_high_freq_state()
		print("[Cheat] dt_freq_state: 已清空高频操作状态机")
		return
	if mode == "on":
		cfg.reset_high_freq_state()
		cfg.notify_double_tap(true)
		cfg.notify_double_tap(true)
		print(
			(
				"[Cheat] dt_freq_state: 已强制进入高频操作状态,CD=%.2fs(仅 doubletap_protect=5/6/7 生效)"
				% cfg.high_freq_cd_sec()
			)
		)
		return
	print("[Cheat] dt_freq_state: 非法参数 '%s',用法:空(打印)/ on / off" % args[0])


func _cmd_toast_text(args: Array[String]) -> void:
	if args.is_empty():
		print("[Cheat] toast_text: 用法 toast_text <0-4>")
		return
	var v: int = args[0].to_int()
	if v < 0 or v > 4:
		print("[Cheat] toast_text: 非法值 '%s',用法 toast_text <0-4>" % args[0])
		return
	ABTestManager.normal_start_toast_text.set_debug_override(v)
	GameState.clear_start_toast_variant_state()
	print("[Cheat] normal_start_toast_text = %d(变体缓存已清)" % v)


func _cmd_free(args: Array[String]) -> void:
	var which: String = args[0] if args.size() > 0 else "all"
	if which not in ["hint", "locate", "all", "off"]:
		print("[Cheat] free 用法: free [hint|locate|all|off],收到: ", which)
		return
	BaseGamePage.debug_force_free_tool = "" if which == "off" else which

	var page: Node = CheatTabBase.get_active_game_page()
	if page != null and page.has_method("_sync_tools_from_state"):
		page.call("_sync_tools_from_state")
	print('[Cheat] free → debug_force_free_tool = "%s"' % BaseGamePage.debug_force_free_tool)


func _cmd_thumb_delay(args: Array[String]) -> void:
	if args.is_empty():
		print("[Cheat] thumb_delay 用法: thumb_delay <秒> | off")
		return
	var arg: String = args[0].strip_edges().to_lower()
	if arg == "off" or arg == "reset" or arg == "default":
		BaseGamePage._missed_cross_delay_override = -1.0
		print("[Cheat] thumb_delay → 恢复默认(遗漏叉 10s)")
		return
	var sec: float = float(arg)
	if sec < 0.0:
		BaseGamePage._missed_cross_delay_override = -1.0
		print("[Cheat] thumb_delay → 恢复默认(遗漏叉 10s)")
		return
	BaseGamePage._missed_cross_delay_override = sec
	print("[Cheat] thumb_delay → 遗漏叉延迟 = %.2fs" % sec)


func _cmd_daily(args: Array[String]) -> void:
	var day: int = -1 if args.is_empty() else maxi(0, int(args[0]))
	DailyGamePage.debug_day_override = day
	CostumeCatalog.debug_day_override = day
	GameState.clear_daily_completion()
	UIManager.show_ui(UiName.DAILY_GAME)


func _cmd_daily_top(args: Array[String]) -> void:
	var top_pct: float = float(args[0]) if not args.is_empty() else 4.1
	var beat: float = 100.0 - top_pct
	var today: String = Time.get_date_string_from_system()
	GameState.mark_daily_completed(today, 69, beat)
	print("[Cheat] daily_top → Top %.1f%% (beat=%.1f%%)" % [top_pct, beat])
	UIManager.show_ui(UiName.HOME)


func _cmd_daily_clear(_args: Array[String]) -> void:
	GameState.clear_daily_completion()
	print(
		(
			"[Cheat] daily_clear: 已清当日完成记录 → 入口态=%s(主页 DC 卡每秒自刷,不必回主页)"
			% [_daily_state_name(DailyEntryState.compute_state())]
		)
	)


func _cmd_daily_first_win_reset(_args: Array[String]) -> void:
	GameState.cheat_reset_daily_first_win_encourage()
	print("[DailyFirstWin] cheat_reset: 已清首次进关与主线首胜日期，关卡进度保留")


func _cmd_costume_dump(_args: Array[String]) -> void:
	var group: int = int(ABTestManager.dc_costume.peek_value())
	print(
		(
			"[Cheat] costume_dump: group=%d(0对照/1实验组1) has_costume=%s can_replay=%s%s"
			% [
				group,
				str(ABTestManager.dc_costume.has_costume()),
				str(ABTestManager.dc_costume.can_replay()),
				(
					""
					if ABTestManager.dc_costume.has_costume()
					else "  ← 对照组:UI 上一切外观都不出现,先 `ab dc_costume 1`"
				)
			]
		)
	)
	var costume_override: int = CostumeCatalog.debug_day_override
	var dc_override: int = DailyGamePage.debug_day_override

	var mismatch: String = ""
	if costume_override != dc_override:
		mismatch = "  ⚠️ 两个 day override 不一致 → 题面与外观错位,跑 `costume_day <id>` 或 `daily <N>` 成对重设"

	print(
		(
			"[Cheat] costume_dump: 当日外观 id=%d(生效,跳过已持有) 纯日期底座=%d day_offset=%d override[外观=%s DC题面=%s]%s"
			% [
				ProfileService.get_today_costume(),
				CostumeCatalog.today_costume(),
				CostumeCatalog.today_day_offset(),
				"off" if costume_override < 0 else str(costume_override),
				"off" if dc_override < 0 else str(dc_override),
				mismatch
			]
		)
	)
	var all_ids: Array[int] = CostumeCatalog.all_ids()
	var held_parts: PackedStringArray = PackedStringArray()
	for id in all_ids:
		if not ProfileService.is_costume_held(id):
			continue
		var remaining: int = ProfileService.costume_trial_remaining_sec(id)
		held_parts.append(
			"%d(%s)" % [id, "默认拥有" if remaining <= 0 else "剩 " + _format_remaining_hms(remaining)]
		)
	print(
		(
			"[Cheat] costume_dump: 持有=%s 装备中=%d(皮肤=%s)"
			% [
				", ".join(held_parts),
				ProfileService.get_costume_id(),
				CostumeCatalog.skin_for(ProfileService.get_costume_id())
			]
		)
	)
	print(
		(
			"[Cheat] costume_dump: 今日已解锁=%s 红点=%s 教学已看=%s"
			% [
				str(ProfileService.has_unlocked_today_costume()),
				str(ProfileService.has_costume_red_dot()),
				str(ProfileService.is_costume_tutorial_shown())
			]
		)
	)
	print(
		(
			"[Cheat] costume_dump: DC入口态=%s can_replay_today=%s 完成日=%s max_daily=%s 最佳=%ds beat=%.1f%%"
			% [
				_daily_state_name(DailyEntryState.compute_state()),
				str(DailyEntryState.can_replay_today()),
				(
					"(never)"
					if GameState.get_daily_completed_date().is_empty()
					else GameState.get_daily_completed_date()
				),
				(
					"(never)"
					if GameState.get_max_daily_date().is_empty()
					else GameState.get_max_daily_date()
				),
				GameState.get_daily_elapsed_sec(),
				GameState.get_daily_beat_percent()
			]
		)
	)


func _cmd_costume_unlock(_args: Array[String]) -> void:
	var unlocked: bool = ProfileService.unlock_today_costume()

	var today_id: int = ProfileService.get_today_costume()
	if unlocked:
		print("[Cheat] costume_unlock: 已解锁 id=%d(24h 体验) 红点已置;对照组不影响数据、只是 UI 不显示" % today_id)
	else:
		print(
			"[Cheat] costume_unlock: 未解锁(unlock_today_costume 返 false) —— 今日已解锁过,或当日外观回落成初始外观。想重来:先 `costume_clear`,或 `costume_day <另一个id>` 换一天"
		)


func _cmd_costume_unlock_all(_args: Array[String]) -> void:
	var added: int = ProfileService.cheat_hold_all_costumes()
	var total: int = CostumeCatalog.TRIAL_COSTUME_IDS.size()
	print(
		(
			"[Cheat] costume_unlock_all: %d 只体验外观已全部持有(新增 %d、其余续期到 24h 后) 红点已置;当日解锁名额未动(解锁画面仍可验),装备未变 id=%d(换装用 `costume_equip <id>`)"
			% [total, added, ProfileService.get_costume_id()]
		)
	)


func _cmd_costume_clear(_args: Array[String]) -> void:
	ProfileService.cheat_clear_costumes()
	print(
		(
			"[Cheat] costume_clear: 体验记录/解锁日/装备/红点已清 → 装备回落 id=%d;教学标志未动(用 costume_tutorial_reset)"
			% [ProfileService.get_costume_id()]
		)
	)


func _cmd_costume_expire(_args: Array[String]) -> void:
	ProfileService.cheat_expire_costumes()
	print(
		(
			"[Cheat] costume_expire: 体验全部置过期 → 装备回落 id=%d;解锁日仍是今天(今日不能再解锁,要再来先 costume_clear)"
			% [ProfileService.get_costume_id()]
		)
	)


func _cmd_costume_day(args: Array[String]) -> void:
	var arg: String = "" if args.is_empty() else args[0].strip_edges().to_lower()
	if arg.is_empty() or arg == "off" or arg == "reset" or arg == "-1":
		CostumeCatalog.debug_day_override = -1
		DailyGamePage.debug_day_override = -1
		print(
			(
				"[Cheat] costume_day → 回真实日期:当日外观 id=%d(生效) 纯日期底座=%d day_offset=%d"
				% [
					ProfileService.get_today_costume(),
					CostumeCatalog.today_costume(),
					CostumeCatalog.today_day_offset()
				]
			)
		)
		return
	var trial_ids: Array[int] = CostumeCatalog.TRIAL_COSTUME_IDS
	var day: int = trial_ids.find(int(arg)) if arg.is_valid_int() else -1
	if day < 0:
		print(
			(
				"[Cheat] costume_day: `%s` 不是限时外观 id —— 可选 %s(初始外观 1 不是「当日外观」)。按天指定用 `daily <N>`"
				% [arg, str(trial_ids)]
			)
		)
		return
	CostumeCatalog.debug_day_override = day
	DailyGamePage.debug_day_override = day
	print(
		(
			"[Cheat] costume_day → 纯日期底座 id=%d(day_offset=%d,DC 题面同步切到那天) 生效当日外观=%d;今日解锁记录随之失配 → 可再 `costume_unlock` 一次。已开着的页面要重开才刷新"
			% [int(arg), day, ProfileService.get_today_costume()]
		)
	)


func _cmd_costume_equip(args: Array[String]) -> void:
	if args.is_empty() or not args[0].strip_edges().is_valid_int():
		print("[Cheat] costume_equip 用法: costume_equip <id>(1=初始外观;限时外观见 costume_dump 的持有列表)")
		return
	var id: int = int(args[0])
	if ProfileService.set_costume_id(id):
		print("[Cheat] costume_equip: 已装备 id=%d(皮肤=%s)" % [id, CostumeCatalog.skin_for(id)])
		return

	var reason: String = (
		"id 非法(合法 id = %d 与 %s)"
		% [CostumeCatalog.DEFAULT_COSTUME_ID, str(CostumeCatalog.TRIAL_COSTUME_IDS)]
	)
	if CostumeCatalog.is_trial(id):
		reason = "未持有,先 `costume_day %d` + `costume_unlock` 把它解锁出来" % id
	print(
		(
			"[Cheat] costume_equip: 拒绝 id=%d —— %s;当前装备=%d"
			% [id, reason, ProfileService.get_costume_id()]
		)
	)


func _cmd_costume_tutorial_reset(_args: Array[String]) -> void:
	var was_shown: bool = ProfileService.is_costume_tutorial_shown()
	ProfileService.cheat_reset_costume_tutorial()
	print(
		(
			"[Cheat] costume_tutorial_reset: 教学标志 %s → %s(下次首进 DC 应再弹一次教学)"
			% [str(was_shown), str(ProfileService.is_costume_tutorial_shown())]
		)
	)


func _cmd_costume_geom(args: Array[String]) -> void:
	var mode: String = args[0].to_lower() if args.size() > 0 else ""
	if mode == "batch_off" or mode == "batch_on":
		if not CellView.engine_supports_spine_batching():
			print(
				"[Cheat] costume_geom: 本引擎的 SpineSprite 无 batching_enabled(跨实例合批 patch 不在),合批 A/B 跳过"
			)
			print(CostumeGeomProbe.dump_perf())
			return
		var enabled: bool = mode == "batch_on"
		var changed: int = CostumeGeomProbe.set_batching(get_tree().root, enabled)
		print(
			(
				"[Cheat] costume_geom: batching_enabled=%s 已应用到 %d 个 SpineSprite"
				% [str(enabled), changed]
			)
		)
		print(CostumeGeomProbe.dump_perf())
		return
	print(CostumeGeomProbe.dump(get_tree().root))
	print(CostumeGeomProbe.dump_perf())


func _cmd_spine_probe(args: Array[String]) -> void:
	var mode: String = args[0].to_lower() if args.size() > 0 else ""
	var sprites: Array[Node] = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_class() == "SpineSprite":
			sprites.append(node)
		var kids: Array = node.get_children()
		for kid in kids:
			stack.append(kid)
	if sprites.is_empty():
		print("[Cheat] spine_probe: 场上没有 SpineSprite(未进过游戏页,或本引擎合批已整套跳过)")
		return
	if mode == "off_hidden" or mode == "off_all" or mode == "on":
		var target_mode: int = 0 if mode == "on" else 2
		var changed: int = 0
		for sprite in sprites:
			if mode == "off_hidden" and sprite.is_visible_in_tree():
				continue
			sprite.set("update_mode", target_mode)
			changed += 1
		print(
			(
				"[Cheat] spine_probe %s: %d/%d 个骨架 update_mode → %s"
				% [
					mode,
					changed,
					sprites.size(),
					"Process(恢复)" if target_mode == 0 else "Manual(停每帧更新)"
				]
			)
		)
		return
	var visible_cnt: int = 0
	var manual_cnt: int = 0
	var by_page: Dictionary = {}
	for sprite in sprites:
		if sprite.is_visible_in_tree():
			visible_cnt += 1
		if int(sprite.get("update_mode")) == 2:
			manual_cnt += 1
		var page_name: String = _spine_owner_page(sprite)
		by_page[page_name] = int(by_page.get(page_name, 0)) + 1
	var conns: Array = RenderingServer.frame_pre_draw.get_connections()
	print(
		(
			"[Cheat] spine_probe: SpineSprite 共 %d(可见 %d / 隐藏 %d / 已停更新 %d)"
			% [sprites.size(), visible_cnt, sprites.size() - visible_cnt, manual_cnt]
		)
	)
	print("  归属页: %s" % str(by_page))
	print("  frame_pre_draw 连接数 = %d(每格猫头一个,只在 cell 销毁时断开)" % conns.size())
	print("  用法: spine_probe off_hidden / off_all / on")


func _spine_owner_page(node: Node) -> String:
	const _PAGE_NAMES: Array[String] = ["GamePage", "DailyGamePage", "HomePage", "TutorialPage"]
	var walk: Node = node
	while walk != null:
		if String(walk.name) in _PAGE_NAMES:
			return String(walk.name)
		walk = walk.get_parent()
	return "?"


func _daily_state_name(state: int) -> String:
	match state:
		DailyEntryState.State.LOCKED:
			return "LOCKED(关卡未解锁)"
		DailyEntryState.State.NORMAL:
			return "NORMAL(可玩)"
		DailyEntryState.State.DONE:
			return "DONE(时钟被回拨,只toast)"
		DailyEntryState.State.REPLAY:
			return "REPLAY(今日已通关,实验组可看广重玩)"
	return "?(%d)" % state


func _format_remaining_hms(sec: int) -> String:
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func _cmd_direct_open(_args: Array[String]) -> void:
	var home_win: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home_win == null:
		Toast.popup("home 未创建,先回主页再试", self)
		return
	if not home_win.is_showing():
		Toast.popup("需先回到主页(home 当前非最上层)", self)
		return

	if not home_win.has_method("cheat_force_direct_open"):
		Toast.popup("home 缺 cheat_force_direct_open 方法,分支未合并?", self)
		return
	home_win.call("cheat_force_direct_open")


func _cmd_streak_open(_args: Array[String]) -> void:
	StreakPage.open_main()


func _cmd_streak_first(_args: Array[String]) -> void:
	_prepare_streak_preset("first")


func _cmd_streak_months(_args: Array[String]) -> void:
	_prepare_streak_preset("months")


func _prepare_streak_preset(preset: String) -> void:
	var session: RefCounted = _get_streak_fixture()
	if session == null:
		return
	var result: Dictionary = session.prepare(preset)
	print("[Cheat] 打卡场景 %s %s" % [preset, JSON.stringify(result)])
	Toast.popup(result["message"], self)


func _get_streak_fixture() -> RefCounted:
	if OS.has_feature("rel"):
		return null
	if _streak_history_session == null:
		var script: GDScript = load(
			"res://scripts/module/cheat/fixtures/streak_history_fixture_session.gd"
		)
		if script == null or not script.can_instantiate():
			push_error("[Cheat] 历史夹具加载失败")
			return null
		_streak_history_session = script.new()
		_streak_history_session.setup(StreakManager, UIManager)
	return _streak_history_session


func _can_prepare_streak() -> bool:
	var session: RefCounted = _get_streak_fixture()
	if session == null:
		return false
	var reason: String = session.mutation_guard()
	if not reason.is_empty():
		print("[Cheat] 打卡造数拒绝：%s" % reason)
		Toast.popup(reason, self)
		return false
	return true


func _refresh_streak_fixture_pages() -> void:
	var session: RefCounted = _get_streak_fixture()
	if session != null:
		session.refresh_current_streak_pages()


func _cmd_streak_history(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	if args.is_empty() or args == ["help"]:
		print(
			(
				"[Cheat] streak_history status/clear/reload\n"
				+ "  continuous <last> <N> [cycle]\n"
				+ "  ranges <last> <current> <cycle> <日期或起日..止日,多段以逗号分隔或empty>\n"
				+ "  empty\n  broken <missed> <current> [cycle]\n"
				+ "  legacy <last> <current> <cycle> [D]\n"
				+ "  pending <last> <current> <cycle> <D>\n"
				+ "日期均为YYYY-MM-DD，直接执行，无需begin；会覆盖打卡测试档，不自动备份。\n"
				+ "今天跟随本地系统日期，测试其他日期请自行修改系统时间。AB保持当前设置。\n"
				+ "clear只清历史并保留current，reload会按连胜补种；pending的冷启结算用隔离runner。"
			)
		)
		return
	var session: RefCounted = _get_streak_fixture()
	if session == null:
		return
	var result: Dictionary = session.execute(args)
	print(
		"[Cheat] streak_history %s %s" % ["OK" if result["ok"] else "FAIL", JSON.stringify(result)]
	)
	Toast.popup(result["message"], self)


func _cmd_streak_clear(_args: Array[String]) -> void:
	if not _can_prepare_streak() or not StreakManager.cheat_clear_today():
		return
	_refresh_streak_fixture_pages()
	print(
		"[Cheat] streak_clear: 今日打卡已清,can_checkin_today=%s" % str(StreakManager.can_checkin_today())
	)


func _cmd_streak_skip(_args: Array[String]) -> void:
	if not _can_prepare_streak() or not StreakManager.cheat_skip_day():
		return
	_refresh_streak_fixture_pages()
	var data: StreakData = StreakManager.get_data()
	print(
		(
			"[Cheat] streak_skip: last=%s is_broken=%s missed_days=%d (断签前 streak=%d cycle=%d 不变);should_offer(main)=%s"
			% [
				data.last_checkin_date,
				str(StreakManager.is_broken()),
				StreakManager.missed_days(),
				data.current_streak,
				data.reward_cycle_day,
				str(StreakManager.should_offer_revive(&"main"))
			]
		)
	)


func _cmd_streak_icon(args: Array[String]) -> void:
	var v: int = int(args[0]) if args.size() > 0 else DailystreakIconConfig.VALUE_WOOL
	ABTestManager.dailystreak_icon.set_debug_override(v)
	StreakManager.cheat_reset_icon_group()
	print(
		(
			"[Cheat] streak_icon=%d 已生效(生效分组=%d);重开 home / 打卡页查看"
			% [v, StreakManager.get_effective_icon_group()]
		)
	)


func _cmd_gf_fx_outside(_args: Array[String]) -> void:
	var gp: UIFrameWindow = UIManager.get_ui(UiName.GAME)
	if gp != null and gp.is_showing():
		return
	GameState.cheat_force_golden_fish_pending()
	var lv_out: int = GameState.get_current_level()
	if not ABTestManager.golden_fish_func.is_enabled():
		print("[Cheat] gf_fx(局外):已置 pending,但 golden_fish_func=0(对照组)→ 压根不出一命关。先去「AB测」页把它切成 1")
	elif lv_out < ABTestManager.golden_fish_timing.unlock_min_level():
		var gate_out: int = ABTestManager.golden_fish_timing.unlock_min_level()
		print(
			(
				"[Cheat] gf_fx(局外):已置 pending,但第 %d 关 < %d 关下限 → 插入式不生效(通关一次还会被清掉)。先 `level %d`"
				% [lv_out, gate_out, gate_out]
			)
		)
	else:
		print("[Cheat] gf_fx(局外):已置 pending —— 进第 %d 关就是插入式一命关。想连点刷动效请在局内点本命令" % lv_out)


func _cmd_gf_pending(_args: Array[String]) -> void:
	GameState.cheat_force_golden_fish_pending()
	var lv_p: int = GameState.get_current_level()
	if not ABTestManager.golden_fish_func.is_enabled():
		print("[Cheat] gf_pending 已置,但 golden_fish_func=0(对照组)→ 压根不出一命关。先去「AB测」页把它切成 1")
	elif lv_p < ABTestManager.golden_fish_timing.unlock_min_level():
		var gate_p: int = ABTestManager.golden_fish_timing.unlock_min_level()
		print(
			(
				"[Cheat] gf_pending 已置,但第 %d 关 < %d 关下限 → 插入式不生效(通关一次还会被清掉)。先 `level %d`"
				% [lv_p, gate_p, gate_p]
			)
		)
	else:
		print("[Cheat] gf_pending 已置:下一关(第 %d 关)就是插入式一命关" % lv_p)


func _cmd_gf_reset(_args: Array[String]) -> void:
	GameState.cheat_reset_golden_fish_career()
	print(
		"[Cheat] gf_reset:教学标记 / 生涯交付数 / 生涯结算数 / 题库游标 / 乱序序列与下标 全部归零,下一个一命关会是「生涯首个」(7×7 + 教学);颜色挑战的解锁门槛也随之复位"
	)
	_cmd_gf_state([])


func _cmd_gf_state(_args: Array[String]) -> void:
	var lv: int = GameState.get_current_level()
	var delivered: int = GameState.get_golden_fish_insert_delivered()
	var gf: GoldenFishFuncConfig = ABTestManager.golden_fish_func
	var shuffled: bool = gf.uses_shuffled_pick()

	var anchor: int = GameState.get_onefish_pick_switch_anchor()
	var next_rank: int = GoldenFishGate.insert_rank(GameState.get_current_strategy())
	var next_rank_txt: String = "R%d" % next_rank
	if delivered == 0 and gf.uses_random_first_rank():
		next_rank_txt = "R3 或 R4(首关随机,交付时才摇)"
	elif gf.uses_alternating_rank():
		next_rank = GoldenFishGate.insert_rank_alternating(delivered, anchor)
		next_rank_txt = "R%d(每关交替,相位锚点=%d)" % [next_rank, anchor]
	elif gf.uses_diff_ext_rank():
		var cands: Array[int] = GoldenFishGate.diff_ext_rank_candidates(
			GameState.get_current_strategy()
		)
		next_rank = cands[0]
		next_rank_txt = (
			"R%d" % next_rank if cands.size() == 1 else "候选 %s 等概(档位>3,交付时才摇)" % str(cands)
		)
	var next_sz: int = GoldenFishGate.insert_size(delivered, anchor, gf.uses_upsized_size_cycle())
	var enabled: bool = gf.is_enabled()

	var timing: GoldenFishTimingConfig = ABTestManager.golden_fish_timing
	var min_level: int = timing.unlock_min_level()
	var cur_interval: int = GoldenFishGate.effective_interval(
		GameState.get_onefish_consecutive_wins(), timing.uses_sticky_boost()
	)
	var kind: int = GoldenFishGate.resolve_kind(
		lv, GameState.get_golden_fish_pending(), enabled, min_level
	)
	var kind_txt: String = ""
	match kind:
		LevelKind.GOLDEN_FISH_INSERT:
			kind_txt = "插入式一命关(1命,不占关号)"

		LevelKind.GOLDEN_FISH_HARD:
			kind_txt = "困难关式一命关(⚠️ 现役不产生,只可能来自历史残局)"
		_:
			kind_txt = "普通主线关(3命)"

	var form_txt: String = "插入式 + 每 %d 关插 1 个 + 可跳过" % cur_interval
	var group_val: int = gf.current_group()
	var group_txt: String = ""
	match group_val:
		GoldenFishFuncConfig.VALUE_CONTROL:
			group_txt = "0=真对照组:不出一命关"
		GoldenFishFuncConfig.VALUE_ON:
			group_txt = "1=本轮对照组:%s | 依序取题 + 尺寸 8→9→10" % form_txt
		GoldenFishFuncConfig.VALUE_RANDOM:
			group_txt = "2=纯随机(PRD实验组1):%s | 乱序发牌 + 尺寸 8→9→10 + 首关随机难度" % form_txt
		GoldenFishFuncConfig.VALUE_RANK_ALT:
			group_txt = (
				"3=难度轮流(PRD实验组2):%s | 乱序发牌 + 尺寸 8→9→10 + R3/R4 每关交替(R3起手,切组归零) + 首关随机难度" % form_txt
			)
		GoldenFishFuncConfig.VALUE_SIZE_UP:
			group_txt = "4=尺寸放大(PRD实验组3):%s | 依序取题 + 尺寸 8/10/10/9/10/10 + 难度与首关同对照组" % form_txt
		GoldenFishFuncConfig.VALUE_DIFF_EXT:
			group_txt = (
				"5=难度扩展(PRD实验组4):%s | 依序取题 + 尺寸 8→9→10 + 难度按玩家档位(≤3出R3 / >3等概R3R4R5,首关同规则)"
				% form_txt
			)
		_:
			group_txt = "%d=⚠️ 代码未实现该组(PRD 规划中)→ 会静默退化成组1 行为,别用它验收" % group_val
	print("[Cheat] 一命关状态")
	print("    golden_fish_func = %s" % group_txt)

	if enabled != (group_val != GoldenFishFuncConfig.VALUE_CONTROL):
		print(
			(
				"    ⚠️ 读值不一致  = 形态判定(peek)说%s、取题读值(value)说组%d;"
				% ["开启" if enabled else "关闭", group_val]
			)
		)
		print("                    原因:本次启动还没遇到过一命关 → golden_fish_func 未染色(时机=进一命关那一刻)。")
		print("                    这是正常状态,不是 bug。用 gf_pending 出一个一命关、进去一次即一致")
	print("    第%d关的类型   = %s" % [lv, kind_txt])
	_print_gf_timing_state(timing, min_level, cur_interval)
	print(
		(
			"    频率计数      = 已过 %d 个主线关 / 每 %d 关插 1 个(攒满即触发)"
			% [GameState.get_golden_fish_streak_count(), cur_interval]
		)
	)

	var gf_pending: bool = GameState.get_golden_fish_pending()
	var pending_note: String = ""
	if gf_pending:
		if lv >= min_level:
			pending_note = "(已挂旗 → 下一关必是一命关,与频率计数攒到几无关)"
		else:
			pending_note = (
				"(已挂旗,但第%d关 < %d 关下限 → 插入式不生效,且通关一次就会被清掉;先 `level %d`)" % [lv, min_level, min_level]
			)
	print("    待玩标记      = %s%s" % ["是" if gf_pending else "否", pending_note])
	print(
		(
			"    生涯教学      = %s"
			% ["已看过(想重看用 gf_reset)" if GameState.has_golden_fish_tutorial_shown() else "还没看"]
		)
	)
	print(
		(
			"    下个插入关预计: %d×%d 难度%s(生涯已交付 %d 个,该「尺寸×难度」组合游标=%d,已排除 %d 道) | 题库现有尺寸=%s"
			% [
				next_sz,
				next_sz,
				next_rank_txt,
				delivered,
				GameState.get_onefish_index(next_sz, next_rank),
				GameState.get_onefish_used_indices(next_sz, next_rank).size(),
				str(BankData.get_onefish_sizes())
			]
		)
	)

	if shuffled:
		var printed_any: bool = false
		var pool_sizes: Array = BankData.get_onefish_sizes()
		for pool_sz: int in pool_sizes:
			var pool_ranks: Array = BankData.get_onefish_ranks(pool_sz)
			for pool_rank: int in pool_ranks:
				var shuffle_state: Dictionary = GameState.get_onefish_shuffle_debug(
					pool_sz, pool_rank
				)
				var order: Array = shuffle_state.get("order", [])
				if order.is_empty():
					continue
				var cursor: int = int(shuffle_state.get("cursor", 0))
				var upcoming: Array = order.slice(cursor, mini(cursor + 8, order.size()))

				var upcoming_1based: Array = []
				for raw_idx: int in upcoming:
					upcoming_1based.append(raw_idx + 1)
				printed_any = true
				print(
					(
						"    乱序 %d×%d R%d = 第%d轮 / 本轮已发 %d/%d 张 | 接下来题号=%s"
						% [
							pool_sz,
							pool_sz,
							pool_rank,
							int(shuffle_state.get("round", 0)) + 1,
							cursor,
							order.size(),
							str(upcoming_1based)
						]
					)
				)
		if not printed_any:
			print("    乱序抽取状态  = 还没洗过任何池(出过一个一命关后才有;切组会清空重洗)")

	var used_any: bool = false
	for pool_sz: int in BankData.get_onefish_sizes():
		for pool_rank: int in BankData.get_onefish_ranks(pool_sz):
			var used: Array = GameState.get_onefish_used_indices(pool_sz, pool_rank)
			if used.is_empty():
				continue
			var used_1based: Array = []
			for raw_idx: int in used.slice(0, mini(12, used.size())):
				used_1based.append(raw_idx + 1)
			used_any = true
			print(
				(
					"    排除表 %d×%d R%d = 已用 %d 道 | 题号=%s%s"
					% [
						pool_sz,
						pool_sz,
						pool_rank,
						used.size(),
						str(used_1based),
						"…" if used.size() > 12 else ""
					]
				)
			)
	if not used_any:
		print("    排除表        = 全空(还没交付过一命关,或刚好整池发完被清表)")

	var prev_gf: int = ABTestManager.golden_fish_func.get_prev_saved_group()

	var prev_form: int = (
		GoldenFishGate.form_from_group_value(prev_gf)
		if prev_gf >= 0
		else ABTestManager.normal_level.golden_fish_prev_group()
	)
	var cur_form: int = GoldenFishGate.current_form(enabled)
	print(
		(
			"    切形态检测    = 上次形态=%s / 本次=%d → %s"
			% [
				"-1(未记录:两个参数本次启动都还没染色)" if prev_form < 0 else str(prev_form),
				cur_form,
				(
					"下次冷启动会清一命关残余(计数/待玩旗/残局/插入关锁题)"
					if GoldenFishGate.should_clear_on_form_switch(prev_form, cur_form)
					else "无需清理"
				)
			]
		)
	)


func _cmd_cc_pending(_args: Array[String]) -> void:
	GameState.cheat_unlock_color_challenge()
	GameState.cheat_force_color_challenge_pending()

	GameState.clear_endgame_snapshot()
	GameState.clear_retry_puzzle()
	var lv: int = GameState.get_current_level()
	var group: int = ABTestManager.color_challenge_func.group_value()
	if not ColorChallengeGate.is_enabled(group):
		print(
			(
				"[Cheat] cc_pending 已置,但 color_challenge_func=%d(对照组)→ 压根不出颜色挑战。先去「AB测」页把它切成 1/2/3"
				% group
			)
		)
	elif GameState.get_color_challenge_defer_until() > 0:
		print(
			(
				"[Cheat] cc_pending 已置,但防打扰正等到第 %d 关才出(连续跳过 %d 次)。cc_pending 是直接挂旗、绕过节奏,所以下一关仍会是颜色挑战;要验节奏本身请 cc_reset 后正常玩"
				% [
					GameState.get_color_challenge_defer_until(),
					GameState.get_color_challenge_skip_count()
				]
			)
		)
	else:
		print("[Cheat] cc_pending 已置:下一关(第 %d 关)就是颜色挑战;残局与锁题已清,不会被盖回普通关" % lv)
	_cmd_cc_state([])


func _cmd_cc_reset(_args: Array[String]) -> void:
	GameState.cheat_reset_color_challenge_career()
	print("[Cheat] cc_reset:生涯交付数 / 题库游标 / 跳过次数 / 防打扰状态 全部归零,下一个颜色挑战会是「生涯首个」(7×7 + R3 + 波形图案)")
	_cmd_cc_state([])


func _cmd_cc_state(_args: Array[String]) -> void:
	var lv: int = GameState.get_current_level()
	var group: int = ABTestManager.color_challenge_func.group_value()
	var delivered: int = GameState.get_color_challenge_delivered()
	var career: int = GameState.get_golden_fish_career_count()
	var unlocked: bool = ColorChallengeGate.is_unlocked(career)
	var pending: bool = GameState.get_color_challenge_pending()
	var next_sz: int = ColorChallengeGate.cc_size(delivered)
	var next_rank: int = ColorChallengeGate.cc_rank(GameState.get_current_strategy(), delivered)
	var group_txt: String = ""
	match group:
		ColorChallengeGate.GROUP_SINGLE:
			group_txt = "1=单色系+图案,可跳过"
		ColorChallengeGate.GROUP_SINGLE_QUIET:
			group_txt = "2=单色系+图案+防打扰"
		ColorChallengeGate.GROUP_DUAL:
			group_txt = "3=双色系+图案,可跳过"
		ColorChallengeGate.GROUP_CONTROL:
			group_txt = "0=对照组:不出颜色挑战"
		_:
			group_txt = "%d=非法值(退化成对照组)" % group
	var kind: int = ColorChallengeGate.resolve_kind(lv, pending, group)
	print("[Cheat] 颜色挑战状态")
	print("    color_challenge_func = %s" % group_txt)
	print(
		(
			"    第%d关的类型   = %s"
			% [lv, "颜色挑战(3命,不占关号)" if kind == LevelKind.COLOR_CHALLENGE else "不是颜色挑战"]
		)
	)
	print(
		(
			"    解锁门槛      = 已通过或跳过 %d 个一命关 / 需 %d 个 → %s"
			% [
				career,
				ColorChallengeGate.UNLOCK_GOLDEN_FISH_COUNT,
				"已解锁" if unlocked else "**未解锁**(用 cc_pending 自动补足)"
			]
		)
	)

	var pending_note: String = ""
	if pending and not unlocked:
		pending_note = " ⚠️ 但未解锁 → 进关仍是普通关"
	elif pending and GameState.get_color_challenge_defer_until() > 0:
		pending_note = (
			" ⚠️ 防打扰另记着「第 %d 关才出」,旗是被 cheat 直接挂上的" % GameState.get_color_challenge_defer_until()
		)
	print("    待玩标记      = %s%s" % ["是" if pending else "否", pending_note])
	var since_gf: int = GameState.get_color_challenge_since_gf()
	print(
		(
			"    节奏(锚一命关)= %s / 一命关后过 %d 关就出"
			% [
				(
					"还没遇到过一命关"
					if since_gf == ColorChallengeGate.NOT_STARTED
					else "距上个一命关已过 %d 关" % since_gf
				),
				ColorChallengeGate.SINCE_GF_INTERVAL
			]
		)
	)

	var quiet_target: int = GameState.get_color_challenge_defer_until()
	print(
		(
			"    防打扰(仅组2) = 连续跳过 %d 次 / 阈值 %d → %s"
			% [
				GameState.get_color_challenge_skip_count(),
				ColorChallengeGate.QUIET_SKIP_THRESHOLD,
				(
					(
						"下次出现在第 %d 关(再玩 %d 关)"
						% [quiet_target, ColorChallengeGate.QUIET_INTERVAL_LEVELS]
					)
					if quiet_target > 0
					else "常规节奏(锚一命关)"
				)
			]
		)
	)
	print(
		(
			"    下个颜色挑战预计: %d×%d 难度R%d(生涯已交付 %d 个,该组合游标=%d,题库该组合有 %d 道)"
			% [
				next_sz,
				next_sz,
				next_rank,
				delivered,
				GameState.get_color_challenge_index(next_sz, next_rank),
				BankData.get_color_challenge_level_count(next_sz, next_rank)
			]
		)
	)
	var pattern_snap: int = GameState.get_pattern_mode_before_color_challenge()
	print(
		(
			"    色盲开关快照  = %s(当前开关=%s)"
			% [
				"无(不在颜色挑战关内)" if pattern_snap < 0 else ("进关前=开" if pattern_snap == 1 else "进关前=关"),
				"开" if GameState.is_pattern_mode_on() else "关"
			]
		)
	)
	var cc_prev: int = ABTestManager.color_challenge_func.get_prev_saved_group()
	var cc_cur: int = ColorChallengeGate.current_form(group)
	print(
		(
			"    切形态检测    = 上次分组=%s / 本次=%d → %s"
			% [
				"-1(未记录:本次启动还没染色)" if cc_prev < 0 else str(cc_prev),
				cc_cur,
				(
					"下次冷启动会清颜色挑战残余(待玩旗/残局/锁题/色盲快照)"
					if ColorChallengeGate.should_clear_on_form_switch(cc_prev, cc_cur)
					else "无需清理"
				)
			]
		)
	)


func _print_gf_timing_state(
	timing: GoldenFishTimingConfig, min_level: int, cur_interval: int
) -> void:
	var group_val: int = timing.current_group()
	var group_txt: String = ""
	match group_val:
		GoldenFishTimingConfig.VALUE_CONTROL:
			group_txt = (
				"0=对照组:Lv%d 起开放 + 每 %d 关"
				% [GoldenFishGate.INSERT_MODE_MIN_LEVEL - 1, GoldenFishGate.INSERT_INTERVAL]
			)
		GoldenFishTimingConfig.VALUE_EARLY_UNLOCK:
			group_txt = "1=解锁提前:Lv%d 起开放(频率不变)" % (GoldenFishGate.EARLY_UNLOCK_MIN_LEVEL - 1)
		GoldenFishTimingConfig.VALUE_STICKY_BOOST:
			group_txt = (
				"2=粘性加密:连续通关 %d 次 → 频率 %d 关(Skip 即恢复 %d 关)"
				% [
					GoldenFishGate.STREAK_TRIGGER,
					GoldenFishGate.STICKY_INTERVAL,
					GoldenFishGate.INSERT_INTERVAL
				]
			)
		GoldenFishTimingConfig.VALUE_SKIP_PENALTY:
			group_txt = (
				"3=拒绝降频:连续 Skip %d 次 → 抑制下一次投放(等效 %d 关;通关即恢复)"
				% [GoldenFishGate.STREAK_TRIGGER, GoldenFishGate.INSERT_INTERVAL * 2]
			)
		_:
			group_txt = "%d=⚠️ 代码未实现该组 → 会退化成对照组的门槛与频率" % group_val
	print("    golden_fish_timing = %s" % group_txt)
	var boosted: bool = cur_interval != GoldenFishGate.INSERT_INTERVAL
	print(
		(
			"    解锁门槛/频率 = 第 %d 关起 / 当前每 %d 关%s"
			% [min_level, cur_interval, "(加密生效中)" if boosted else ""]
		)
	)
	var suppressed: bool = GameState.is_onefish_spawn_suppressed()
	print(
		(
			"    一命关连续态  = 连续通关 %d 次 / 连续Skip %d 次 / 抑制标记=%s%s"
			% [
				GameState.get_onefish_consecutive_wins(),
				GameState.get_onefish_consecutive_skips(),
				"是" if suppressed else "否",
				"(下一次投放会放行并清标记)" if suppressed else ""
			]
		)
	)


func _cmd_streak_6(_args: Array[String]) -> void:
	if not _can_prepare_streak() or not StreakManager.cheat_setup_six_days():
		return
	_refresh_streak_fixture_pages()
	print("[Cheat] streak_6: 6 天已打 + 今未打,今天 do_checkin 触发满 7 发奖")


func _cmd_streak_broken_6(_args: Array[String]) -> void:
	if not _can_prepare_streak() or not StreakManager.cheat_setup_broken(1, 6):
		return
	_refresh_streak_fixture_pages()
	print(
		(
			"[Cheat] streak_broken_6: 6天已打+断签1天+今日未打卡(can_checkin=%s);is_broken=%s should_offer(main)=%s"
			% [
				str(StreakManager.can_checkin_today()),
				str(StreakManager.is_broken()),
				str(StreakManager.should_offer_revive(&"main"))
			]
		)
	)


func _cmd_streak_set(args: Array[String]) -> void:
	var days: int = maxi(1, args[0].to_int()) if args.size() > 0 else 1
	if not _can_prepare_streak() or not StreakManager.cheat_set_days(days):
		return
	_refresh_streak_fixture_pages()
	print("[Cheat] streak_set: 已打卡到第 %d 天(今日已打卡)" % StreakManager.get_data().current_streak)


func _cmd_streak_at(args: Array[String]) -> void:
	if not _can_prepare_streak():
		return
	var minute: int = _parse_hhmm(args[0] if args.size() > 0 else "5:30")
	var cfg: DailyStreakEncourageConfig = ABTestManager.daily_streak_encourage
	if args.size() > 1:
		cfg.set_debug_override(int(args[1]))
	var result: Dictionary = StreakManager.cheat_checkin_at(minute)
	if result.is_empty():
		return

	var info: Dictionary = StreakEncourageData.resolve(
		minute / 60, minute % 60, cfg.uses_top_percent()
	)
	var expect: String
	if not cfg.is_enabled():
		expect = "不显示(组0 对照)"
	elif not bool(info.get("visible", false)):
		expect = "不显示(该时刻在本组文案表外 → 按约定回落对照组布局)"
	else:
		expect = (
			"slot=%d 带猫=%s  标题=%s  文案=%s"
			% [
				int(info["slot"]),
				str(cfg.has_cat()),
				tr(String(info["name_key"])),
				tr(String(info["body_key"]))
			]
		)
	print(
		(
			"[Cheat] streak_at %02d:%02d  组=%d  streak=%d\n         预期鼓励条: %s"
			% [
				minute / 60,
				minute % 60,
				int(cfg.value()),
				StreakManager.get_display_streak(),
				expect
			]
		)
	)
	StreakPage.open_settle()


static func _parse_hhmm(s: String) -> int:
	var parts: PackedStringArray = s.split(":")
	var h: int = clampi(int(parts[0]), 0, 23)
	var mi: int = clampi(int(parts[1]), 0, 59) if parts.size() > 1 else 0
	return h * 60 + mi


func _cmd_streak_broken(args: Array[String]) -> void:
	var missed: int = args[0].to_int() if args.size() > 0 else 1
	var streak: int = args[1].to_int() if args.size() > 1 else 5
	if not _can_prepare_streak() or not StreakManager.cheat_setup_broken(missed, streak):
		return
	_refresh_streak_fixture_pages()
	print(
		(
			"[Cheat] streak_broken: 断 %d 天 / 断前 streak=%d;is_broken=%s should_offer(main)=%s (streak_protect 已固化,断天数在补签窗口内即命中)"
			% [
				missed,
				streak,
				str(StreakManager.is_broken()),
				str(StreakManager.should_offer_revive(&"main"))
			]
		)
	)


func _cmd_robot_dump(_args: Array[String]) -> void:
	RankActivityManager.cheat_dump_robots(ABTestManager.rank_state.window_sec())


func _cmd_rank_open(_args: Array[String]) -> void:
	RankActivityManager.cheat_open()
	UIManager.show_ui(UiName.HOME)
	print(
		(
			"[Cheat] rank_open: state=%d group=%d period=%d open_not_joined=%s(已重载主页触发开启弹窗;OPEN_NOT_JOINED 即会弹,参与后不再弹)"
			% [
				RankActivityManager.get_state(),
				RankActivityManager.get_group(),
				RankActivityManager.get_period_count(),
				RankActivityManager.is_open_not_joined()
			]
		)
	)


func _cmd_rank_like_reset(_args: Array[String]) -> void:
	RankActivityManager.cheat_reset_rank_likes()
	print("[Cheat] rank_like_reset: 当前活动期点赞与首次上榜豁免数据已重置")


func _cmd_rank_gift(args: Array[String]) -> void:
	var place: int = clampi(int(args[0]) if args.size() > 0 else 1, 1, 3)
	var items: Array = RankActivityConfig.reward_items(place, RandomNumberGenerator.new())
	var uid: int = AwardManager.dispatch(
		items, AwardManager.DisplayType.RANK_GIFT, "cheat", "cheat"
	)
	if uid < 0:
		print("[Cheat] rank_gift: dispatch 失败")
		return

	var info: PlayerInfo = ProfileService.get_player_info()
	var top3: Array = [info, info, info]
	var win_count: int = (
		(maxi(0, ProfileService.get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID)) + 1)
		if place == 1
		else place
	)
	AwardManager.show_award(uid, {"top3_infos": top3, "place": place, "win_count": win_count})
	print("[Cheat] rank_gift: RANK_GIFT place=%d 发 %d 项, uid=%d" % [place, items.size(), uid])


func _cmd_rank_lock_frame(_args: Array[String]) -> void:
	ProfileService.cheat_revoke_frame(ProfileCatalog.FIRST_PLACE_FRAME_ID)
	print(
		"[Cheat] rank_lock_frame: 第一名头像框已设为未获得 (frame_id=%d)" % ProfileCatalog.FIRST_PLACE_FRAME_ID
	)


func _cmd_rank_frame_wins(args: Array[String]) -> void:
	var n: int = maxi(0, int(args[0])) if args.size() > 0 else 0
	ProfileService.cheat_revoke_frame(ProfileCatalog.FIRST_PLACE_FRAME_ID)
	if n > 0:
		ProfileService.grant_frame(ProfileCatalog.FIRST_PLACE_FRAME_ID, n)
	print(
		(
			"[Cheat] rank_frame_wins: 第一名框统计次数设为 %d(max_unlocked_form=%d)"
			% [ProfileService.get_first_place_wins(), ProfileService.get_max_unlocked_form()]
		)
	)


func _cmd_rank_frame_form(args: Array[String]) -> void:
	if args.is_empty():
		print(
			"[Cheat] rank_frame_form: 需要参数 <f>(0-%d)" % (ProfileCatalog.FIRST_FRAME_FORM_COUNT - 1)
		)
		return
	var form: int = int(args[0])
	if not ProfileCatalog.is_valid_form(form):
		print(
			(
				"[Cheat] rank_frame_form: form=%d 不合法(合法范围 0-%d)"
				% [form, ProfileCatalog.FIRST_FRAME_FORM_COUNT - 1]
			)
		)
		return
	var snapshot: Dictionary = ProfileService.export_cloud_data()
	snapshot["frame_form"] = form
	ProfileService.merge_cloud_data(snapshot, MergeContext.from_comparison(true))
	print(
		(
			"[Cheat] rank_frame_form: 强制装备 form=%d(跳过解锁校验,wins 未变=%d)"
			% [ProfileService.get_frame_form(), ProfileService.get_first_place_wins()]
		)
	)


func _cmd_rank_frame_reset_backfill(_args: Array[String]) -> void:
	var snapshot: Dictionary = ProfileService.export_cloud_data()
	snapshot["frame_tier_backfill_done"] = false
	snapshot["frame_tier_presented_form"] = -1
	ProfileService.merge_cloud_data(snapshot, MergeContext.from_comparison(true))
	print("[Cheat] rank_frame_reset_backfill: 补发兼容标记与已表现形态已清，可重新复测首登补发弹窗")


func _cmd_rank_frame_dump(_args: Array[String]) -> void:
	var wins: int = ProfileService.get_first_place_wins()
	var max_form: int = ProfileService.get_max_unlocked_form()
	var equipped: int = ProfileService.get_frame_form()
	var backfill_done: bool = ProfileService.is_frame_tier_backfill_done()
	var now: int = int(Time.get_unix_time_from_system())
	var tz_bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var period_index: int = RankActivityPeriod.global_period_index(
		now, tz_bias_sec, RankActivityConfig.GLOBAL_T0_LOCAL_DAY
	)
	var period_count: int = period_index + 1

	var tiered_ab: bool = ABTestManager.rank_1st_frame.is_enabled()
	var tiered: bool = RankActivityManager._first_frame_tiered

	var player_period: int = RankActivityManager.get_period_count() + 1
	var badge_table: Array = (
		RankActivityConfig.build_first_frame_badge_table(period_count, true) if tiered else []
	)
	var mismatch: String = ""
	if tiered_ab != tiered:
		mismatch = (
			"  ⚠两份不一致:榜单/领奖台仍按 tiered=%s 渲染。回一次首页或重跑 `ab rank_1st_frame <v>` 即可同步" % str(tiered)
		)
	print(
		(
			"[Cheat] rank_frame_dump: wins=%d max_unlocked_form=%d equipped_form=%d backfill_done=%s global_period_count(now)=%d 玩家历经期数+1=%d tiered(AB现值)=%s tiered(manager注入值、榜单真正用的)=%s%s"
			% [
				wins,
				max_form,
				equipped,
				backfill_done,
				period_count,
				player_period,
				tiered_ab,
				tiered,
				mismatch
			]
		)
	)
	if tiered:
		print(
			(
				"[Cheat] rank_frame_dump: badge_table(实验组权重表,按全局期数 %d 构)=%s"
				% [period_count, str(badge_table)]
			)
		)
	else:
		print(
			(
				"[Cheat] rank_frame_dump: badge_table=[] (对照组不注入表) → 角标走现网 random(1, %d)"
				% player_period
			)
		)
	var robot_lines: Array = []
	for item in RankActivityManager.get_rank_infos():
		var pi: PlayerInfo = item.player_info
		if pi == null or pi.is_self():
			continue
		if pi.frame == null or pi.frame.id != ProfileCatalog.FIRST_PLACE_FRAME_ID:
			continue
		robot_lines.append(
			"%s: badge=%d->form=%d" % [pi.nickname, pi.frame.acquired_count, pi.frame.form]
		)
	print("[Cheat] rank_frame_dump: 榜内戴第一名框机器人(badge->form)=%s" % str(robot_lines))


func _cmd_comeback_show(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.COMEBACK_WELCOME, {"preview": true})
	print("[Cheat] comeback_show: 已弹出欢迎表演预览")


func _cmd_comeback_returnee(args: Array[String]) -> void:
	var days_ago: int = int(args[0]) if args.size() >= 1 else 4
	var group: int = int(args[1]) if args.size() >= 2 else ComebackFuncConfig.VALUE_WELCOME
	GameState.cheat_set_last_login_days_ago(days_ago)
	ComebackCheat.arm_next_cold_start(group)
	var hint: String = "离开 %d 天 + 组 %d,杀进程重开即可测" % [days_ago, group]
	if days_ago < ComebackGate.RETURNEE_GAP_DAYS:
		hint += "(不足 %d 天,不会演)" % ComebackGate.RETURNEE_GAP_DAYS
	print("[Cheat] comeback_returnee: %s" % hint)
	Toast.popup(hint, self)


func _peekaboo_home() -> Node:
	var home_win: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home_win == null or not home_win.is_showing():
		Toast.popup("需先回到主页再用 peekaboo 命令", self)
		return null
	if not home_win.has_method("refresh_peekaboo_cat"):
		Toast.popup("home 未接躲猫猫(refresh_peekaboo_cat 缺失)", self)
		return null
	return home_win


func _cmd_peekaboo(args: Array[String]) -> void:
	var home_win: Node = _peekaboo_home()
	if home_win == null:
		return
	var d: PeekabooData = PeekabooManager._data
	var prop: int = (
		int(args[0])
		if args.size() >= 1 and args[0].is_valid_int()
		else randi() % PeekabooRules.PROP_COUNT
	)
	var pos: int = (
		int(args[1])
		if args.size() >= 2 and args[1].is_valid_int()
		else randi() % PeekabooRules.POS_COUNT
	)
	d.prop_index = posmod(prop, PeekabooRules.PROP_COUNT)
	d.pos_index = posmod(pos, PeekabooRules.POS_COUNT)
	d.cat_present = true
	d.interacted = false

	PeekabooManager._session_evaluated = false
	PeekabooManager._save()
	home_win.call("refresh_peekaboo_cat")
	print(
		(
			"[Cheat] peekaboo: 强制出猫 prop=%d pos=%d group=%d(0=对照组不发奖) claimed_today=%s"
			% [
				d.prop_index,
				d.pos_index,
				int(ABTestManager.peekaboo_cat.peek_value()),
				PeekabooManager.get_cat_state().get("claimed_today", false)
			]
		)
	)


func _cmd_peekaboo_reset(_args: Array[String]) -> void:
	var d: PeekabooData = PeekabooManager._data
	d.claimed_date = ""
	d.interacted = false
	PeekabooManager._session_evaluated = false
	PeekabooManager._save()
	var home_win: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home_win != null and home_win.is_showing() and home_win.has_method("refresh_peekaboo_cat"):
		home_win.call("refresh_peekaboo_cat")
	print('[Cheat] peekaboo_reset: 当日额度已清(claimed_date=""),下次进主页重新判定出猫')


func _cmd_peekaboo_group(args: Array[String]) -> void:
	var g: int = int(args[0]) if args.size() >= 1 and args[0].is_valid_int() else 1
	g = clampi(g, 0, 2)
	ABTestManager.peekaboo_cat.set_debug_override(g)
	PeekabooManager._session_evaluated = false
	PeekabooManager.evaluate_on_cold_start()
	var home_win: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home_win != null and home_win.is_showing() and home_win.has_method("refresh_peekaboo_cat"):
		home_win.call("refresh_peekaboo_cat")
	print(
		(
			"[Cheat] peekaboo_group: 已切组=%d(运行时覆盖,杀端失效) 重判后 cat_state=%s"
			% [g, str(PeekabooManager.get_cat_state())]
		)
	)


func _cmd_peekaboo_dump(_args: Array[String]) -> void:
	var group: int = int(ABTestManager.peekaboo_cat.peek_value())
	var st: Dictionary = PeekabooManager.get_cat_state()
	var rank_state: int = RankActivityManager.get_state()
	var grants: bool = PeekabooRules.grants_reward(rank_state)
	var claimed: bool = bool(st.get("claimed_today", false))
	print(
		(
			"[Cheat] peekaboo_dump: group=%d(0对照/1送1鱼干/2弹窗) has_peekaboo=%s needs_ad_popup=%s"
			% [
				group,
				ABTestManager.peekaboo_cat.has_peekaboo(),
				ABTestManager.peekaboo_cat.needs_ad_popup()
			]
		)
	)
	print(
		(
			"[Cheat] peekaboo_dump: 落盘态 present=%s prop=%d pos=%d claimed_today=%s (claimed_date=%s)"
			% [
				st.get("present", false),
				int(st.get("prop_index", 0)),
				int(st.get("pos_index", 0)),
				claimed,
				(
					"(never)"
					if PeekabooManager._data.claimed_date.is_empty()
					else PeekabooManager._data.claimed_date
				)
			]
		)
	)
	print(
		(
			"[Cheat] peekaboo_dump: 发奖判定 = rank已开启(%s, state=%d) 且 当日未领(%s) 且 组非对照(%s) → %s；本次应发 %d/%d 条(不看广/看广)"
			% [
				grants,
				rank_state,
				not claimed,
				group != PeekabooRules.GROUP_OFF,
				grants and not claimed and group != PeekabooRules.GROUP_OFF,
				PeekabooRules.fish_count(group, false),
				PeekabooRules.fish_count(group, true)
			]
		)
	)
	var home_win: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home_win != null and home_win.has_method("get_rank_entry_center"):
		print(
			(
				"[Cheat] peekaboo_dump: 鱼干飞入落点=%s (Vector2.ZERO = 三形态卡都不可见、会跳过飞入段) has_home_entry=%s"
				% [
					str(home_win.call("get_rank_entry_center")),
					RankActivityManager.has_home_entry()
				]
			)
		)


func _cmd_peekaboo_pos(args: Array[String]) -> void:
	var home_win: Node = _peekaboo_home()
	if home_win == null:
		return
	var pos: int = int(args[0]) if args.size() >= 1 and args[0].is_valid_int() else 0
	_peekaboo_force_pos(home_win, posmod(pos, PeekabooRules.POS_COUNT))


func _cmd_peekaboo_next(_args: Array[String]) -> void:
	var home_win: Node = _peekaboo_home()
	if home_win == null:
		return
	var next_pos: int = posmod(PeekabooManager._data.pos_index + 1, PeekabooRules.POS_COUNT)
	_peekaboo_force_pos(home_win, next_pos)


func _peekaboo_force_pos(home_win: Node, pos: int) -> void:
	var d: PeekabooData = PeekabooManager._data
	d.pos_index = pos
	d.cat_present = true
	d.interacted = false
	PeekabooManager._session_evaluated = true
	PeekabooManager._save()
	home_win.call("refresh_peekaboo_cat")
	var cell: Control = home_win.call("get_peekaboo_cell") as Control
	var rect_text: String = str(cell.get_global_rect()) if cell != null else "(cell 为空)"
	print(
		(
			"[Cheat] peekaboo_pos: pos=%d/%d prop=%d 热区=%s"
			% [pos, PeekabooRules.POS_COUNT - 1, d.prop_index, rect_text]
		)
	)


func _cmd_peekaboo_boxes(_args: Array[String]) -> void:
	var home_win: Node = _peekaboo_home()
	if home_win == null:
		return
	const OVERLAY_NAME: String = "_CheatPeekabooBoxes"
	var existing: Node = home_win.get_node_or_null(OVERLAY_NAME)
	if existing != null:
		existing.queue_free()
		print("[Cheat] peekaboo_boxes: 已清掉落点框")
		return

	var d: PeekabooData = PeekabooManager._data
	var saved_pos: int = d.pos_index
	var saved_present: bool = d.cat_present
	var saved_interacted: bool = d.interacted
	d.cat_present = true
	d.interacted = false
	PeekabooManager._session_evaluated = true

	var rects: Array[Rect2] = []
	for pos in PeekabooRules.POS_COUNT:
		d.pos_index = pos
		home_win.call("refresh_peekaboo_cat")
		var cell: Control = home_win.call("get_peekaboo_cell") as Control
		rects.append(cell.get_global_rect() if cell != null else Rect2())

	d.pos_index = saved_pos
	d.cat_present = saved_present
	d.interacted = saved_interacted
	home_win.call("refresh_peekaboo_cat")

	var overlay := Control.new()
	overlay.name = OVERLAY_NAME
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 4096
	(home_win as Node).add_child(overlay)
	for index in rects.size():
		var rect: Rect2 = rects[index]
		var frame := ReferenceRect.new()
		frame.editor_only = false
		frame.border_color = Color(1.0, 0.15, 0.15, 0.9)
		frame.border_width = 4.0
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.global_position = rect.position
		frame.size = rect.size
		overlay.add_child(frame)
		var tag := Label.new()
		tag.text = "pos%d" % index
		tag.add_theme_font_size_override("font_size", 40)
		tag.add_theme_color_override("font_color", Color(0.85, 0.05, 0.05))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.global_position = rect.position + Vector2(4.0, -46.0)
		overlay.add_child(tag)
		print(
			(
				"[Cheat] peekaboo_boxes: pos%d 热区 x=%d..%d y=%d..%d"
				% [
					index,
					int(rect.position.x),
					int(rect.end.x),
					int(rect.position.y),
					int(rect.end.y)
				]
			)
		)
	print("[Cheat] peekaboo_boxes: 已画 %d 个落点框（再点一次清掉；落盘态未改动）" % rects.size())


func _cmd_rank_rise(args: Array[String]) -> void:
	var from_rank: int = int(args[0]) if args.size() >= 1 else 15
	var to_rank: int = int(args[1]) if args.size() >= 2 else 3
	if from_rank <= to_rank or to_rank < 1:
		print("[Cheat] rank_rise: from_rank(%d) 必须 > to_rank(%d) >= 1" % [from_rank, to_rank])
		return

	var total: int = int(args[2]) if args.size() >= 3 else maxi(from_rank + 5, 30)
	total = maxi(total, from_rank)
	var mock_infos: Array = []
	var self_pinfo: PlayerInfo = ProfileService.get_player_info()
	for i: int in range(total):
		var rank: int = i + 1
		var info := RankInfo.new()
		info.rank = rank
		info.score = (total - rank + 1) * 100
		if rank == to_rank:
			info.player_info = self_pinfo
		else:
			var pi := PlayerInfo.new()
			pi.nickname = "Player_%d" % rank
			pi.player_id = "robot_%d" % rank
			pi.is_robot = true
			pi.avatar_id = (rank % 8) + 1
			info.player_info = pi
		mock_infos.append(info)
	var advance: int = from_rank - to_rank

	(
		UIManager
		. show_ui(
			(
				UiName.RANK_ACTIVITY_CHANGE_V2
				if ABTestManager.podium_per_game.is_list_podium_style()
				else UiName.RANK_ACTIVITY_CHANGE
			),
			{
				"mock_infos": mock_infos,
				"advance_places": advance,
			}
		)
	)
	print("[Cheat] rank_rise: %d → %d (上升 %d 名, 榜单 %d 人)" % [from_rank, to_rank, advance, total])


func _cmd_rank_spread(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_spread: 排名活动未开启(先 rank_open)")
		return
	var gap: int = int(args[0]) if args.size() >= 1 else 3
	var top: int = int(args[1]) if args.size() >= 2 else 0
	if gap < 2:
		print("[Cheat] rank_spread: gap(%d) 太小,已按 2 处理(gap=1 相邻名次无整数空隙,插不进去)" % gap)
	print("[Cheat] rank_spread: 铺开前 %s" % _fmt_rank_scores())
	var r: Dictionary = RankActivityManager.cheat_spread_robot_scores(gap, top)
	if not bool(r.get("ok", false)):
		return
	print("[Cheat] rank_spread: 铺开后 %s" % _fmt_rank_scores())
	print("[Cheat] rank_spread: %s" % _fmt_insertable())
	print(
		(
			"[Cheat] rank_spread: gap=%d 榜首=%d 玩家现在第 %d 名"
			% [int(r.get("gap", 0)), int(r.get("top", 0)), int(r.get("player_rank", -1))]
		)
	)
	print("[Cheat]    机器人已改为固定分(不再随时间涨)、陪伴追赶已关闭 → 分布稳定,可反复 rank_win_to。")


func _fmt_rank_scores() -> String:
	var infos: Array = RankActivityManager.get_rank_infos()
	var parts: Array[String] = []
	for i: int in range(mini(8, infos.size())):
		var ri = infos[i]
		parts.append("%d%s" % [ri.score, "(玩家)" if not ri.player_info.is_robot else ""])
	return "分数: " + "/".join(parts)


func _fmt_insertable() -> String:
	var infos: Array = RankActivityManager.get_rank_infos()
	var bots: Array[int] = []
	for ri in infos:
		if ri.player_info.is_robot:
			bots.append(ri.score)
	if bots.size() < 2:
		return "可精确插入的名次: 机器人不足 2 个,无法判定"
	var ok: Array[String] = []
	for target: int in range(2, mini(8, bots.size() + 1)):
		if bots[target - 2] - bots[target - 1] >= 2:
			ok.append(str(target))
	if ok.is_empty():
		return "可精确插入的名次: 无(2-7 名相邻分差都 <2,先跑 rank_spread)"
	return "可精确插入的名次: %s (第1名恒可插)" % "/".join(ok)


func _cmd_rank_win_to(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_win_to: 排名活动未开启(先 rank_open)")
		return
	var to_rank: int = int(args[0]) if args.size() >= 1 else 2
	var from_rank: int = int(args[1]) if args.size() >= 2 else to_rank + 3
	if to_rank < 1:
		print("[Cheat] rank_win_to: to_rank(%d) 必须 >= 1" % to_rank)
		return
	if from_rank <= to_rank:
		print(
			(
				"[Cheat] rank_win_to: from_rank(%d) 必须 > to_rank(%d)，否则名次没上升(advance=0)、不会弹登领奖台"
				% [from_rank, to_rank]
			)
		)
		return
	RankActivityManager.cheat_pin_next_win(to_rank, from_rank)
	print(
		(
			"[Cheat] rank_win_to: 起点名次=%d(实际=%d) → 本局通关后升到第 %d 名 (advance=%d)"
			% [from_rank, RankActivityManager.get_player_rank(), to_rank, from_rank - to_rank]
		)
	)

	var pg: int = ABTestManager.podium_per_game.value()
	if not ABTestManager.podium_per_game.has_per_game_podium():
		print("[Cheat] ⚠️ podium_per_game=%d 未开启每局登台(需 1)：只会看到名次上浮，不弹登领奖台" % pg)
	elif to_rank > ABTestManager.podium_per_game.podium_rank_limit():
		print(
			(
				"[Cheat] ⚠️ 目标名次 %d 超出本组登台名次上限 %d：只会看到名次上浮，不弹登领奖台"
				% [to_rank, ABTestManager.podium_per_game.podium_rank_limit()]
			)
		)


func _cmd_rank_score(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_score: 排名活动未开启(先 rank_open)")
		return
	var val: int = int(args[0]) if args.size() > 0 else 100
	RankActivityManager.cheat_set_score(val)
	print(
		(
			"[Cheat] rank_score: collect_total=%d 名次=%d"
			% [RankActivityManager.get_collect_total(), RankActivityManager.get_player_rank()]
		)
	)


func _cmd_rank_streak(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_streak: 排名活动未开启(先 rank_open)")
		return
	var streak: int = int(args[0]) if args.size() > 0 else 3
	var refreeze: bool = args.size() > 1 and args[1] == "1"
	if refreeze:
		RankActivityManager.set_streak_rule(
			ABTestManager.rank_win.streak_table(),
			ABTestManager.rank_win.boost_spec(),
			ABTestManager.rank_win.x_base_rule()
		)
	RankActivityManager.cheat_set_streak(streak, refreeze)
	print(
		(
			"[Cheat] rank_streak: 连胜=%d 下一局 ×%d 档位表=%s"
			% [
				RankActivityManager.get_win_streak(),
				RankActivityManager.get_next_multiplier(),
				RankActivityManager.get_streak_table()
			]
		)
	)


func _cmd_rank_set_rank(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_set_rank: 排名活动未开启(先 rank_open)")
		return
	var n: int = int(args[0]) if args.size() > 0 else 3

	RankActivityManager.cheat_set_rank(n)
	RankActivityManager.cheat_end_in(1)
	print("[Cheat] rank_set_rank: 目标名次=%d, 1s 后结束(实际名次见 [RankActivity] 日志)" % n)


func _cmd_rank_end10(args: Array[String]) -> void:
	if not RankActivityManager.is_running():
		print("[Cheat] rank_end10: 排名活动未开启(先 rank_open)")
		return
	var sec: int = int(args[0]) if args.size() > 0 else 10
	RankActivityManager.cheat_end_in(sec)
	print(
		"[Cheat] rank_end10: %ds 后结束, remaining=%d" % [sec, RankActivityManager.get_remaining_sec()]
	)


func _cmd_rank_solo_podium(args: Array[String]) -> void:
	var n: int = int(args[0]) if args.size() > 0 else RankActivityConfig.END_SOLO_PODIUM_RANK_MIN
	n = clampi(
		n, RankActivityConfig.END_SOLO_PODIUM_RANK_MIN, RankActivityConfig.END_SOLO_PODIUM_RANK_MAX
	)
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": n})
	print("[Cheat] rank_solo_podium: 预览名次=%d(仅表现,未改结算状态)" % n)


func _cmd_bank(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.BANK)


func _cmd_latest(args: Array[String]) -> void:
	var count: int = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 30
	UIManager.show_ui(UiName.RECENT_LEVELS, {"latest_count": count})


func _cmd_fastjump(args: Array[String]) -> void:
	var count: int = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 30
	var summary: Dictionary = _run_fastjump(maxi(1, count))
	var final_level: int = int(summary["final_level"])
	UIManager.show_ui(UiName.GAME, {"level_index": final_level})

	UIManager.hide_ui(UiName.HOME)


func _run_fastjump(count: int) -> Dictionary:
	count = maxi(1, count)
	var start_level: int = GameState.get_current_level()
	var done: int = 0
	var select_usec: int = 0
	var won_usec: int = 0
	RegionClusterSignature.reset_stats()
	var wall_t0: int = Time.get_ticks_usec()
	for i: int in range(count):
		var lv: int = start_level + i
		var pre_cat_pend: Dictionary = GameState.consume_pre_cat_pending()
		var t0: int = Time.get_ticks_usec()
		var entry: Dictionary = LevelSelector.select(lv, 0, pre_cat_pend)
		select_usec += Time.get_ticks_usec() - t0
		if entry.is_empty():
			push_error("[fastjump] Lv%d 取题失败,提前终止(已完成 %d/%d)" % [lv, done, count])
			break
		var sz: int = int(entry.get("size", 0))
		if sz == 0:
			sz = SizeModifier.get_size(lv)
		var puzzle_id: String = str(entry.get("_puzzle_id", ""))
		if not puzzle_id.is_empty():
			PuzzleSessionTracker.record(puzzle_id, lv)
		var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
		var rank: int = int(entry.get("_delivery_rank", entry.get("_bank_rank", 1)))
		RecentLevelDebugTracker.record(
			lv, sz, rank, entry.get("regionMap", []), source, str(entry.get("_iso_check", ""))
		)
		var t1: int = Time.get_ticks_usec()
		_prepare_fastjump_elo_v2(lv, entry)
		GameState.on_level_won(lv)
		won_usec += Time.get_ticks_usec() - t1
		done += 1
	var wall_usec: int = Time.get_ticks_usec() - wall_t0
	var final_level: int = GameState.get_current_level()

	var iso_stats: Dictionary = RegionClusterSignature.get_stats()
	var compute_ms: float = int(iso_stats["compute_usec"]) / 1000.0
	var match_ms: float = int(iso_stats["match_usec"]) / 1000.0
	print(
		(
			(
				"[fastjump] 完成 %d/%d 关,当前关卡=%d\n"
				+ "  总耗时 %.1fms = 取题(select) %.1fms + 结算落盘(on_level_won) %.1fms + 其它 %.1fms\n"
				+ "  同构判定(算法本身): compute_signatures 调 %d 次共 %.1fms, has_isomorphic_match 调 %d 次共 %.1fms(命中拒绝 %d 次)"
			)
			% [
				done,
				count,
				final_level,
				wall_usec / 1000.0,
				select_usec / 1000.0,
				won_usec / 1000.0,
				(wall_usec - select_usec - won_usec) / 1000.0,
				int(iso_stats["compute_calls"]),
				compute_ms,
				int(iso_stats["match_calls"]),
				match_ms,
				int(iso_stats["match_hits"]),
			]
		)
	)
	return {"completed": done, "final_level": final_level}


func _prepare_fastjump_elo_v2(level_num: int, entry: Dictionary) -> void:
	if not ABTestManager.normal_level.is_elo_v2_active():
		return
	var puzzle_id: String = str(entry.get("_puzzle_id", ""))
	if puzzle_id.is_empty():
		push_error("[fastjump] ELO simulation missing delivered puzzle ID, lv=%d" % level_num)
		return
	var size: int = int(entry.get("_delivery_size", entry.get("size", 0)))
	var rank: int = int(entry.get("_delivery_rank", entry.get("_bank_rank", 0)))
	var eligible: bool = (
		level_num >= 21
		and rank in [3, 4, 5]
		and not LevelSelector.is_super_hard_level(level_num)
		and bool(entry.get("is_elo_delivery", false))
	)
	var style: Dictionary = entry.get("elo_v2_style_vector", {}).duplicate(true)
	style["style_size"] = size
	GameState.abandon_elo_v2_attempt(level_num)
	GameState.begin_elo_v2_attempt(
		level_num, puzzle_id, rank, float(entry.get("eloRating", -1.0)), style, eligible
	)
	var simulated_time_total: int = LevelPassTimeMedian.median_sec(size, rank)
	if ABTestManager.normal_level.value() == ABTestManager.normal_level.VALUE_ELO_V2_TIME:
		simulated_time_total = floori(float(simulated_time_total) * 0.7)
	GameState.set_elo_v2_win_facts(simulated_time_total, true)
	print(
		(
			"[Level.ELO] SIMULATE group=%d lv=%d rank=%d pid=%s eligible=%s time_total=%d behavior=clean_full_hp"
			% [
				ABTestManager.normal_level.value(),
				level_num,
				rank,
				puzzle_id,
				str(eligible),
				simulated_time_total
			]
		)
	)


func _cmd_level_json(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.LEVEL_JSON_INPUT)


func _cmd_reset_rate_us(_args: Array[String]) -> void:
	GameState.reset_rate_us_shown()
	print("[Cheat] reset_rate_us → has_shown_rate_us = ", GameState.has_shown_rate_us())


func _cmd_bank_preview(args: Array[String]) -> void:
	var idx: int = clampi(int(args[0]) if args.size() > 0 else 1, 1, 9999)
	var transform: int = clampi(int(args[1]) if args.size() > 1 else 0, 0, 11)
	var pool_key: String = args[2] if args.size() > 2 else "reg_10_3"

	var parts: Array = pool_key.split("_")
	if parts.size() < 3:
		print("[bank_preview] pool 格式错误，应为 类型_尺寸_rank，如 reg_10_3")
		return
	var pool_type: String = parts[0]
	var sz: int = int(parts[1])
	var rank: int = int(parts[2])

	var levels: Array = []
	match pool_type:
		"lks":
			levels = BankData.get_lk_style_levels(sz, rank)
		"lkm":
			var all: Array = BankData.get_lk_modified_levels()
			for e in all:
				if int(e.get("size", 0)) == sz and int(e.get("maxR", e.get("r", 0))) == rank:
					levels.append(e)
		_:
			levels = BankData.get_levels(sz, rank)

	if levels.is_empty():
		print("[bank_preview] 题库为空: ", pool_key)
		return

	var entry_idx: int = (idx - 1) % levels.size()
	var entry: Dictionary = levels[entry_idx]
	var raw_solution: Array = BankData.get_solution(entry)
	var sol_1d: Array = []
	for v in raw_solution:
		sol_1d.append(int(v))
	var raw_regions: Array = BankData.get_region_map(entry)
	var int_regions: Array = []
	for row_arr in raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	if transform > 0:
		var transformed: Array = LevelData.apply_transform(int_regions, sol_1d, sz, transform)
		int_regions = transformed[0]
		sol_1d = transformed[1]
	print(
		(
			"[bank_preview] %s #%d/%d  transform=%d  sz=%d  rank=%d"
			% [pool_key, entry_idx + 1, levels.size(), transform, sz, rank]
		)
	)
	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"bank_mode": true,
				"bank_size": sz,
				"bank_rank": rank,
				"bank_index": idx,
				"bank_total": levels.size(),
				"prebuilt_regions": int_regions,
				"prebuilt_solution": sol_1d,
				"level_seed": int(entry.get("seed", entry.get("id", 0))),
				"_bank_transform": transform,
			}
		)
	)

	UIManager.hide_ui(UiName.HOME)


func _cmd_size12(args: Array[String]) -> void:
	var rank: int = clampi(int(args[0]) if args.size() > 0 else 3, 1, 5)
	var idx: int = clampi(int(args[1]) if args.size() > 1 else 1, 1, 9999)
	_cmd_bank_preview([str(idx), "0", "reg_12_%d" % rank])


func _cmd_ad_debug(_args: Array[String]) -> void:
	UniKitManager.open_ad_debug_view()


func _cmd_hide_ui(_args: Array[String]) -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		return
	const PATHS: Array[String] = [
		"Root/VBoxContainer/Header/GearBtn",
		"Root/VBoxContainer/Header/LevelLabel",
		"Root/VBoxContainer/Header/SettingsBtn",
		"Root/VBoxContainer/Header/StrategyBtn",
		"Root/VBoxContainer/Header/PrevBtn",
		"Root/VBoxContainer/Header/NextBtn",
		"Root/VBoxContainer/BottomTools",
	]

	var target_visible: bool = true
	for path: String in PATHS:
		var node: Node = page.get_node_or_null(path)
		if node != null:
			target_visible = not (node as CanvasItem).visible
			break
	for path: String in PATHS:
		var node: Node = page.get_node_or_null(path)
		if node != null:
			(node as CanvasItem).visible = target_visible


func _cmd_ui_stack(_args: Array[String]) -> void:
	print(UIManager.debug_dump_stack())


func _cmd_font_zh_old_save(_args: Array[String]) -> void:
	GameState.cheat_restore_ab_group_before_peek_migration(
		ABTestManager.font_test_zh.key, FontTestZhConfig.VALUE_YUAN_QUAN_YUAN_2TW
	)
	print("[Cheat] 已恢复 font_test_zh 旧存档并清除 peek，退出后重启可再次测试迁移")
	get_tree().quit()


func _cmd_ab_persist(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	var action: String = args[0].to_lower() if not args.is_empty() else "toggle"
	if args.size() > 1 or action not in ["on", "off", "toggle"]:
		print("[Cheat] ab_persist 用法：ab_persist <on|off|toggle>，省略参数切换开关")
		return
	var enabled: bool = (
		not DebugOverrideStore.is_enabled() if action == "toggle" else action == "on"
	)
	if not DebugOverrideStore.set_enabled(enabled):
		return
	print(
		(
			"[Cheat] AB 参数存档：%s；已有覆盖继续生效，ab <key> clear 同时清除内存和本地覆盖"
			% ["开启，后续 ab 设置立即保存" if enabled else "关闭，后续 ab 设置仅本次进程生效"]
		)
	)


## 设置或清除实验调试覆盖；特定参数还会清缓存、重置图标分组或刷新当前界面。
func _cmd_ab(args: Array[String]) -> void:
	if OS.has_feature("rel"):
		return
	if args.size() < 2:
		print("[Cheat] ab 用法: ab <key> <value|clear>  例: ab region_color 1 / ab peekaboo_cat clear")
		return
	var key: String = args[0]
	var cfg: AbConfigBase = ABTestManager.find_config(key)
	if cfg == null:
		print("[Cheat] 未知 AB 参数: ", key)
		return

	if args[1] == "clear":
		if not cfg.clear_debug_override():
			return
		if key == ABTestManager.dailystreak_icon.key:
			StreakManager.cheat_reset_icon_group()
		print("[Cheat] ab %s clear: 已清内存和本地覆盖，现在读到 %s（回真实取值链）" % [key, str(cfg.value())])
		if key == "cat_found_grid":
			_resync_cat_found_grid_dim()
		return

	var value: Variant = args[1] if typeof(cfg.default_value) == TYPE_STRING else int(args[1])
	if not cfg.set_debug_override(value, true):
		return

	if key == ABTestManager.dailystreak_icon.key:
		StreakManager.cheat_reset_icon_group()
	print(
		(
			"[Cheat] ab %s = %s（%s）"
			% [key, str(value), "已保存，重启后保留" if DebugOverrideStore.is_enabled() else "仅本次进程生效"]
		)
	)

	if key == "normal_level":
		BankSorter.clear_cache()
		print("[Cheat] normal_level 切组,BankSorter cache cleared")

	if key == "rank_1st_frame":
		var tiered: bool = ABTestManager.rank_1st_frame.is_enabled()
		RankActivityManager.set_first_frame_tiered(tiered)
		print("[Cheat] rank_1st_frame 切组,已注入 set_first_frame_tiered(%s)" % str(tiered))

	if key == "cat_found_grid":
		_resync_cat_found_grid_dim()


func _cmd_ab_debug(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.AB_DEBUG)


func _cmd_switch_popup(args: Array[String]) -> void:
	var shape: String = args[0] if args.size() > 0 else "both"
	var reward: Dictionary = {}
	match shape:
		"both":
			reward = {"hint": 1, "locate": 1}
		"hint":
			reward = {"hint": 3}
		"locate":
			reward = {"locate": 3}
		"none":
			reward = {}
		_:
			print("[Cheat] switch_popup 用法: switch_popup [both|hint|locate|none],默认 both")
			return
	(
		UIManager
		. show_ui(
			UiName.AB_SWITCH_POPUP,
			{
				"title": "DAILY_STREAK_MAJOR_UPDATE",
				"body": "COMMON_SWITCH_POPUP_DEFAULT_DESC",
				"feedback": "1",
				"reward": reward,
			}
		)
	)
	print(
		(
			"[Cheat] switch_popup %s | reward=%s | prop_position=%s → %s 在前"
			% [
				shape,
				str(reward),
				str(ABTestManager.prop_position.value()),
				"hint" if ABTestManager.prop_position.is_hint_first() else "locate",
			]
		)
	)


func _cmd_ab_tag(_args: Array[String]) -> void:
	var tag: String = ABTestManager.get_ab_dyeing_tag()
	print('[Cheat] ab_dyeing_tag = "%s"' % tag)


func _cmd_pace_reset(_args: Array[String]) -> void:
	BankSorter.clear_cache()
	print("[Cheat] BankSorter sort cache cleared")


func _cmd_dup_puzzle(args: Array[String]) -> void:
	var sz: int = clampi(int(args[0]) if args.size() > 0 else 8, 7, 12)
	var rank: int = clampi(int(args[1]) if args.size() > 1 else 4, 1, 5)
	var lk_idx: int = maxi(int(args[2]) if args.size() > 2 else 9, 0)
	var level: int = maxi(int(args[3]) if args.size() > 3 else 991, 51)

	var lv_size: int = SizeModifier.get_size(level)
	if lv_size != sz:
		print("[dup_puzzle] 关卡 %d 尺寸是 %d、与目标桶 %d 不符 —— 8x8 要取尾号 1 的关(如 991)" % [level, lv_size, sz])
		return

	var pools: Dictionary = LevelData.build_pools(sz, rank, "", false, true)
	var lk_pool: Array = pools.get("lk_mod", [])
	if lk_idx >= lk_pool.size():
		print(
			(
				"[dup_puzzle] 桶(%d,%d) 的 lk_mod 池只有 %d 条,lk_idx=%d 越界 —— 池取尽后不再走 lk_mod 分支,撞不出重复"
				% [sz, rank, lk_pool.size(), lk_idx]
			)
		)
		return

	var target: Dictionary = lk_pool[lk_idx]
	var pid: String = PuzzleDeduplicator.resolve_puzzle_id(
		target, sz, BankData.get_region_map(target)
	)

	ABTestManager.normal_level.set_debug_override(NormalLevelConfig.VALUE_FUSION_BASE)

	GameState.cheat_jump_to_level(level)
	GameState.set_current_strategy(6 if rank == 5 else rank)

	GameState.set_main_progress(sz, rank, "", {"idx": 0, "since_lk": 4, "transform": 0})
	GameState.set_lkmod_progress(sz, rank, {"idx": lk_idx})

	(
		GameState
		. finalize_selected_puzzle(
			level - 10,
			{
				"puzzle_id": pid,
				"v": UniKitManager.get_version_name(),
				"nl": NormalLevelConfig.VALUE_FUSION_BASE,
				"src": "lk_mod",
				"iso_sig": [],
				"style_hist": [],
				"style_order_z": [],
				"style_size": sz,
			},
			{}
		)
	)

	print("[dup_puzzle] 已构造 桶(%d,%d) lk_idx=%d/%d pid=%s" % [sz, rank, lk_idx, lk_pool.size(), pid])
	print(
		(
			"[dup_puzzle]   normal_level 覆写=%d 关号=%d 难度档=%d since_lk=4"
			% [NormalLevelConfig.VALUE_FUSION_BASE, level, GameState.get_current_strategy()]
		)
	)
	UIManager.show_ui(UiName.GAME, {"level_index": level})

	UIManager.hide_ui(UiName.HOME)


func _cmd_gamble_user(args: Array[String]) -> void:
	if args.size() < 1:
		print("[Cheat] usage: gamble_user <-1|0|1>  (-1=未打标 / 0=推理 / 1=赌博)")
		return
	var v: int = int(args[0])
	if v != -1 and v != 0 and v != 1:
		print("[Cheat] gamble_user: invalid value=%s (only -1/0/1 allowed)" % args[0])
		return
	if not GambleUserTag.set_value(v):
		return
	GameState.persist_user_tag_state()
	print("[Cheat] gamble_user tag = %d" % v)


func _cmd_gamble_status(_args: Array[String]) -> void:
	var snap: Dictionary = GambleUserTag.debug_snapshot()
	print("[GambleUser Status]")
	print(
		(
			"  is_gamble_user            = %d  (-1=untagged / 0=reasoning / 1=gamble)"
			% snap["is_gamble_user"]
		)
	)
	print("  gamble_update_level       = %s  (-1=本设备尚未成功更新)" % snap["gamble_update_level"])
	print(
		(
			"  _early_l1_l20_bits        = %s  (最近 L1-L20 通关的「非R2无错」bit,cap=20;size=20 全 true 判 gamble,any false 判 reasoning,size<20 跳过)"
			% str(snap["early_l1_l20_bits"])
		)
	)
	print(
		(
			"  _recent_non_easy_invalid_bits = %s  (当前批次非简单关 invalid>0;满5条重算并清空)"
			% str(snap["recent_non_easy_invalid_bits"])
		)
	)
	print(
		"  _recent_non_easy_levels   = %s  (当前批次实际参与判定的关卡号)" % str(snap["recent_non_easy_levels"])
	)
	print(
		(
			"  _recent_hard_invalid_bits = %s  (旧版 hard 窗口兼容数据，新逻辑不参与判定)"
			% str(snap["recent_hard_invalid_bits"])
		)
	)
	var r3: Vector2 = GameState.compute_11503_r3_probs()
	var r4: Vector3 = GameState.compute_11503_r4_probs()
	print("  [R3] 段派生占比: R2=%.3f%%, R3=%.3f%%" % [r3.x, r3.y])
	print("  [R4] 段派生占比: R2=%.3f%%, R3=%.3f%%, R4=%.3f%%" % [r4.x, r4.y, r4.z])
	print(
		(
			"  current_strategy          = %d (决定当前生效规则: <3 无规则 / ==3 [R3] 段 / ==4 [R4] 段)"
			% GameState.get_current_strategy()
		)
	)


func _cmd_clickdbg(args: Array[String]) -> void:
	var mode: String = args[0] if args.size() > 0 else "toggle"
	match mode:
		"on":
			_clickdbg_enabled = true
		"off":
			_clickdbg_enabled = false
		_:
			_clickdbg_enabled = not _clickdbg_enabled
	print("[ClickDbg] ", "ON" if _clickdbg_enabled else "OFF")


func _cmd_dc(args: Array[String]) -> void:
	var mode: String = args[0] if args.size() > 0 else "on"
	match mode:
		"on":
			FpsButton.dc_visible = true
		"off":
			FpsButton.dc_visible = false
		_:
			print("[CheatDC] 用法: dc on / dc off")
			return
	print("[CheatDC] ", "ON" if FpsButton.dc_visible else "OFF")


func _cmd_rec(args: Array[String]) -> void:
	await RecProbe.run(self, args)


func _cmd_rec_status(_args: Array[String]) -> void:
	print(
		(
			"[RecStatus] queue=%d history=%d session_pos=%d days_since_open=%d"
			% [
				LevelRecManager.queue_remaining(),
				LevelRecManager.get_history_count(),
				LevelRecManager._history.get_session_position(),
				ProtectScheme.days_since_first_open()
			]
		)
	)


func _cmd_rec_prefetch(_args: Array[String]) -> void:
	print("[RecPrefetch] 强制触发预取...")
	LevelRecManager.force_prefetch()


func _cmd_rec_clear(_args: Array[String]) -> void:
	LevelRecManager.clear_queue()
	print("[RecClear] 队列已清空")


## 切换并持久化数据同步开关，跨会话继续生效。
func _cmd_datasync(args: Array[String]) -> void:
	var mode: String = args[0].to_lower() if args.size() > 0 else "toggle"
	var enabled: bool
	match mode:
		"on":
			enabled = true
		"off":
			enabled = false
		_:
			enabled = not DataSyncManager.is_sync_enabled()
	DataSyncManager.set_sync_enabled(enabled)
	var state: String = "ON(启用)" if enabled else "OFF(禁用)"
	print("[DataSync] 数据同步 ", state, " (已持久化,跨 session 生效)")
	Toast.popup("数据同步: %s (已持久化)" % state, self)


func _cmd_safe_area(_args: Array[String]) -> void:
	if _safe_area_overlay != null and is_instance_valid(_safe_area_overlay):
		_safe_area_overlay.queue_free()
		_safe_area_overlay = null
		print("[Cheat] safe_area: 关闭")
		return

	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	var top_inset: float = float(safe.position.y)
	var bottom_inset: float = float(win.y - (safe.position.y + safe.size.y))
	var left_inset: float = float(safe.position.x)
	var right_inset: float = float(win.x - (safe.position.x + safe.size.x))

	var vp: Viewport = get_viewport()
	var vp_rect: Rect2 = vp.get_visible_rect()
	var scale_x: float = (vp_rect.size.x / float(win.x)) if win.x > 0 else 1.0
	var scale_y: float = (vp_rect.size.y / float(win.y)) if win.y > 0 else 1.0
	print("[safe_area] ── 坐标系诊断 ──")
	print("[safe_area] 物理像素 window_get_size = %s" % str(win))
	print("[safe_area] 物理像素 display_safe_area = %s" % str(safe))
	print(
		(
			"[safe_area] 物理 inset top=%.1f bottom=%.1f left=%.1f right=%.1f"
			% [top_inset, bottom_inset, left_inset, right_inset]
		)
	)
	print("[safe_area] 2D视口 get_visible_rect = %s" % str(vp_rect))
	print("[safe_area] scale(视口/物理) x=%.4f y=%.4f" % [scale_x, scale_y])
	print(
		(
			"[safe_area] 换算到2D的 inset top=%.1f bottom=%.1f left=%.1f right=%.1f"
			% [
				top_inset * scale_y,
				bottom_inset * scale_y,
				left_inset * scale_x,
				right_inset * scale_x
			]
		)
	)

	_log_safe_group("_safe_top", "_safe_top_baseline", top_inset, true)
	_log_safe_group("_safe_bottom", "_safe_bottom_baseline", bottom_inset, false)

	var band_top: float = maxf(top_inset, 0.0) * scale_y
	var band_bottom: float = maxf(bottom_inset, 0.0) * scale_y
	var band_left: float = maxf(left_inset, 0.0) * scale_x
	var band_right: float = maxf(right_inset, 0.0) * scale_x
	var vw: float = vp_rect.size.x
	var vh: float = vp_rect.size.y

	var layer := CanvasLayer.new()
	layer.layer = 128

	var band_color := Color(1, 0, 0, 0.35)
	_add_band(layer, Vector2(0, 0), Vector2(vw, band_top), band_color)
	_add_band(layer, Vector2(0, vh - band_bottom), Vector2(vw, band_bottom), band_color)
	_add_band(layer, Vector2(0, 0), Vector2(band_left, vh), band_color)
	_add_band(layer, Vector2(vw - band_right, 0), Vector2(band_right, vh), band_color)

	var border := Panel.new()
	border.position = Vector2(safe.position.x * scale_x, safe.position.y * scale_y)
	border.size = Vector2(safe.size.x * scale_x, safe.size.y * scale_y)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = Color(0, 1, 0, 0.9)
	border.add_theme_stylebox_override("panel", sb)
	layer.add_child(border)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 40)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 8)
	info.position = Vector2(30, band_top + 20)
	info.text = (
		"窗口(物理px): %dx%d\n安全区(物理px): pos(%d,%d) size(%dx%d)\ninset(物理px): top=%d bottom=%d left=%d right=%d"
		% [
			win.x,
			win.y,
			safe.position.x,
			safe.position.y,
			safe.size.x,
			safe.size.y,
			int(top_inset),
			int(bottom_inset),
			int(left_inset),
			int(right_inset),
		]
	)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(info)

	add_child(layer)
	_safe_area_overlay = layer
	print(
		(
			"[Cheat] safe_area: 开启 win=%s safe=%s top=%d bottom=%d"
			% [str(win), str(safe), int(top_inset), int(bottom_inset)]
		)
	)


func _log_safe_group(
	group: String, baseline_meta: String, expected_inset: float, is_top: bool
) -> void:
	var nodes: Array = get_tree().get_nodes_in_group(group)
	print("[safe_area] ── 组 %s(%d 个)  期望 inset=%.1f ──" % [group, nodes.size(), expected_inset])
	for n in nodes:
		if not (n is Control):
			continue
		var c := n as Control
		if not c.has_meta(baseline_meta):
			print("[safe_area]   %s  (无 baseline meta,该页未跑过 _apply_safe_area)" % c.name)
			continue
		var baseline: Vector2 = c.get_meta(baseline_meta)
		var applied: float = (
			(c.offset_top - baseline.x) if is_top else (baseline.y - c.offset_bottom)
		)
		var ok: String = "✓" if is_equal_approx(applied, expected_inset) else "✗ 不一致"
		print(
			(
				"[safe_area]   %-24s offset_top=%.1f offset_bottom=%.1f baseline=(%.1f,%.1f) 实际应用=%.1f  %s"
				% [
					c.name,
					c.offset_top,
					c.offset_bottom,
					baseline.x,
					baseline.y,
					applied,
					ok,
				]
			)
		)


func _add_band(layer: CanvasLayer, pos: Vector2, band_size: Vector2, color: Color) -> void:
	if band_size.x <= 0.0 or band_size.y <= 0.0:
		return
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = band_size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


func _cmd_adapt_holders(_args: Array[String]) -> void:
	var page: Node = CheatTabBase.get_active_game_page()
	if page == null:
		print("[adapt_holders] 需要在 game/daily_game 页面")
		Toast.popup("adapt_holders: 请先进游戏页", self)
		return
	var vbox: Node = page.get_node_or_null("Root/VBoxContainer")
	if vbox == null:
		print("[adapt_holders] 未找到 Root/VBoxContainer")
		return

	var win_y: float = float(DisplayServer.window_get_size().y)
	var vp2d_y: float = get_viewport().get_visible_rect().size.y
	var to_phys: float = (win_y / vp2d_y) if vp2d_y > 0.0 else 1.0

	print("[adapt_holders] ── VBoxContainer AdaptHolder 高度 ──")
	print("[adapt_holders] 物理窗口高=%.0fpx  2D视口高=%.0f  2D→物理系数=%.4f" % [win_y, vp2d_y, to_phys])
	var total_ratio: float = 0.0
	var holders: Array[Control] = []
	for child in vbox.get_children():
		if child is Control and String(child.name).ends_with("AdaptHolder"):
			holders.append(child)
			total_ratio += (child as Control).size_flags_stretch_ratio
	for c in holders:
		var ratio: float = c.size_flags_stretch_ratio
		var h2d: float = c.size.y
		var pct: float = (ratio / total_ratio * 100.0) if total_ratio > 0.0 else 0.0
		print(
			(
				"[adapt_holders] %-22s 设置ratio=%7.1f (%.1f%%)  实际2D=%.1f  实际物理=%.0fpx"
				% [
					c.name,
					ratio,
					pct,
					h2d,
					h2d * to_phys,
				]
			)
		)
	print("[adapt_holders] ratio 合计=%.1f  共 %d 个" % [total_ratio, holders.size()])
	Toast.popup("adapt_holders: %d 个,详见日志" % holders.size(), self)


func _cmd_resort_fail(_args: Array[String]) -> void:
	var page: Node = UIManager.get_ui(UiName.FAIL)
	if page == null or not (page is CanvasItem) or not (page as CanvasItem).visible:
		print("[Cheat] resort_fail: 失败页未显示,请先在失败结算页触发")
		Toast.popup("resort_fail: 请先进失败页", self)
		return
	var vbox: Control = page.get_node_or_null("Root/VBoxContainer/VBoxContainer")
	var enc: Control = page.get_node_or_null("Root/VBoxContainer/VBoxContainer/EncourageLabel")
	var bg: Control = page.get_node_or_null(
		"Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/Bg"
	)
	if vbox == null or enc == null or bg == null:
		print("[Cheat] resort_fail: 未找到 VBox / EncourageLabel / 复活按钮 Bg 节点")
		return

	var snapshot := func() -> String:
		var e: float = enc.get_global_rect().end.y
		var b: float = bg.get_global_rect().position.y
		return "enc底=%.1f 复活Bg顶=%.1f 间距=%.1f" % [e, b, b - e]

	var before: String = snapshot.call()

	for c in vbox.get_children():
		if c is Control:
			(c as Control).update_minimum_size()
	vbox.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame
	var after: String = snapshot.call()
	print("[Cheat] resort_fail 已强制刷新 VBox 布局")
	print("[Cheat]   刷新前: %s" % before)
	print("[Cheat]   刷新后: %s" % after)
	Toast.popup("resort_fail: 前[%s] 后[%s]" % [before, after], self)


func _cmd_mock_ad_fail(_args: Array[String]) -> void:
	if not OS.has_feature("ios"):
		print("[cheat] mock_ad_fail: iOS only")
		return
	UniKitManager.debug_mock_ad_load_fail()
	print("[cheat] mock_ad_fail: dispatched")


func _cmd_inter(_args: Array[String]) -> void:
	var show_id := UniKitManager.stats_ad_show_timing(AdPlacement.INTERSTITIAL, "cheat")
	if await UniKitManager.is_interstitial_ready(AdPlacement.INTERSTITIAL, "cheat", show_id):
		UniKitManager.try_show_interstitial(AdPlacement.INTERSTITIAL, "cheat", show_id)


func _cmd_reward(_args: Array[String]) -> void:
	var show_id := UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, "cheat")
	if await UniKitManager.is_reward_ready(AdPlacement.REWARD, "cheat", show_id):
		UniKitManager.show_reward(AdPlacement.REWARD, "cheat", show_id)


func _cmd_mock_reward_miss(args: Array[String]) -> void:
	var enabled: bool = (int(args[0]) if args.size() > 0 else 1) != 0
	UniKitManager.set_debug_reward_miss(enabled)

	if enabled:
		var now: int = int(Time.get_unix_time_from_system())
		for _i in 3:
			GameState.record_normal_reward(now)
	print(
		(
			"[Cheat] mock_reward_miss = %d (%s)%s"
			% [
				int(enabled),
				"漏奖补发" if enabled else "正常发奖",
				" | 已补满防刷(近3天3次正常领奖)" if enabled else "",
			]
		)
	)


func _cmd_push_restore(args: Array[String]) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for _i in 3:
		GameState.record_normal_reward(now)
	GameState.add_pending_reward({"source": Tracker.AdPos.PROPS_NORMAL_HINT})

	var both: bool = args.size() > 0 and args[0] == "both"
	if both:
		GameState.add_pending_reward({"source": Tracker.AdPos.PROPS_NORMAL_LOCATE})
	print("[Cheat] push_restore: 已推入 %s 补发，回首页将触发补发弹窗" % ("hint+locate" if both else "hint"))


func _cmd_add_session(_args: Array[String]) -> void:
	SessionManager.debug_advance_session()
	print("[Cheat] add_session → session 计数 = ", GameState.get_session_count())


func _cmd_inter_prob_count(args: Array[String]) -> void:
	var n: int = int(args[0]) if args.size() > 0 else 3
	GameState.set_session_reward_view_count(n)
	print(
		"[Cheat] inter_prob_count → 本 session 激励视频次数 = ", GameState.get_session_reward_view_count()
	)


func _cmd_inter_prob_games(args: Array[String]) -> void:
	var game_count: int = int(args[0]) if args.size() > 0 else 51
	GameState.set_session_game_count(game_count)
	var cfg: InterProbConfig = ABTestManager.inter_prob
	var living_days: int = (
		ABTestManager.living_days.days_since_first_open() if cfg.has_post_gate_probability() else 0
	)
	print(
		(
			"[Cheat] inter_prob_games → 本 session 已开局数 = %d,当前组 %d 的区间概率 = %d%%,与激励闸取 min 后有效 = %d%%"
			% [
				GameState.get_session_game_count(),
				cfg.live_group(),
				cfg.session_game_percent(GameState.get_session_game_count(), living_days),
				cfg.effective_percent(
					GameState.get_session_reward_view_count(),
					GameState.get_session_game_count(),
					living_days
				),
			]
		)
	)


func _cmd_reset_first_easy(_args: Array[String]) -> void:
	GameState.cheat_reset_daily_first_easy()
	print("[Cheat] reset_first_easy: 已重置,下次进关可触发首局降档")


func _cmd_luid(_args: Array[String]) -> void:
	var luid: String = UniKitManager.get_luid()
	if luid.is_empty() and OS.has_feature("editor"):
		luid = "luid"
	print("[Cheat] luid: %s" % luid)
	DisplayServer.clipboard_set(luid)
	Toast.popup("LUID: %s (已复制)" % luid, self)


func _cmd_uuid(_args: Array[String]) -> void:
	var uuid: String = UniKitManager.get_uuid()
	if uuid.is_empty() and OS.has_feature("editor"):
		uuid = "uuid"
	print("[Cheat] uuid: %s" % uuid)
	DisplayServer.clipboard_set(uuid)
	Toast.popup("UUID: %s (已复制)" % uuid, self)


func _cmd_test_att(_args: Array[String]) -> void:
	if not OS.has_feature("editor"):
		return
	UniKitManager.debug_force_editor_test = true
	print(
		(
			"[Cheat] test_att: 重载主场景重走 launcher 流程,att_dlg_logic = %s"
			% str(ABTestManager.att_dlg_logic.value())
		)
	)
	get_tree().reload_current_scene()


func _cmd_test_err_cheat(_args: Array[String]) -> void:
	push_error("[fold-test] error A from cheat_commands.gd")


func _cmd_savetest(_args: Array[String]) -> void:
	var pw := "savetest_pw_0123456789ABCDEF0123"
	var dir := "user://save_test_fi/"
	var path_a := dir + "save_a.cfg"
	var path_b := dir + "save_b.cfg"
	var flag := dir + "flag.txt"
	var legacy := dir + "save_old.cfg"
	var eg := dir + "endgame.cfg"
	DirAccess.make_dir_recursive_absolute(dir)

	var clean := func() -> void:
		for p in [path_a, path_b, flag, legacy, eg, path_a + ".tmp", path_b + ".tmp", eg + ".tmp"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	var write_good := func(p: String, marker: String) -> void:
		var c := ConfigFile.new()
		c.set_value("p", "marker", marker)
		c.save_encrypted_pass(p, pw)
	var write_corrupt := func(p: String) -> void:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("XX_garbage_not_encrypted_XX")
		f = null
	var set_flag := func(slot: String) -> void:
		var f := FileAccess.open(flag, FileAccess.WRITE)
		f.store_string(slot)
		f = null

	var results: Array[String] = []
	var pass_count := {"n": 0}
	var run_case := func(name: String, dual: bool, expect: String) -> void:
		var store := (
			SaveStore.new(pw, dir, dual, path_a, path_b, flag, legacy)
			if dual
			else SaveStore.new(pw, dir, false, eg)
		)
		var cfg := store.load_config()
		var got := "null" if cfg == null else str(cfg.get_value("p", "marker", "?"))
		var ok: bool = got == expect
		if ok:
			pass_count.n += 1
		var line := "%s %s got=%s expect=%s" % ["[PASS]" if ok else "[FAIL]", name, got, expect]
		results.append(line)
		print("[savetest] %s" % line)

	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_good.call(path_b, "B")
	run_case.call("a坏 b好(flag=A)", true, "B")
	clean.call()
	set_flag.call("A")
	write_good.call(path_a, "A")
	write_corrupt.call(path_b)
	run_case.call("a好 b坏(flag=A)", true, "A")
	clean.call()
	set_flag.call("B")
	write_corrupt.call(path_a)
	write_good.call(path_b, "B")
	run_case.call("a坏 b好(flag=B)", true, "B")
	clean.call()
	set_flag.call("B")
	write_good.call(path_a, "A")
	write_corrupt.call(path_b)
	run_case.call("a好 b坏(flag=B)", true, "A")
	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_corrupt.call(path_b)
	write_good.call(legacy, "OLD")
	run_case.call("ab坏 c好(旧档兜底)", true, "OLD")
	clean.call()
	set_flag.call("A")
	write_corrupt.call(path_a)
	write_corrupt.call(path_b)
	write_corrupt.call(legacy)
	run_case.call("abc 全坏", true, "null")

	clean.call()
	write_good.call(eg, "EG")
	run_case.call("残局 好", false, "EG")
	clean.call()
	write_corrupt.call(eg)
	run_case.call("残局 坏", false, "null")

	clean.call()
	if DirAccess.dir_exists_absolute(dir):
		DirAccess.remove_absolute(dir)

	var total := results.size()
	print("[savetest] ===== %d/%d 通过 =====" % [pass_count.n, total])
	Toast.popup("存档容错自检: %d/%d 通过" % [pass_count.n, total], self)


func _cmd_speed(args: Array[String]) -> void:
	var scale: float = float(args[0]) if args.size() > 0 else 1.0
	scale = clampf(scale, 0.1, 10.0)
	Engine.time_scale = scale
	Toast.popup("游戏速度: %.1fx" % scale, self)


func _cmd_http_headers(_args: Array[String]) -> void:
	var http := HttpClient.new()
	var headers: PackedStringArray = http._common_headers()
	http.free()
	print("[Cheat] HttpClient 公共 Header (%d 项):" % headers.size())
	for h: String in headers:
		print("  " + h)


func _cmd_buy(args: Array[String]) -> void:
	var arg: String = args[0] if args.size() > 0 else "0"
	var force: bool = args.size() > 1 and (args[1] == "force" or args[1] == "f")
	var product_id: String = arg
	if arg.is_valid_int():
		var ids: Array = PurchaseManager.get_sub_product_ids_cfg()
		var idx: int = int(arg)
		if idx < 0 or idx >= ids.size():
			Toast.popup("buy: 序号 %d 越界(共 %d 个商品)" % [idx, ids.size()], self)
			return
		product_id = String(ids[idx])
	print("[Cheat] buy → %s force=%s" % [product_id, force])
	if not PurchaseManager.buy(product_id, force):
		if not UniKit.purchase_module.is_initialized():
			Toast.popup("内购未初始化(本次会话不可用),未发起: %s" % product_id, self)
		elif PurchaseManager.is_vip_active():
			Toast.popup("已是 VIP，拒绝重复购买（加 force 绕过）: %s" % product_id, self)
		elif PurchaseManager.is_purchasing():
			Toast.popup("上一笔购买还在飞，拒绝重复下单（加 force 绕过）: %s" % product_id, self)
		else:
			Toast.popup("购买未发起，原因未知(见日志): %s" % product_id, self)
		return
	Toast.popup("发起购买: %s" % product_id, self)


func _cmd_restore(_args: Array[String]) -> void:
	print("[Cheat] restore")
	Toast.popup("恢复购买中…", self)

	PurchaseManager.restore_purchase()


func _cmd_sub_loading(args: Array[String]) -> void:
	var sec: float = 6.0
	if args.size() > 0 and args[0].is_valid_float():
		sec = clampf(args[0].to_float(), 1.0, 60.0)
	print("[Cheat] sub_loading: 显示 %.1fs 后自动关闭" % sec)
	UIManager.show_ui(UiName.COMMON_LOADING)
	get_tree().create_timer(sec).timeout.connect(
		func() -> void: UIManager.hide_ui(UiName.COMMON_LOADING)
	)


func _cmd_nettype(_args: Array[String]) -> void:
	var net_type: String = UniKitManager.get_network_type()
	print("[Cheat] nettype: %s" % net_type)
	Toast.popup("当前网络类型: %s" % net_type, self)


func _cmd_vip(_args: Array[String]) -> void:
	var active: bool = PurchaseManager.is_vip_active()
	var products: Dictionary = PurchaseManager.get_products()
	var pm: UniKitPurchaseModule = UniKit.purchase_module
	var inited: bool = pm.is_initialized()
	var any_sub: bool = pm.is_any_subscription_active()
	var msg: String = (
		"VIP=%s 商品数=%d init=%s addon有效订阅=%s" % [active, products.size(), inited, any_sub]
	)
	print("========== VIP / 内购状态 ==========")
	print(
		(
			"本层: VIP=%s 档位=%d 上次赠送=%s"
			% [
				active,
				PurchaseManager.get_vip_tier(),
				PurchaseManager.get_vip_daily_gift_last_claim_date()
			]
		)
	)

	print(
		(
			"有效订阅=%s 生效=%s 多笔=%s 购买在飞=%s"
			% [
				str(PurchaseManager.get_valid_sub_product_ids()),
				PurchaseManager.get_vip_plan_product_id(),
				PurchaseManager.has_multiple_subscriptions(),
				PurchaseManager.is_purchasing()
			]
		)
	)
	print(
		(
			"addon: initialized=%s is_any_subscription_active=%s 可付款=%s"
			% [inited, any_sub, pm.is_authorized_for_payments()]
		)
	)
	print("商品表(元数据已就绪 %d 项):" % products.size())
	for product_id: String in PurchaseManager.get_sub_product_ids_cfg():
		var p: UniKitPurchaseProduct = products.get(product_id)
		if p == null:
			print(
				"  · %s | (未拉到元数据) | 有效订阅=%s" % [product_id, pm.is_valid_subscription(product_id)]
			)
			continue
		print(
			(
				"  · %s | %s | %s | 有效订阅=%s"
				% [
					product_id,
					p.display_price,
					p.currency_code,
					pm.is_valid_subscription(product_id)
				]
			)
		)
	print("====================================")
	Toast.popup(msg, self)


func _cmd_vip_refresh(_args: Array[String]) -> void:
	print("[Cheat] vip_refresh → update_subscription(静默,无回执)")
	Toast.popup("已发起静默刷新；无信号=商店无有效订阅，本地状态不变", self)
	PurchaseManager.update_subscription()


func _cmd_vip_clear(args: Array[String]) -> void:
	var also_store: bool = args.size() > 0 and args[0].to_lower() in ["all", "store", "unsub"]
	var had_store: bool = not PurchaseManager.get_debug_fake_store_purchase().is_empty()
	PurchaseManager.cheat_clear_vip_local(also_store)
	var msg: String = ""
	if also_store:
		msg = "已清本地 + 模拟商店记录(%s) = 相当于真退订,恢复购买将找不到记录" % ["原有记录已删" if had_store else "本来就没有"]
	else:
		msg = (
			"已清本地(VIP/档位/到期/套餐锁定)。模拟商店记录%s —— 点「恢复购买」可拉回来"
			% ["保留" if had_store else "本来就没有,恢复会说找不到"]
		)
	print("[Cheat] vip_clear(all=%s): %s" % [str(also_store), msg])
	Toast.popup(msg, self)


func _cmd_vip_inter(_args: Array[String]) -> void:
	PurchaseManager.cheat_clear_vip_sub_inter_last_show_date()
	var target: int = IsVipConfig.INTERSTITIAL_REPLACE_AT_COUNT - 1
	GameState.set_session_interstitial_count(target)
	var group_ok: bool = ABTestManager.is_vip.value() == IsVipConfig.VALUE_INTERSTITIAL
	var msg: String = (
		"组2插屏位: 已清当天配额 + 计数顶到 %d(下一发是第 %d 次→替换)"
		% [target, IsVipConfig.INTERSTITIAL_REPLACE_AT_COUNT]
	)
	if not group_ok:
		msg += "。⚠️ 但 is_vip 当前=%s,需先 `ab is_vip 2`" % str(ABTestManager.is_vip.value())
	if PurchaseManager.is_vip_active():
		msg += "。⚠️ 当前是 VIP、插屏被去广告拦在最前,需先 `vip_clear all`"
	print("[Cheat] vip_inter: %s" % msg)
	Toast.popup(msg, self)


func _cmd_vip_gift(_args: Array[String]) -> void:
	if not PurchaseManager.can_claim_vip_daily_gift():
		var msg: String = "VIP每日赠送: 不可领(无网/非VIP/今日已领)"
		print("[Cheat] vip_gift: %s" % msg)
		Toast.popup(msg, self)
		return
	print("[Cheat] vip_gift: 弹出领取弹窗(点 Claim / × 才真发)")

	VipDailyGiftFlow.run()


func _cmd_native_util_dump(_args: Array[String]) -> void:
	var nu_avail: bool = NativeUtilManager.is_available()
	var nu_vname: String = NativeUtilManager.get_version_name()
	var nu_vcode: int = NativeUtilManager.get_version_code()
	var nu_online: bool = NativeUtilManager.is_online()
	var nu_net: String = NativeUtilManager.get_network_type()
	var nu_first: int = NativeUtilManager.get_first_open_time_ms()

	var uk_avail: bool = UniKitManager.is_available()
	var uk_vname: String = UniKitManager.get_version_name()
	var uk_vcode: int = UniKitManager.get_version_code()
	var uk_online: bool = UniKitManager.is_online()
	var uk_net: String = UniKitManager.get_network_type()
	var uk_first: int = UniKitManager.get_first_open_time_ms()

	print("========== NativeUtil / UniKitManager 6 接口对比 ==========")
	print(
		(
			"is_available          : NU=%s | UKM=%s   (注:两侧语义不同, UKM=UniKit插件就绪 / NU=NativeUtilPlugin就绪)"
			% [str(nu_avail), str(uk_avail)]
		)
	)
	print("get_version_name      : NU=%s | UKM=%s" % [nu_vname, uk_vname])
	print("get_version_code      : NU=%d | UKM=%d" % [nu_vcode, uk_vcode])
	print("is_online             : NU=%s | UKM=%s" % [str(nu_online), str(uk_online)])
	print("get_network_type      : NU=%s | UKM=%s" % [nu_net, uk_net])
	print("get_first_open_time_ms: NU=%d | UKM=%d" % [nu_first, uk_first])
	print("==========================================================")


const _INNER_TAG_KEYS: Array[String] = [
	"country",
	"media_source",
	"living_days",
	"dynamic_ad_value",
	"os_version",
	"device_ram",
	"app_version",
	"low_perf_device",
	"device_brand",
	"first_install_time",
]


func _cmd_usertag(_args: Array[String]) -> void:
	if not UniKitManager.is_available():
		print("[Cheat][usertag] UniKit 插件不可用(编辑器 / 未初始化),跳过")
		return

	var state: Dictionary = {"done": false}
	_fetch_inner_tags_async(state)
	var waited: float = 0.0
	while not state.done and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not state.done:
		print("[Cheat][usertag] 查询超时(3s 未回调) —— Android AAR 未 emit inner_tag_result")


func _fetch_inner_tags_async(state: Dictionary) -> void:
	var tags: Dictionary = await UniKitManager.get_inner_tags()
	state.done = true
	_print_inner_tags(tags)


const _MS_TAG_KEY: String = "media_source"


func _cmd_usertag_ms(args: Array[String]) -> void:
	if not UniKitManager.is_available():
		print("[Cheat][usertag_ms] UniKit 插件不可用(编辑器 / 未初始化),跳过")
		return
	if args.is_empty():
		_print_usertag_ms_status()
		return
	UniKitManager.add_local_tag(_MS_TAG_KEY, args[0])
	print("[Cheat][usertag_ms] 已写 localTag: media_source = %s" % [args[0]])


func _print_usertag_ms_status() -> void:
	var state: Dictionary = {"done": false}
	_fetch_local_tags_ms_async(state)
	var waited: float = 0.0
	while not state.done and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not state.done:
		print("[Cheat][usertag_ms] localTag 查询超时(3s 未回调)")


func _fetch_local_tags_ms_async(state: Dictionary) -> void:
	var tags: Dictionary = await UniKitManager.get_local_tags()
	state.done = true
	if tags.has(_MS_TAG_KEY):
		print(
			(
				"[Cheat][usertag_ms] 当前 localTag: media_source = %s(已写入,合并视图将遮住 inner 真值)"
				% [str(tags[_MS_TAG_KEY])]
			)
		)
	else:
		print("[Cheat][usertag_ms] 当前无 localTag media_source(未写入)")


const _USERTAG_DEBUG_JSON_PATH: String = "user://unikit/usertag_debug.json"


func _cmd_usertag_debug(args: Array[String]) -> void:
	if args.is_empty() or args[0] == "off":
		_remove_usertag_debug_file()
		return
	_write_usertag_debug_file(args[0])


func _write_usertag_debug_file(media_source_value: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://unikit")
	var file: FileAccess = FileAccess.open(_USERTAG_DEBUG_JSON_PATH, FileAccess.WRITE)
	if file == null:
		print("[Cheat][usertag_debug] 写失败: %s" % [error_string(FileAccess.get_open_error())])
		return
	var debug_json: Dictionary = {
		"afData":
		{
			"media_source": media_source_value,
			"af_status": "Non-organic",
		},
	}
	file.store_string(JSON.stringify(debug_json, "\t"))
	file.close()
	print(
		(
			"[Cheat][usertag_debug] 已写 %s → afData.media_source = %s"
			% [_USERTAG_DEBUG_JSON_PATH, media_source_value]
		)
	)
	print("[Cheat][usertag_debug] 重启后生效(cheat kill 杀进程再进);仅 dev 包加载(is_debug=true)")


func _remove_usertag_debug_file() -> void:
	if not FileAccess.file_exists(_USERTAG_DEBUG_JSON_PATH):
		print("[Cheat][usertag_debug] 无覆盖文件,无需删")
		return
	DirAccess.remove_absolute(_USERTAG_DEBUG_JSON_PATH)
	print("[Cheat][usertag_debug] 已删覆盖文件,重启后恢复 SDK 真值")


func _print_inner_tags(tags: Dictionary) -> void:
	print("========== UniKit UserTag inner 标签 ==========")
	if tags.is_empty():
		print('⚠️ 返回空字典 —— 桥接 getInnerTagJson 退化成 "{}"(JSON 序列化失败)或插件未就绪')
	for key in _INNER_TAG_KEYS:
		if tags.has(key):
			print("%s = %s" % [key, str(tags[key])])
		else:
			print("%s = <缺失>" % key)
	var extra: Array = []
	for key in tags.keys():
		if not _INNER_TAG_KEYS.has(key):
			extra.append(key)
	if not extra.is_empty():
		print("额外 key(SDK 新增?): %s" % str(extra))

	var ram: float = float(tags.get("device_ram", 0))
	var brand: String = str(tags.get("device_brand", ""))
	var passed: bool = ram > 0.0 and brand != ""
	print(
		(
			'device_ram / device_brand 校验: %s(ram=%s brand="%s")'
			% [
				"PASS" if passed else "FAIL(iOS 上为 0 / 空 → addon 仍是 dev2 或 pod 缺该属性)",
				str(ram),
				brand
			]
		)
	)
	print("=============================================")


func _cmd_nonet(args: Array[String]) -> void:
	var scene: String = args[0] if args.size() > 0 else "断网"
	var offline: bool
	var no_fill: bool
	match scene.to_lower():
		"断网", "offline", "无网":
			offline = true
			no_fill = true
		"断网有广告", "offline_ad", "无网有广告":
			offline = true
			no_fill = false
		"有网", "online":
			offline = false
			no_fill = false
		"有网无广告", "online_nofill", "有网无填充":
			offline = false
			no_fill = true
		_:
			print("[Cheat] nonet 未知场景: %s" % scene)
			print("[Cheat] 可用: 断网 / 断网有广告 / 有网 / 有网无广告")
			print("[Cheat] 英文别名: offline / offline_ad / online / online_nofill")
			return
	UniKitManager._mock_offline = offline
	UniKitManager._mock_no_fill = no_fill
	var cfg: NoNetworkRemindConfig = ABTestManager.no_network_remind
	if args.size() > 1:
		cfg.set_debug_override(int(args[1]))

	var badge_expected: bool = cfg.is_enabled() and (no_fill if cfg.covers_no_fill() else offline)
	print("=============== nonet: %s ===============" % scene)
	print("  mock_offline = %s   →  is_online() = %s" % [offline, UniKitManager.is_online()])
	print("  mock_no_fill = %s   →  有填充 = %s" % [no_fill, not no_fill])
	print(
		(
			"  no_network_remind = %d%s"
			% [int(cfg.value()), "" if args.size() > 1 else "（未指定组号,沿用当前分组）"]
		)
	)
	print("  预期角标: %s" % ("无网标识" if badge_expected else "AD 播放键"))

	if not cfg.is_enabled():
		print("  ┌──────────────────────────────────────────┐")
		print("  │ ⚠️ 当前是对照组(0):四个场景都不会显标识!  │")
		print("  │    补救: nonet %s 1                       │" % scene)
		print("  └──────────────────────────────────────────┘")

	print("  ⚠️ 需道具库存为 0(NO_TOOL 态)才看得到;FREE 态刻意不显")
	var gp = CheatTabBase.get_active_game_page()
	if gp == null:
		print("  当前不在关内,进关后按新场景生效")
		print("=============================================")
		return

	print("  点道具的 toast: %s" % gp._tool_ad_toast_key())

	gp._arm_network_poll()
	var timer = gp.get("_net_poll_timer")
	print("  网络轮询: %s" % ("未武装(对照组)" if timer == null else "%ss" % timer.wait_time))

	gp._refresh_ad_unavailable_badge()
	print("=============================================")


func _cmd_mock_no_fill(args: Array[String]) -> void:
	var arg: String = args[0].to_lower() if args.size() > 0 else "toggle"
	var new_val: bool
	match arg:
		"on", "true", "1":
			new_val = true
		"off", "false", "0":
			new_val = false
		_:
			new_val = not UniKitManager._mock_no_fill
	UniKitManager._mock_no_fill = new_val
	print("[Cheat] mock_no_fill: %s" % ["ON(模拟无填充)" if new_val else "OFF(恢复真实填充状态)"])

	var gp = CheatTabBase.get_active_game_page()
	if gp != null:
		gp._refresh_ad_unavailable_badge()


func _cmd_mock_offline(args: Array[String]) -> void:
	var arg: String = args[0].to_lower() if args.size() > 0 else "toggle"
	var new_val: bool
	match arg:
		"on", "true", "1":
			new_val = true
		"off", "false", "0":
			new_val = false
		_:
			new_val = not UniKitManager._mock_offline
	UniKitManager._mock_offline = new_val
	print(
		(
			"[Cheat] mock_offline: %s (is_online() -> %s)"
			% ["ON(模拟无网)" if new_val else "OFF(恢复真实网络状态)", UniKitManager.is_online()]
		)
	)


func _cmd_logout(_args: Array[String]) -> void:
	await AuthManager.logout()
	AuthManager.login_as_guest()
	Toast.popup("已发起登出", self)


func _cmd_del_acc(_args: Array[String]) -> void:
	AuthManager.delete_account()
	Toast.popup("已发起删号", self)


func _progress_conflict_text() -> String:
	var conflict: ProgressConflict = AccountManager.get_progress_conflict()
	if conflict == null:
		return "无"
	return (
		"local=%d关/%d道具 cloud=%d关/%d道具 suggested=%s"
		% [
			conflict.local.level,
			conflict.local.items,
			conflict.cloud.level,
			conflict.cloud.items,
			conflict.suggested
		]
	)


func _cmd_acc_deleted(_args: Array[String]) -> void:
	var kind: String = DataSyncManager.CREDENTIAL_ACCOUNT_DELETED
	if AuthManager.is_available():
		DataSyncManager.account_credential_invalid.emit(kind, 1003)
		Toast.popup("已模拟账号已销毁(1003),回 home 看弹窗", self)
		return
	print("[Cheat] 无原生 auth 插件（编辑器 / 无插件包）：该信号无人订阅，直接调处理函数")
	AccountManager._on_account_credential_invalid(kind, 1003)
	Toast.popup("已模拟账号已销毁(1003,编辑器直调),回 home 看弹窗", self)


func _cmd_auth_state(_args: Array[String]) -> void:
	var lines: Array[String] = [
		"initialized=%s" % str(AuthManager.is_initialized()),
		"logged_in=%s" % str(AuthManager.is_logged_in()),
		"is_guest=%s" % str(AuthManager.is_guest_login()),
		"provider='%s'" % AuthManager.get_provider_id(),
		"device_id=%s" % AuthManager.get_device_id(),
		"channels=%s" % str(AccountDefine.available_channels()),
		"user_id=%s" % AuthManager.get_user_profile().user_id,
		"signed_in_channel='%s'" % AccountManager.get_signed_in_channel(),
		(
			"progress_select: pending=%s conflict=%s"
			% [str(AccountManager.is_progress_select_pending()), _progress_conflict_text()]
		),
		"account_deleted_pending=%s" % str(AccountManager.has_pending_account_deleted()),
	]
	print("[Cheat] authstate\n  " + "\n  ".join(lines))
	Toast.popup("登录态已打印到日志", self)


func _cmd_gold_flash_bug(args: Array[String]) -> void:
	var arg: String = args[0].to_lower() if args.size() > 0 else "toggle"
	var new_val: bool
	match arg:
		"on", "true", "1":
			new_val = true
		"off", "false", "0":
			new_val = false
		_:
			new_val = not CellView.debug_gold_flash_bug
	CellView.debug_gold_flash_bug = new_val
	print("[Cheat] gold_flash_bug: %s" % ("ON(跳过修复,可复现原 bug)" if new_val else "OFF(修复生效,金色残留应消失)"))


func _cmd_pwr_saver(args: Array[String]) -> void:
	var on: bool = args.size() == 0 or args[0] != "off"
	if args.size() > 1:
		PowerSaver.idle_fps = clampi(int(args[1]), 10, 60)

	PowerSaver.cache_enabled = not (args.size() > 2 and args[2] == "nocache")
	PowerSaver.set_enabled(on)

	CellView.cat_settle_enabled = on and not (args.size() > 2 and args[2] == "nosettle")
	print(
		"[Cheat] pwr_saver: %s idle_fps=%d %s" % [on, PowerSaver.idle_fps, PowerSaver.cache_debug()]
	)


var _pwr_saved: Dictionary = {}
var _pwr_frames_mark: Dictionary = {}
var _pwr_timing_samples: Array = []
var _pwr_timing_last: Dictionary = {}


func _pwr_count_visible_items(root: Node) -> int:
	var n: int = 0
	var st: Array[Node] = [root]
	while not st.is_empty():
		var nd: Node = st.pop_back()
		if nd is CanvasItem and not (nd as CanvasItem).visible:
			continue
		if nd is CanvasItem:
			n += 1
		for c: Node in nd.get_children():
			st.push_back(c)
	return n


func _cmd_pwr(args: Array[String]) -> void:
	if args.size() > 0 and args[0] == "ref":
		if _pwr_saved.is_empty():
			_pwr_saved = {
				"fps": Engine.max_fps,
				"lp": OS.low_processor_usage_mode,
				"saver": PowerSaver.enabled
			}

		PowerSaver.freeze_fps_override = true
		RenderingServer.render_loop_enabled = false
		Engine.max_fps = 1
	elif args.size() > 0 and args[0] == "unref":
		RenderingServer.render_loop_enabled = true
		PowerSaver.freeze_fps_override = false
		if not _pwr_saved.is_empty():
			Engine.max_fps = _pwr_saved.fps
			OS.low_processor_usage_mode = _pwr_saved.lp
			_pwr_saved = {}
	elif args.size() > 0 and args[0] == "bisect":
		_pwr_bisect(args.slice(1))
		return
	elif args.size() > 0 and args[0] == "timing":
		_pwr_timing_samples = []
		_pwr_timing_last = {}

		var paused: Array[Node] = []
		if args.size() > 1 and args[1] == "quiet":
			for nd: Node in get_tree().root.find_children("*", "", true, false):
				if nd == self or nd.get_script() == null:
					continue
				if (
					nd.is_processing()
					or nd.is_physics_processing()
					or nd.is_processing_input()
					or nd.is_processing_unhandled_input()
				):
					paused.append(nd)
					nd.set_meta(
						&"_pwr_q",
						[
							nd.is_processing(),
							nd.is_physics_processing(),
							nd.is_processing_input(),
							nd.is_processing_unhandled_input()
						]
					)
					nd.set_process(false)
					nd.set_physics_process(false)
					nd.set_process_input(false)
					nd.set_process_unhandled_input(false)
		var on_proc := func() -> void:
			var t: int = Time.get_ticks_usec()
			if _pwr_timing_last.has("post"):
				_pwr_timing_samples.append(
					[
						_pwr_timing_last.get("pre", t) - _pwr_timing_last.get("proc", t),
						_pwr_timing_last.post - _pwr_timing_last.get("pre", t),
						t - _pwr_timing_last.post
					]
				)
			_pwr_timing_last = {"proc": t}
		var on_pre := func() -> void: _pwr_timing_last["pre"] = Time.get_ticks_usec()
		var on_post := func() -> void: _pwr_timing_last["post"] = Time.get_ticks_usec()
		get_tree().process_frame.connect(on_proc)
		RenderingServer.frame_pre_draw.connect(on_pre)
		RenderingServer.frame_post_draw.connect(on_post)
		await get_tree().create_timer(2.0, true, false, true).timeout
		get_tree().process_frame.disconnect(on_proc)
		RenderingServer.frame_pre_draw.disconnect(on_pre)
		RenderingServer.frame_post_draw.disconnect(on_post)
		for nd: Node in paused:
			if is_instance_valid(nd) and nd.has_meta(&"_pwr_q"):
				var st: Array = nd.get_meta(&"_pwr_q")
				nd.set_process(st[0])
				nd.set_physics_process(st[1])
				nd.set_process_input(st[2])
				nd.set_process_unhandled_input(st[3])
				nd.remove_meta(&"_pwr_q")
		if not paused.is_empty():
			print("[Cheat] pwr timing quiet: paused %d script nodes" % paused.size())
		var sums: Array[float] = [0.0, 0.0, 0.0]
		for s: Array in _pwr_timing_samples:
			for i in 3:
				sums[i] += s[i]
		var cnt: int = maxi(1, _pwr_timing_samples.size())
		print(
			(
				"[Cheat] pwr timing: frames=%d process=%.2fms draw=%.2fms rest=%.2fms vis_items=%d"
				% [
					_pwr_timing_samples.size(),
					sums[0] / cnt / 1000.0,
					sums[1] / cnt / 1000.0,
					sums[2] / cnt / 1000.0,
					_pwr_count_visible_items(get_tree().root)
				]
			)
		)
		return
	elif args.size() > 0 and args[0] == "spinecost":
		var n_iter: int = int(args[1]) if args.size() > 1 else 200
		for sp: Node in get_tree().root.find_children("CatIconSpine*", "SpineSprite", true, false):
			var s: SpineSprite = sp as SpineSprite
			if not s.is_visible_in_tree():
				continue
			var t0: int = Time.get_ticks_usec()
			for _i in n_iter:
				s.update_skeleton(0.0)
			var per: float = float(Time.get_ticks_usec() - t0) / n_iter
			var sk: SpineSkeleton = s.get_skeleton()
			var t1: int = Time.get_ticks_usec()
			for _i in n_iter:
				sk.update_world_transform(0)
			var per_wt: float = float(Time.get_ticks_usec() - t1) / n_iter
			print(
				(
					"[Cheat] pwr spinecost %s: update_skeleton=%.1fus world_transform=%.1fus"
					% [s.name, per, per_wt]
				)
			)
		return
	elif args.size() > 0 and args[0] == "idleparticles":
		var n_hidden: int = 0
		for nd: Node in get_tree().current_scene.find_children("*", "CPUParticles2D", true, false):
			var p: CPUParticles2D = nd as CPUParticles2D
			if p.visible and p.is_visible_in_tree() and not p.emitting:
				p.visible = false
				n_hidden += 1
		print("[Cheat] pwr idleparticles: hidden %d" % n_hidden)
		return
	elif args.size() > 0 and args[0] == "settlecats":
		var n_s: int = 0
		for nd: Node in get_tree().root.find_children("CatIconSpine*", "SpineSprite", true, false):
			var s: SpineSprite = nd as SpineSprite
			if not s.is_visible_in_tree():
				continue
			s.set("batching_enabled", false)
			s.process_mode = Node.PROCESS_MODE_DISABLED
			n_s += 1
		print("[Cheat] pwr settlecats: %d" % n_s)
		return
	elif args.size() > 1 and args[0] == "direct":
		RenderingServer.viewport_set_render_direct_to_screen(
			get_tree().root.get_viewport_rid(), args[1] == "1"
		)
		print("[Cheat] pwr direct: %s" % args[1])
		return
	elif args.size() > 1 and args[0] == "vsync":
		DisplayServer.window_set_vsync_mode(int(args[1]) as DisplayServer.VSyncMode)
		if args.size() > 2:
			Engine.max_fps = int(args[2])
		print(
			(
				"[Cheat] pwr vsync: mode=%d max_fps=%d"
				% [DisplayServer.window_get_vsync_mode(), Engine.max_fps]
			)
		)
		return
	elif args.size() > 0 and args[0] == "clearbg":
		var page: Node = get_tree().current_scene.get_node_or_null("GamePage")
		var bg: ColorRect = (
			page.get_node_or_null("Root/Background") as ColorRect if page != null else null
		)
		if bg != null:
			RenderingServer.set_default_clear_color(bg.color)
			bg.visible = false
		print("[Cheat] pwr clearbg: %s" % (bg.color if bg != null else "no bg"))
		return
	elif args.size() > 0 and args[0] == "wave":
		var gp: Node = get_tree().current_scene.get_node_or_null("GamePage")
		var ba: Node = gp.get("_bullets_area") if gp != null else null
		if ba != null:
			var wave: Array[Dictionary] = [{"key": RobotNicknamePool.NAMES[0], "args": []}]
			ba.call("play_wave", wave, RandomNumberGenerator.new())
		print("[Cheat] pwr wave: %s fps=%d" % [str(ba != null), Engine.max_fps])
		return
	elif args.size() > 0 and args[0] == "taparm":
		var k: int = int(args[1]) if args.size() > 1 else 0
		var pos := Vector2(
			float(args[2]) if args.size() > 2 else 540.0,
			float(args[3]) if args.size() > 3 else 300.0
		)
		PowerSaver.arm_test_tap(k, pos)
		print("[Cheat] pwr taparm: k=%d pos=%s" % [k, str(pos)])
		return
	elif args.size() > 0 and args[0] == "trace":
		for line: String in PowerSaver._cache.trace_dump(true):
			print("[Cheat] pwr trace: ", line)
		print("[Cheat] pwr trace: <end>")
		return
	elif args.size() > 0 and args[0] == "cachestat":
		print("[Cheat] pwr cachestat: fps=%d %s" % [Engine.max_fps, PowerSaver.cache_debug()])
		return
	elif args.size() > 0 and args[0] == "cache":
		_pwr_static_cache(args.slice(1))
		return
	elif args.size() > 1 and args[0] == "physics":
		Engine.physics_ticks_per_second = clampi(int(args[1]), 1, 240)
		print("[Cheat] pwr physics: ticks=%d" % Engine.physics_ticks_per_second)
		return
	elif args.size() > 1 and args[0] == "cellpart":
		var page2: Node = get_tree().current_scene.get_node_or_null("GamePage")
		var bv: Node = (
			page2.get_node_or_null("Root/VBoxContainer/BoardContainer/BoardView")
			if page2 != null
			else null
		)
		var n_t: int = 0
		if bv != null:
			for cell: Node in bv.get_children():
				var t: CanvasItem = cell.get_node_or_null(args[1]) as CanvasItem
				if t != null:
					t.visible = not t.visible
					n_t += 1
		print("[Cheat] pwr cellpart %s toggled %d" % [args[1], n_t])
		return
	elif args.size() > 1 and args[0] == "hide":
		var page: Node = get_tree().current_scene.get_node_or_null("GamePage")
		var target: CanvasItem = (
			page.get_node_or_null(args[1]) as CanvasItem if page != null else null
		)
		if target == null:
			print("[Cheat] pwr hide: not found %s" % args[1])
			return
		target.visible = not target.visible
		print("[Cheat] pwr hide: %s visible=%s" % [args[1], target.visible])
		return
	elif args.size() > 0 and args[0] == "mon":
		print(
			(
				"[Cheat] pwr mon: fps=%.1f process_ms=%.2f objects=%d prims=%d draw_calls=%d vmem_mb=%.1f nodes=%d"
				% [
					Performance.get_monitor(Performance.TIME_FPS),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
					Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
				]
			)
		)
		return
	elif args.size() > 0 and args[0] == "frames":
		var now_ms: int = Time.get_ticks_msec()
		var drawn: int = Engine.get_frames_drawn()
		var loops: int = Engine.get_process_frames()
		if not _pwr_frames_mark.is_empty():
			var dt: float = maxf(0.001, (now_ms - int(_pwr_frames_mark.t)) / 1000.0)
			print(
				(
					"[Cheat] pwr frames: drawn/s=%.1f loops/s=%.1f over %.1fs"
					% [
						(drawn - int(_pwr_frames_mark.d)) / dt,
						(loops - int(_pwr_frames_mark.l)) / dt,
						dt
					]
				)
			)
		_pwr_frames_mark = {"t": now_ms, "d": drawn, "l": loops}
	elif args.size() > 1 and args[0] == "off":
		var n_off: int = 0
		var st: Array[Node] = [get_tree().root]
		while not st.is_empty():
			var nd: Node = st.pop_back()
			for c: Node in nd.get_children():
				st.push_back(c)
			match args[1]:
				"spine":
					if nd.get_class() == "SpineSprite":
						nd.process_mode = Node.PROCESS_MODE_DISABLED
						n_off += 1
				"anim":
					if nd is AnimationPlayer and (nd as AnimationPlayer).is_playing():
						(nd as AnimationPlayer).pause()
						n_off += 1
				"proc":
					var sp: String = (
						(nd.get_script() as Script).resource_path if nd.get_script() != null else ""
					)
					if (
						nd != self
						and nd.is_processing()
						and sp != ""
						and not sp.contains("/debug/")
						and not sp.contains("/remote/")
					):
						print("[Cheat] pwr off proc: %s" % sp.get_file())
						nd.set_process(false)
						n_off += 1
				"game":
					if (
						nd.get_script() != null
						and (nd.get_script() as Script).resource_path.ends_with("game_page.gd")
					):
						nd.set_process(false)
						n_off += 1
		print("[Cheat] pwr off %s: %d nodes" % [args[1], n_off])
		return
	else:
		if args.size() > 0:
			PowerSaver.set_enabled(false)
			Engine.max_fps = int(args[0])
		if args.size() > 1:
			OS.low_processor_usage_mode = args[1] == "1"
		if args.size() > 2:
			OS.low_processor_usage_mode_sleep_usec = int(args[2])
	print(
		(
			"[Cheat] pwr: max_fps=%d lowproc=%s sleep_usec=%d render_loop=%s"
			% [
				Engine.max_fps,
				OS.low_processor_usage_mode,
				OS.low_processor_usage_mode_sleep_usec,
				RenderingServer.render_loop_enabled
			]
		)
	)


func _pwr_bisect(custom: Array[String] = []) -> void:
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 33333
	var steps: Array[String] = [
		"none",
		"spine_proc",
		"cat_proxy",
		"cheat_overlay",
		"game_proc",
		"other_proc",
		"anim_all",
		"hide_game",
		"tweens",
		"particles",
		"subviewports",
		"hide_all"
	]
	if not custom.is_empty():
		steps = ["none"]
		steps.append_array(custom)
	for step: String in steps:
		var n: int = _pwr_disable(step)
		await get_tree().create_timer(0.5, true, false, true).timeout
		var d0: int = Engine.get_frames_drawn()
		var t0: int = Time.get_ticks_msec()
		await get_tree().create_timer(2.0, true, false, true).timeout
		var dt: float = (Time.get_ticks_msec() - t0) / 1000.0
		print(
			(
				"[PwrBisect] after %-14s (%3d nodes) drawn/s=%.1f changed=%s"
				% [step, n, (Engine.get_frames_drawn() - d0) / dt, RenderingServer.has_changed()]
			)
		)


func _pwr_disable(step: String) -> int:
	var n: int = 0
	var st: Array[Node] = [get_tree().root]
	while not st.is_empty():
		var nd: Node = st.pop_back()
		for c: Node in nd.get_children():
			st.push_back(c)
		var sp: String = (
			(nd.get_script() as Script).resource_path if nd.get_script() != null else ""
		)
		if step.begins_with("p:"):
			if sp.get_file() == step.substr(2) and nd.is_processing():
				nd.set_process(false)
				n += 1
			continue
		match step:
			"spine_proc":
				if nd.get_class() == "SpineSprite":
					nd.process_mode = Node.PROCESS_MODE_DISABLED
					n += 1
			"cat_proxy":
				if nd.has_method("_sync_cat_proxy"):
					var cb: Callable = Callable(nd, "_sync_cat_proxy")
					if RenderingServer.frame_pre_draw.is_connected(cb):
						RenderingServer.frame_pre_draw.disconnect(cb)
						n += 1
			"cheat_overlay":
				if nd.name == &"CheatOverlay" and nd is CanvasItem:
					(nd as CanvasItem).visible = false
					nd.process_mode = Node.PROCESS_MODE_DISABLED
					n += 1
			"game_proc":
				if sp.ends_with("game_page.gd") and nd.is_processing():
					nd.set_process(false)
					n += 1
			"other_proc":
				if (
					nd != self
					and sp != ""
					and (nd.is_processing() or nd.is_physics_processing())
					and not sp.contains("/debug/")
					and not sp.contains("/remote/")
				):
					print("[PwrBisect]   stop proc %s" % sp.get_file())
					nd.set_process(false)
					nd.set_physics_process(false)
					n += 1
			"anim_all":
				if nd is AnimationMixer:
					nd.process_mode = Node.PROCESS_MODE_DISABLED
					n += 1
			"tweens":
				if nd == get_tree().root:
					for t: Tween in get_tree().get_processed_tweens():
						t.kill()
						n += 1
			"particles":
				if nd is GPUParticles2D or nd is CPUParticles2D:
					nd.process_mode = Node.PROCESS_MODE_DISABLED
					(nd as CanvasItem).visible = false
					n += 1
			"subviewports":
				if nd is SubViewport:
					(nd as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
					print("[PwrBisect]   subviewport %s" % get_tree().root.get_path_to(nd))
					n += 1
			"hide_all":
				if nd.get_parent() == get_tree().current_scene and nd is CanvasItem:
					(nd as CanvasItem).visible = false
					n += 1
			"hide_game":
				if (
					(sp.ends_with("/game_page.gd") or sp.ends_with("/daily_game_page.gd"))
					and nd is CanvasItem
				):
					(nd as CanvasItem).visible = false
					n += 1
	return n


var _pwr_cache_vp: SubViewport = null
var _pwr_cache_rect: TextureRect = null
var _pwr_cache_tagged: Array[CanvasItem] = []
const _PWR_STATIC_BIT: int = 1 << 1


func _pwr_static_cache(args: Array[String]) -> void:
	var mode: String = args[0] if args.size() > 0 else "on"
	var root: Window = get_tree().root
	if mode == "off":
		for ci: CanvasItem in _pwr_cache_tagged:
			if is_instance_valid(ci):
				ci.visibility_layer = ci.get_meta(&"_pwr_vl", 1)
				ci.remove_meta(&"_pwr_vl")
		_pwr_cache_tagged.clear()
		root.canvas_cull_mask = 4294967295
		if is_instance_valid(_pwr_cache_rect):
			_pwr_cache_rect.queue_free()
		if is_instance_valid(_pwr_cache_vp):
			_pwr_cache_vp.queue_free()
		_pwr_cache_vp = null
		_pwr_cache_rect = null
		print("[Cheat] pwr cache: off")
		return
	if mode == "refresh":
		if is_instance_valid(_pwr_cache_vp):
			_pwr_cache_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		print("[Cheat] pwr cache: refresh")
		return
	if is_instance_valid(_pwr_cache_vp):
		print("[Cheat] pwr cache: already on")
		return
	var page: CanvasItem = get_tree().current_scene.get_node_or_null("GamePage") as CanvasItem
	if page == null:
		print("[Cheat] pwr cache: no GamePage")
		return

	var dynamic_roots: Array[Node] = page.find_children("CatBatchLayer", "", true, false)
	var keep: Dictionary = {}
	for d: Node in dynamic_roots:
		var a: Node = d
		while a != null and a != page.get_parent():
			keep[a.get_instance_id()] = true
			a = a.get_parent()
	var stack: Array[Node] = [page]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var ci: CanvasItem = n as CanvasItem
			if keep.has(ci.get_instance_id()):
				ci.set_meta(&"_pwr_vl", ci.visibility_layer)
				ci.visibility_layer = 1 | _PWR_STATIC_BIT
				_pwr_cache_tagged.append(ci)
			elif dynamic_roots.has(n):
				pass
			else:
				ci.set_meta(&"_pwr_vl", ci.visibility_layer)
				ci.visibility_layer = _PWR_STATIC_BIT
				_pwr_cache_tagged.append(ci)

		for c: Node in n.get_children():
			if not dynamic_roots.has(c):
				stack.push_back(c)

	var vp := SubViewport.new()
	vp.world_2d = root.world_2d
	vp.size = root.size
	vp.transparent_bg = false
	vp.canvas_cull_mask = _PWR_STATIC_BIT
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_transform = root.get_final_transform()
	add_child(vp)
	_pwr_cache_vp = vp

	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.top_level = true

	var dyn: Node = dynamic_roots[0] if not dynamic_roots.is_empty() else page
	var host: Node = dyn.get_parent() if dyn != page else page
	host.add_child(rect)
	host.move_child(rect, dyn.get_index() if dyn != page else 0)

	var abs_z: int = 0
	var zn: Node = dyn
	while zn is CanvasItem:
		abs_z += (zn as CanvasItem).z_index
		if not (zn as CanvasItem).z_as_relative:
			break
		zn = zn.get_parent()
	rect.z_as_relative = false
	rect.z_index = abs_z - 1
	var inv: Transform2D = root.get_final_transform().affine_inverse()
	rect.position = inv * Vector2.ZERO
	rect.size = inv.basis_xform(Vector2(vp.size))
	_pwr_cache_rect = rect
	root.canvas_cull_mask = 4294967295 & ~_PWR_STATIC_BIT
	print(
		(
			"[Cheat] pwr cache: on tagged=%d vp=%s final_xform=%s visible_rect=%s"
			% [
				_pwr_cache_tagged.size(),
				vp.size,
				root.get_final_transform(),
				root.get_visible_rect()
			]
		)
	)


func _cmd_pwr_probe(_args: Array[String]) -> void:
	var page: Node = get_tree().current_scene
	for n: Node in page.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if not c.is_visible_in_tree():
			continue
		var area: float = (
			c.size.x
			* c.size.y
			* absf(c.get_global_transform().get_scale().x * c.get_global_transform().get_scale().y)
		)
		if area < 200000.0:
			continue
		var a_eff: float = c.modulate.a * c.self_modulate.a
		var p: Node = c.get_parent()
		while p is CanvasItem:
			a_eff *= (p as CanvasItem).modulate.a
			p = p.get_parent()
		var own_a: float = 1.0
		if c is ColorRect:
			own_a = (c as ColorRect).color.a
		if (
			a_eff * own_a < 0.01
			and (c is ColorRect or c is TextureRect or c is NinePatchRect or c is Panel)
		):
			print(
				(
					"[PwrProbe] transparent-big %s area=%.0f  %s"
					% [c.get_class(), area, page.get_path_to(c)]
				)
			)
	var root: Node = get_tree().root
	var lines: PackedStringArray = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.push_back(c)
		var vis: bool = true
		var host: Node = n.get_parent() if not (n is CanvasItem) else n
		if host is CanvasItem:
			vis = (host as CanvasItem).is_visible_in_tree()
		if not vis or not n.can_process():
			continue
		var tag: String = ""
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing():
			tag = "anim:%s" % (n as AnimationPlayer).current_animation
		elif n is AnimatedSprite2D and (n as AnimatedSprite2D).is_playing():
			tag = "asprite"
		elif n is GPUParticles2D and (n as GPUParticles2D).emitting:
			tag = "gpu_particles"
		elif n is CPUParticles2D and (n as CPUParticles2D).emitting:
			tag = "cpu_particles"
		elif n.get_class() == "SpineSprite":
			tag = "spine"
		elif n is CanvasItem and (n as CanvasItem).material is ShaderMaterial:
			var sh: Shader = ((n as CanvasItem).material as ShaderMaterial).shader
			if sh != null and sh.code.contains("TIME"):
				tag = "shader_TIME:%s" % sh.resource_path.get_file()
		elif n.is_processing() and n.get_script() != null:
			tag = "process:%s" % (n.get_script() as Script).resource_path.get_file()
		if tag != "":
			lines.append("%s  %s" % [tag, root.get_path_to(n)])
	print("[PwrProbe] tweens=%d hits=%d" % [get_tree().get_processed_tweens().size(), lines.size()])
	for t: Tween in get_tree().get_processed_tweens():
		print("[PwrProbe] tween running=%s loops_left=%d" % [t.is_running(), t.get_loops_left()])
	for l: String in lines:
		print("[PwrProbe] " + l)


func _cmd_time_scale(args: Array[String]) -> void:
	var ratio: float = float(args[0]) if args.size() > 0 else 0.25
	ratio = clampf(ratio, 0.05, 4.0)
	Engine.time_scale = ratio
	print("[Cheat] time_scale: %.2fx (Engine.time_scale=%.3f)" % [ratio, Engine.time_scale])


func _cmd_blocker_repro(args: Array[String]) -> void:
	var hold: float = float(args[0]) if args.size() > 0 else 0.3
	hold = clampf(hold, 0.0, 3.0)
	var root: Window = get_tree().root
	var layer := CanvasLayer.new()
	layer.layer = 1001
	root.add_child(layer)

	var target := Control.new()
	target.name = "BlockerReproTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(target)
	target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	await get_tree().process_frame
	if not is_instance_valid(target):
		return
	UIManager.block_input_briefly(target, 3.0)
	var b1: Control = target.get_node_or_null(NodePath("_InputBlocker")) as Control
	if b1 == null:
		print("[Cheat] blocker_repro: 未找到 _InputBlocker,block_input_briefly 实现可能已改")
		layer.queue_free()
		return
	await get_tree().process_frame
	if not is_instance_valid(b1) or not is_instance_valid(target):
		return

	var got: Dictionary = {"down": false}
	b1.gui_input.connect(
		func(ev: InputEvent) -> void:
			if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
				got.down = true
	)

	var pos: Vector2 = Vector2(root.size) * 0.5
	var down := InputEventScreenTouch.new()
	down.index = 7
	down.pressed = true
	down.position = pos
	root.push_input(down)
	if not got.down:
		print(
			"[Cheat] blocker_repro: 触摸未落到 blocker(被某个 _input 提前 set_input_as_handled,或拾取被更高 canvas layer 抢走),中止"
		)
		layer.queue_free()
		return
	print("[Cheat] blocker_repro: 按下已命中 blocker#1,touch_focus[7] 已指向它")

	UIManager.block_input_briefly(target, 2.0)
	print(
		(
			"[Cheat] blocker_repro: 二次 block 后 blocker#1 valid=%s inside_tree=%s(期望 true/false)"
			% [is_instance_valid(b1), b1.is_inside_tree()]
		)
	)
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	if not is_instance_valid(root):
		return
	var up := InputEventScreenTouch.new()
	up.index = 7
	up.pressed = false
	up.position = pos
	print('[Cheat] blocker_repro: 注入抬起,下一行应出现引擎断言 Condition "!is_inside_tree()" is true')
	root.push_input(up)
	await get_tree().process_frame

	if is_instance_valid(layer):
		layer.queue_free()


func _cmd_robot_sim(_args: Array[String]) -> void:
	UIManager.show_ui(UiName.DBG_RANK_BOARD)


## 将 on、off 或状态查询交给控制台访问器，启动失败仅显示诊断提示。
func _cmd_rc(args: Array[String]) -> void:
	var action: String = args[0].to_lower() if args.size() > 0 else ""
	match action:
		"on":
			if RemoteConsoleAccess.start():
				Toast.popup(RemoteConsoleAccess.status_text(), self)
			else:
				Toast.popup("远程控制台启动失败,看日志", self)
		"off":
			RemoteConsoleAccess.stop()
			Toast.popup("远程控制台已停止", self)
		_:
			Toast.popup(RemoteConsoleAccess.status_text(), self)
			print("[Cheat] rc: " + RemoteConsoleAccess.status_text())
