# 埋点门面（autoload）：事件名与参数取值在这里集中定义，业务只调 track_* ，最终由 UniKitManager 转给原生 SDK
# ================= 事件名 =================
extends Node

const EVT_SCR_SHOW: String = "scr_show" # 页面曝光
const EVT_DLG_SHOW: String = "dlg_show" # 弹窗曝光
const EVT_BTN_CLICK: String = "btn_click" # 按钮点击
const EVT_GAME_START: String = "game_start" # 开局
const EVT_GAME_END: String = "game_end" # 一局结束（赢/输/中途退出都走它）
const EVT_PROP_GET: String = "prop_get" # 道具获得
const EVT_PROP_USE: String = "prop_use" # 道具消耗
const EVT_AD_SHOW_TIMING: String = "ad_show_timing" # 广告展示耗时
const EVT_INTERSTITIAL_AD_SHOW: String = "interstitial_ad_show" # 插屏广告展示
const EVT_REWARDED_AD_SHOW: String = "rewarded_ad_show" # 激励视频展示
const EVT_SW_CLICK: String = "sw_click" # 设置开关点击
const EVT_NEW_GUIDE_SHOW: String = "new_guide_show" # 新手引导开始
const EVT_NEW_GUIDE_END: String = "new_guide_end" # 新手引导结束
const EVT_NEW_GUIDE_STEP: String = "new_guide_step" # 新手引导单步
const EVT_PERF_MONITOR: String = "perf_monitor" # 启动阶段性能耗时
const EVT_REMOVE_APP_START: String = "remove_app_start" # 桌面快捷方式冷启动
const EVT_SPARK_STREAK: String = "spark_streak" # 连胜进度变化


# 页面标识：track_scr_show 的 scr_name 取值，节点通过 get_scr_name() 暴露
class Scr:
	const SPLASH: String = "splash_scr" # 闪屏
	const HOMEPAGE: String = "homepage_scr" # 主页
	const NORMAL_GAME: String = "normal_game_scr" # 普通模式对局
	const NORMAL_GAME_SUCCESS: String = "normal_game_success_scr" # 普通模式胜利结算
	const NORMAL_GAME_FAIL: String = "normal_game_fail_scr" # 普通模式失败结算
	const DAILY_GAME: String = "daily_game_scr" # 每日挑战对局
	const DAILY_GAME_SUCCESS: String = "daily_game_success_scr" # 每日挑战胜利结算
	const DAILY_GAME_FAIL: String = "daily_game_fail_scr" # 每日挑战失败结算
	const FEEDBACK: String = "feedback_scr" # 反馈
	const STREAK: String = "streak_scr" # 连胜活动页（主态）
	const GAME_STREAK: String = "game_streak_scr" # 连胜活动页（结算态）


# 弹窗标识：track_dlg_show 的 dlg_name 取值，节点通过 get_dlg_name() 暴露
class Dlg:
	const PRIVACY: String = "privacy_dlg" # 隐私政策
	const PRE_ATT_GUIDE: String = "pre_att_guide_dlg" # ATT 授权前引导
	const RATE: String = "rate_dlg" # 评分引导
	const FEEDBACK: String = "feedback_dlg" # 反馈
	const SETTINGS: String = "settings_dlg" # 设置
	const OPTIONS: String = "options_dlg" # 对局内选项
	const GAME_NORMAL_TOAST: String = "game_normal_toast_dlg" # 普通模式局内提示条
	const GAME_HARD_TOAST: String = "game_hard_toast_dlg" # 困难关提示条
	const REWARD_FAIL: String = "reward_fail_dlg" # 广告奖励失败
	const DAILY_AUTO_MARK_POPUP: String = "daily_auto_mark_popup_dlg" # 每日自动标叉弹窗
	const LANGUAGE_PICKER: String = "language_picker_dlg" # 语言选择


# 按钮标识：track_btn_click 的 btn_name 取值
class Btn:
	const NORMAL_PLAY: String = "normal_play" # 主页进普通模式
	const DAILY_PLAY: String = "daily_play" # 主页进每日挑战
	const SETTINGS: String = "settings" # 进设置
	const STREAK: String = "streak" # 进连胜活动

	const BACK: String = "back" # 返回
	const HINT: String = "hint" # 提示
	const LOCATE: String = "locate" # 定位
	const CLEAR: String = "clear" # 清空
	const COORD: String = "coord" # 坐标显示
	const HINT_APPLY: String = "hint_apply" # 提示-应用
	const HINT_STOP: String = "hint_stop" # 提示-停止
	const HINT_DETAIL: String = "hint_detail" # 提示-详情
	const OPTIONS: String = "options" # 对局内选项

	const LEVEL_PLAY: String = "level_play" # 结算页继续下一关
	const REVIVE: String = "revive" # 失败后复活
	const RESTART: String = "restart" # 重开本局
	const TRY_AGAIN: String = "try_again" # 再试一次
	const CONTINUE: String = "continue" # 继续上次残局

	const CLOSE: String = "close" # 关闭
	const FEEDBACK: String = "feedback" # 进反馈
	const TERMS: String = "terms" # 条款入口
	const POLICY: String = "policy" # 政策入口
	const PRIVACY: String = "privacy" # 隐私入口
	const PRIVACY_PREFERENCE: String = "privacy_preference" # 隐私偏好设置

	const LANGUAGE: String = "language" # 切换语言
	const LANGUAGE_CONFIRM: String = "language_confirm" # 语言确认
	const LANGUAGE_CANCEL: String = "language_cancel" # 语言取消

	const SUBMIT: String = "submit" # 提交
	const FEEDBACK_RECORD: String = "feedback_record" # 反馈里的录音/附件入口

	const ACCEPT: String = "accept" # 同意（隐私弹窗）
	const ATT_CONTINUE: String = "att_continue" # ATT 引导继续
	const RATE_US: String = "rate_us" # 去评分
	const COLLECT: String = "collect" # 领取奖励


# 道具标识：track_prop_get / track_prop_use 的 prop_name 取值
class Prop:
	const HINT: String = "hint" # 提示
	const LOCATE: String = "locate" # 定位
	const UNDO: String = "undo" # 撤销
	const AUTOX: String = "autox" # 每日挑战自动标叉


# 道具来源：prop_get / prop_use 的 source 参数取值
class PropSource:
	const HINT_REWARD_AD: String = "hint_reward_ad" # 看激励视频换提示
	const LOCATE_REWARD_AD: String = "locate_reward_ad" # 看激励视频换定位
	const UNDO_REWARD_AD: String = "undo_reward_ad" # 看激励视频换撤销
	const REWARD_FAIL_DLG: String = "reward_fail_dlg" # 奖励失败弹窗的补偿
	const STREAK_CHEST: String = "streak_chest" # 连胜宝箱
	const STREAK_REWARD_AD: String = "streak_reward_ad" # 连胜活动看激励视频
	const SWITCH_GROUP: String = "switch_group" # 切换关卡组奖励
	const AUTOX_REWARD_AD: String = "autox_reward_ad" # 每日自动标叉看激励视频


# 设置开关标识：track_sw_click 的 sw_name 取值
class Sw:
	const MUSIC: String = "music_sw" # 音乐
	const SOUND: String = "sound_sw" # 音效
	const VIBRATION: String = "vibration_sw" # 震动


# 用户属性键：走 setUserProperty（属性，不是事件）
class UserProp:
	const UI_LANGUAGE: String = "ui_language" # 界面语言


# 广告类型：track_ad_show_timing 的 placement 参数
class Placement:
	const INTERSTITIAL: String = "interstitial" # 插屏
	const REWARD: String = "reward" # 激励视频
	const APPOPEN: String = "appopen" # 开屏


# 广告位：按「出现的位置」区分，同时用于埋点与 UniKitManager 的奖励校验
class AdPos:
	const NORMAL_GAME_FAIL: String = "normal_game_fail" # 普通模式失败结算
	const DAILY_GAME_FAIL: String = "daily_game_fail" # 每日挑战失败结算
	const PROPS_NORMAL_HINT: String = "props_normal_hint" # 普通模式对局内提示
	const PROPS_NORMAL_LOCATE: String = "props_normal_locate" # 普通模式对局内定位
	const PROPS_DAILY_HINT: String = "props_daily_hint" # 每日挑战对局内提示
	const PROPS_DAILY_LOCATE: String = "props_daily_locate" # 每日挑战对局内定位
	const STREAK_X2_REWARD: String = "streak_x2_reward" # 连胜奖励翻倍
	const AUTOX_REWARD: String = "autox_reward" # 每日自动标叉

	const NORMAL_START: String = "normal_start" # 普通模式开局插屏
	const NORMAL_SUCCESS: String = "normal_success" # 普通模式胜利插屏
	const NORMAL_RESTART: String = "normal_restart" # 普通模式重开插屏
	const NORMAL_CONTINUE: String = "normal_continue" # 普通模式继续对局插屏


# 对局类型：决定读写哪一套本局统计与持久化 game_id
class GameType:
	const NORMAL: String = "normal" # 普通模式
	const DAILY: String = "daily" # 每日挑战


# 开局状态：track_game_start 的 status 参数
class GameStatus:
	const NEW: String = "new" # 新开一局
	const CONTINUE: String = "continue" # 继续上次残局
	const RESTART: String = "restart" # 重开本局


# 一局的结果：track_game_end 的 result 参数
class GameResult:
	const WIN: String = "win" # 通关
	const FAIL: String = "fail" # 失败
	const QUIT: String = "quit" # 中途退出


# 启动性能打点步骤：track_perf_monitor 的 step 参数，Launcher 依次上报
class PerfStep:
	const LOAD_SPLASH: String = "load_splash" # 闪屏加载
	const INIT_GAME_MANAGER: String = "init_game_manager" # 对局管理器初始化
	const INIT_AD_MANAGER: String = "init_ad_manager" # 广告管理器初始化
	const END: String = "end" # 启动流程结束


# ================= 运行时状态 =================
var _current_game_id: String = "" # _send 会把它附到每个事件的参数里

var _active_game_type: String = "" # Tracker.GameType.NORMAL / DAILY，决定用哪套本局统计

var _source_stack: Array[String] = [] # 来源栈：页面/弹窗曝光时入栈，供后续事件推 source

var _pending_ad_show_ids: Dictionary = {} # 广告位 → 展示 ID 的临时登记表（播放前记、展示回调时取走）

var _main_game_stats: Dictionary = {} # 普通模式本局统计（内存缓存，落盘靠 GameState 的残局存档）
var _daily_game_stats: Dictionary = {} # 每日挑战本局统计

# 这些键属于「一局」，reset_round_stats 会清掉；不在此列的键（如 restart_count、gamedie_count）跨重开保留
const _ROUND_STAT_KEYS: Array[String] = [
	"hint_used",
	"locate_used",
	"hint_apply_used",
	"hint_stop_used",
	"hint_detail_used",
	"clear_used",
	"step_used",
	"erase_count",
]


# ================= 对局与统计 API（给业务读写，不发事件） =================
# 取当前对局 ID（外部拼 game_end 参数时会用）
func get_game_id() -> String:
	return _current_game_id


# 切到某一对局类型：沿用 GameState 里持久化的 game_id，内存统计为空时从残局存档补回
func set_active_game_type(game_type: String) -> void:
	_active_game_type = game_type
	_current_game_id = GameState.get_persisted_game_id(game_type)

	var d: Dictionary = _get_active_stats_dict()
	# 内存里没有（冷启动或刚换局）就从残局存档补回上次的本局统计
	if d.is_empty():
		var persisted: Dictionary = GameState.get_game_round_stats(game_type)
		if not persisted.is_empty(): # 存档里也没有就保持空字典
			d.merge(persisted)


# 开一局新的：生成新 game_id、清空统计，并把新 ID 写进 GameState 存档
func new_game_id(game_type: String) -> String:
	_active_game_type = game_type
	_current_game_id = _gen_uuid()
	_get_active_stats_dict().clear()

	GameState.reset_game_total_stats(game_type)

	GameState.reset_game_round_stats(game_type)

	GameState.set_persisted_game_id(game_type, _current_game_id)
	return _current_game_id


# 本局统计 +delta 并落盘（局内 UI 调用最频繁的一个）
func inc_stat(key: String, delta: int = 1) -> void:
	var d: Dictionary = _get_active_stats_dict()
	d[key] = int(d.get(key, 0)) + delta
	GameState.persist_game_round_stats(_active_game_type, d)


# 读本局统计，缺省 0
func get_stat(key: String) -> int:
	return int(_get_active_stats_dict().get(key, 0))


# 清掉本局统计里的 _ROUND_STAT_KEYS 并落盘（重开一局时）
func reset_round_stats() -> void:
	var d: Dictionary = _get_active_stats_dict()
	for key: String in _ROUND_STAT_KEYS:
		d.erase(key)
	GameState.persist_game_round_stats(_active_game_type, d)


# 玩家点了重开：先清本局统计，再计一次 restart_count
func on_restart() -> void:
	reset_round_stats()
	inc_stat("restart_count")


# 按当前对局类型返回本局统计字典的引用（内部用）
func _get_active_stats_dict() -> Dictionary:
	if _active_game_type == GameType.DAILY:
		return _daily_game_stats
	return _main_game_stats


# 取来源栈顶；栈空返回空串
func get_current_source() -> String:
	return _source_stack.back() if not _source_stack.is_empty() else "" # 空栈返回空串


# 弹窗关闭：把该弹窗及其之上压入的来源一起出栈（UIManager 关弹窗时调用）
func notify_dlg_closed(dlg_name: String) -> void:
	if dlg_name == "":
		return
	var idx: int = _source_stack.rfind(dlg_name)
	if idx >= 0:
		_source_stack.resize(idx) # 连同压在这个弹窗之上的来源一起丢掉


# ================= 事件上报 API =================
# 上报页面曝光：默认用来源栈顶当 source，然后把来源栈重置为这个页面
func track_scr_show(scr_name: String, source: String = "") -> void:
	if scr_name == "":
		return
	var prev_source: String = source if source != "" else get_current_source() # 显式传入的 source 优先
	var params: Dictionary = {
		"scr_name": scr_name,
	}
	if prev_source != "":
		params["source"] = prev_source
	_send(EVT_SCR_SHOW, params)

	_source_stack.clear() # 页面级曝光：来源栈重置为当前页面
	_source_stack.append(scr_name)


# 上报弹窗曝光：source 同上，extra 会并进参数，弹窗名压入来源栈
func track_dlg_show(dlg_name: String, source: String = "", extra: Dictionary = {}) -> void:
	if dlg_name == "":
		return
	var prev_source: String = source if source != "" else get_current_source()
	var params: Dictionary = {
		"dlg_name": dlg_name,
	}
	if prev_source != "":
		params["source"] = prev_source

	for k in extra:
		params[k] = extra[k]
	_send(EVT_DLG_SHOW, params) # 曝光上报后才入栈，避免自己成为自己的 source
	_source_stack.append(dlg_name)


# 上报按钮点击：source 优先从按钮所在节点向上找，找不到才退回栈顶
func track_btn_click(btn_name: String, source_node: Node = null, extra: Dictionary = {}) -> void:
	if btn_name == "":
		return
	var source: String
	if source_node != null:
		source = _resolve_source_from_node(source_node)
	else:
		source = get_current_source()
		push_warning("Tracker.track_btn_click('%s') 未传 source_node，退化到 source 栈顶" % btn_name) # 排查漏传 source_node 的调用点
	var params: Dictionary = {
		"btn_name": btn_name,
	}
	if source != "":
		params["source"] = source
	for k in extra:
		params[k] = extra[k]
	_send(EVT_BTN_CLICK, params)


# 从节点向上冒泡找所属弹窗/页面名（节点自己实现 get_dlg_name / get_scr_name）
func _resolve_source_from_node(node: Node) -> String:
	var cur: Node = node
	while cur != null and is_instance_valid(cur):
		if cur.has_method("get_dlg_name"):
			var dlg: String = cur.call("get_dlg_name")
			if dlg != "":
				return dlg
		if cur.has_method("get_scr_name"):
			var scr: String = cur.call("get_scr_name")
			if scr != "":
				return scr
		cur = cur.get_parent()
	return ""


# 上报开局：题号、旋转、状态、类型、难度、关卡、策略层、棋盘尺寸一次带齐
func track_game_start(
	qid: String,
	qrotate: String,
	status: String,
	game_type: String,
	diffi: int,
	level: int,
	strategy_layer: int,
	scale: int
) -> void:
	var params: Dictionary = {
		"qid": qid,
		"qrotate": qrotate,
		"status": status,
		"game_type": game_type,
		"diffi": diffi,
		"level": level,
		"strategy_layer": strategy_layer,
		"scale": scale,
	}
	_send(EVT_GAME_START, params)


# 上报一局结束：参数由调用方（level_ops / 结算页）拼好传入
func track_game_end(extra: Dictionary) -> void:
	_send(EVT_GAME_END, extra)


# 上报道具获得：来源 + 本次数量 + 剩余数量
func track_prop_get(prop_name: String, source: String, prop_num: int, prop_left: int) -> void:
	var params: Dictionary = {
		"prop_name": prop_name,
		"source": source,
		"prop_num": prop_num,
		"prop_left": prop_left,
	}
	_send(EVT_PROP_GET, params)


# 上报道具消耗：参数与 prop_get 相同
func track_prop_use(prop_name: String, source: String, prop_num: int, prop_left: int) -> void:
	var params: Dictionary = {
		"prop_name": prop_name,
		"source": source,
		"prop_num": prop_num,
		"prop_left": prop_left,
	}
	_send(EVT_PROP_USE, params)


# 生成一个广告展示 ID（UUID v4）
func gen_ad_show_id() -> String:
	return _gen_uuid()


# 记住某广告位这次的展示 ID，供广告回调时取用（UniKitManager 调用）
func remember_ad_show_id(placement_type: String, ad_show_id: String) -> void:
	_pending_ad_show_ids[placement_type] = ad_show_id # 同一广告位后一次覆盖前一次


# 取走并清掉某广告位的展示 ID；没有就返回空串
func consume_ad_show_id(placement_type: String) -> String:
	var id: String = _pending_ad_show_ids.get(placement_type, "")
	if id != "":
		_pending_ad_show_ids.erase(placement_type)
	return id


# 上报广告展示耗时（placement 是广告类型，position 是广告位）
func track_ad_show_timing(
	ad_show_id: String, placement: String, placement_type: String, position: String
) -> void:
	var params: Dictionary = {
		"ad_show_id": ad_show_id,
		"placement": placement,
		"placement_type": placement_type,
		"position": position,
	}
	_send(EVT_AD_SHOW_TIMING, params)


# 上报插屏广告展示
func track_interstitial_ad_show(ad_show_id: String, level: int, position: String) -> void:
	var params: Dictionary = {
		"ad_show_id": ad_show_id,
		"level": level,
		"position": position,
	}
	_send(EVT_INTERSTITIAL_AD_SHOW, params)


# 上报激励视频展示
func track_rewarded_ad_show(ad_show_id: String, level: int, position: String) -> void:
	var params: Dictionary = {
		"ad_show_id": ad_show_id,
		"level": level,
		"position": position,
	}
	_send(EVT_REWARDED_AD_SHOW, params)


# 上报设置开关点击（state 由调用方按开 = 1 传）
func track_sw_click(sw_name: String, state: int, source: String) -> void:
	var params: Dictionary = {
		"sw_name": sw_name,
		"state": state,
		"source": source,
	}
	_send(EVT_SW_CLICK, params)


# 上报新手引导开始（带触发时的关卡）
func track_new_guide_show(level: int) -> void:
	_send(EVT_NEW_GUIDE_SHOW, {"level": level})


# 上报新手引导结束（time 单位：秒）
func track_new_guide_end(level: int, time_sec: float) -> void:
	_send(EVT_NEW_GUIDE_END, {"level": level, "time": time_sec}) # time 单位为秒


# 上报新手引导走到第几步
func track_new_guide_step(step: int) -> void:
	_send(EVT_NEW_GUIDE_STEP, {"step": step})


# 上报启动阶段耗时：cost_time 本步耗时、total_time 累计（毫秒）
func track_perf_monitor(type: String, step: String, cost_ms: int, total_ms: int) -> void:
	var params: Dictionary = {
		"type": type,
		"step": step,
		"cost_time": cost_ms,
		"total_time": total_ms,
	}
	_send(EVT_PERF_MONITOR, params)


# 上报「从桌面快捷方式冷启动」（Launcher 处理 shortcut 时调用）
func track_remove_app_start() -> void:
	_send(EVT_REMOVE_APP_START, {})


# 上报用户属性「界面语言」（走 setUserProperty，不是事件）
func track_user_property_ui_language(lang_code: String) -> void:
	UniKitManager.set_user_property(UserProp.UI_LANGUAGE, lang_code) # 只同步属性，不发事件


# 上报连胜进度：当前连胜与历史最佳（连胜模块调用）
func track_spark_streak(current_streak: int, best_streak: int) -> void:
	var params: Dictionary = {
		"game_type": _active_game_type,
		"current_streak": current_streak,
		"best_streak": best_streak,
	}
	_send(EVT_SPARK_STREAK, params)


# ================= GRT 实验埋点 =================
# 按「留存天数 + 关卡/时长阈值」补报，同一事件只报一次（去重记录存在 GameState 的存档里）
const GRT_PLATFORMS: Array = ["facebook", "appsflyer", "learnings", "firebase"] # 这几个 GRT 事件只发给这 4 个平台

# D90 档位：通关到这些等级时各报一次 grt_level{N}_d90
const GRT_LEVEL_D90_LEVELS: Array[int] = [
	2, 6, 10, 15, 20, 25, 30, 50, 80, 120, 200, 300, 500, 600, 700, 800
]

const GRT_LEVEL_D90_MAX_LIVING_DAYS: int = 89 # 超过 89 天的老玩家不再补报 D90 档

const GRT_WINDOW_MAX_LIVING: Dictionary = {"d0": 0, "d2": 1, "d3": 2, "d7": 6} # 窗口 → 允许的最大留存天数，超过就跳过该窗口

# 关卡窗口：窗口 → 触发关卡列表；当前关达到列表里的值就补报（已报过的跳过）
const GRT_LEVEL_WINDOW: Dictionary = {
	"d0": [6, 7, 9, 12],
	"d2": [7, 9, 11, 14],
	"d3": [7, 9, 12, 15],
	"d7": [8, 10, 14, 19],
}

# 时长窗口：窗口 → 累计活跃分钟阈值（分钟）
const GRT_TIME_WINDOW_MIN: Dictionary = {
	"d0": [5, 7, 10, 16],
	"d2": [5, 10, 15, 22],
	"d3": [6, 10, 16, 25],
	"d7": [6, 12, 20, 32],
}


# 通关后按 D90 档位补报 grt_level{N}_d90；报过的（记在 GameState）跳过
func try_track_grt_level_pass(level_num: int) -> void:
	var living_days: int = ABTestManager.living_days.days_since_first_open()
	if living_days < 0 or living_days > GRT_LEVEL_D90_MAX_LIVING_DAYS:
		return
	for lv: int in GRT_LEVEL_D90_LEVELS:
		if lv > level_num:
			break
		if GameState.has_grt_level_d90_reported(lv):
			continue
		var event_name: String = "grt_level%d_d90" % lv
		print(
			(
				"[Tracker][GRT] %s livingdays=%d trigger_level=%d platforms=%s"
				% [event_name, living_days, level_num, str(GRT_PLATFORMS)]
			)
		)
		UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0)
		GameState.mark_grt_level_d90_reported(lv)


# 通关后按留存窗口补报 grt_level{N}_{d0|d2|d3|d7}，每个事件只报一次
func try_track_grt_level_window(level_num: int) -> void:
	var living_days: int = ABTestManager.living_days.days_since_first_open()
	if living_days < 0:
		return
	for win: String in GRT_LEVEL_WINDOW:
		if living_days > int(GRT_WINDOW_MAX_LIVING[win]):
			continue
		for lv: int in GRT_LEVEL_WINDOW[win]:
			if lv > level_num:
				continue
			var event_name: String = "grt_level%d_%s" % [lv, win]
			if GameState.has_grt_event_reported(event_name):
				continue
			print(
				(
					"[Tracker][GRT] %s livingdays=%d trigger_level=%d platforms=%s"
					% [event_name, living_days, level_num, str(GRT_PLATFORMS)]
				)
			)
			UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0) # 空参数，value_to_sum 为 0
			GameState.mark_grt_event_reported(event_name)


# 累计活跃分钟到阈值时补报 grt_time{M}_{窗口}（SessionManager 结算前台时长后调用）
func try_track_grt_time_window(total_active_sec: int) -> void:
	var living_days: int = ABTestManager.living_days.days_since_first_open()
	if living_days < 0:
		return
	var total_min: int = total_active_sec / 60
	if total_min <= 0:
		return
	for win: String in GRT_TIME_WINDOW_MIN:
		if living_days > int(GRT_WINDOW_MAX_LIVING[win]):
			continue
		for m: int in GRT_TIME_WINDOW_MIN[win]:
			if m > total_min:
				continue
			var event_name: String = "grt_time%d_%s" % [m, win]
			if GameState.has_grt_event_reported(event_name):
				continue
			print(
				(
					"[Tracker][GRT] %s livingdays=%d total_min=%d platforms=%s"
					% [event_name, living_days, total_min, str(GRT_PLATFORMS)]
				)
			)
			UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0)
			GameState.mark_grt_event_reported(event_name) # 记进存档，保证只报一次


# ================= 工具函数 =================
# 把题库的 transform 编号转成埋点用的 qrotate：旋转角度 + 可选的 V/H 翻转前缀
func transform_to_qrotate(transform: int) -> String:
	var rot_part: String = str([0, 90, 180, 270][transform % 4]) # 低 2 位是旋转角度
	if transform >= 8:
		return "V" + rot_part # 8~15 额外带垂直翻转
	if transform >= 4:
		return "H" + rot_part # 4~7 额外带水平翻转
	return rot_part


# 统一出口：补 game_id、打日志，再交给 UniKitManager 发事件
func _send(event_name: String, params: Dictionary) -> void:
	if _current_game_id != "" and not params.has("game_id"):
		params["game_id"] = _current_game_id # 调用方自己传了 game_id 就不覆盖
	print("[Tracker] %s %s" % [event_name, JSON.stringify(params)]) # 本地按日志即可核对埋点
	UniKitManager.send_event(event_name, params) # 原生插件未就绪时这里会直接丢弃


# 生成 UUID v4 格式字符串（随机 16 字节，取 hex 拼成 8-4-4-4-12）
func _gen_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex: String = bytes.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [
			hex.substr(0, 8),
			hex.substr(8, 4),
			hex.substr(12, 4),
			hex.substr(16, 4),
			hex.substr(20, 12),
		]
	)
