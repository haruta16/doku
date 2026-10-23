## 运行统计入口：维护局标识、计数和解题步骤，整理玩法事件后交给分析通道。
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
const EVT_GOLDEN_FISH_GUIDE_SHOW: String = "golden_fish_guide_show"
const EVT_GOLDEN_FISH_GUIDE_END: String = "golden_fish_guide_end"
const EVT_PERF_MONITOR: String = "perf_monitor" # 启动阶段性能耗时
const EVT_REMOVE_APP_START: String = "remove_app_start" # 桌面快捷方式冷启动
const EVT_SPARK_STREAK: String = "spark_streak" # 连胜进度变化
const EVT_RANK_START: String = "rank_start"
const EVT_RANK_DATA: String = "rank_data"
const EVT_FRAME_GET: String = "frame_get"
const EVT_AVATAR_GET: String = "avatar_get"
const EVT_SKIN_GET: String = "skin_get"
const EVT_COMPANION_CAT_ITEM_GET: String = "companion_cat_item_get"
const EVT_COMPANION_CAT_ITEM_USE: String = "companion_cat_item_use"
const EVT_SUB_ENTRY_CLICK: String = "sub_entry_click"
const EVT_SUB_PAGE_VIEW: String = "sub_page_view"
const EVT_SUB_PLAN_SELECT: String = "sub_plan_select"
const EVT_SUB_PAY: String = "sub_pay"
const EVT_SUB_RESUME: String = "sub_resume"


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

	const GOLDEN_FISH_GAME: String = "golden_fish_game_scr"
	const GOLDEN_FISH_GAME_SUCCESS: String = "golden_fish_game_success_scr"
	const GOLDEN_FISH_GAME_FAIL: String = "golden_fish_game_fail_scr"

	const COLOR_CHALLENGE_GAME: String = "color_challenge_game_scr"
	const STREAK: String = "streak_scr" # 连胜活动页（主态）
	const GAME_STREAK: String = "game_streak_scr" # 连胜活动页（结算态）
	const CHALLENGE_RANK: String = "challenge_rank_scr"


class Dlg:
	const PRIVACY: String = "privacy_dlg" # 隐私政策
	const PRE_ATT_GUIDE: String = "pre_att_guide_dlg" # ATT 授权前引导
	const RATE: String = "rate_dlg" # 评分引导
	const FEEDBACK: String = "feedback_dlg" # 反馈
	const SETTINGS: String = "settings_dlg" # 设置
	const OPTIONS: String = "options_dlg" # 对局内选项
	const GAME: String = "game_dlg"

	const GAME_NORMAL_TOAST: String = "game_normal_toast_dlg" # 普通模式局内提示条

	const GAME_HARD_TOAST: String = "game_hard_toast_dlg" # 困难关提示条

	const GOLDEN_FISH_TOAST: String = "golden_fish_toast_dlg"

	const DC_START_TOAST: String = "dc_start_toast_dlg"
	const REWARD_FAIL: String = "reward_fail_dlg" # 广告奖励失败
	const LANGUAGE_PICKER: String = "language_picker_dlg" # 语言选择

	const CHALLENGE_GUIDE: String = "challenge_guide_dlg"
	const AVATAR: String = "avatar_dlg"
	const CHALLENGE_RANK: String = "challenge_rank_dlg"
	const CHALLENGE_REWARD: String = "challenge_reward_dlg"
	const CHALLENGE_REWARD_GET: String = "challenge_reward_get_dlg"

	const LOGIN: String = "login_dlg"
	const LOGIN_SUCCESS: String = "login_success_dlg"
	const LOGIN_FAIL: String = "login_fail_dlg"
	const NETWORK_FAIL: String = "network_fail_dlg"
	const PROGRESS_SELECT: String = "progress_select_dlg"
	const SIGN_OUT_CONFIRM: String = "sign_out_confirm_dlg"
	const DELETE_ACCOUNT_CONFIRM: String = "delete_account_confirm_dlg"
	const DELETE_ACCOUNT_SUCCESS: String = "delete_account_success_dlg"
	const ACCOUNT_DELETED_NOTICE: String = "account_deleted_notice_dlg"

	const PEEKABOO: String = "peekaboo_dlg"

	const DC_REPLAY: String = "dc_replay_dlg"

	const DC_TRIAL_SKIN: String = "dc_trial_skin_dlg"

	const COMPANION_CAT_GUIDE: String = "companion_cat_guide_dlg"

	const COMPANION_CAT_REWARD: String = "companion_cat_reward_dlg"


class Btn:
	const NORMAL_PLAY: String = "normal_play" # 主页进普通模式
	const DAILY_PLAY: String = "daily_play" # 主页进每日挑战

	const PEEKABOO_POT: String = "peekaboo_pot"
	const PEEKABOO_HAMPER: String = "peekaboo_hamper"
	const PEEKABOO_BAG: String = "peekaboo_bag"
	const PEEKABOO_LEAF: String = "peekaboo_leaf"
	const PEEKABOO_PLANT: String = "peekaboo_plant"

	const GOLDEN_FISH_PLAY: String = "golden_fish_play"

	const COLOR_CHALLENGE_PLAY: String = "color_challenge_play"
	const SETTINGS: String = "settings" # 进设置
	const STREAK: String = "streak" # 进连胜活动
	const GOTOPLAY: String = "gotoplay"

	const BACK: String = "back" # 返回
	const HINT: String = "hint" # 提示
	const LOCATE: String = "locate" # 定位

	const MOUSE: String = "mouse"
	const CLEAR: String = "clear" # 清空
	const HINT_APPLY: String = "hint_apply" # 提示-应用
	const HINT_STOP: String = "hint_stop" # 提示-停止
	const HINT_DETAIL: String = "hint_detail" # 提示-详情
	const OPTIONS: String = "options" # 对局内选项

	const DRAFT: String = "draft"
	const DRAFT_APPLY: String = "draft_apply"

	const PATTERN_MODE_ON: String = "pattern_mode_on"
	const PATTERN_MODE_OFF: String = "pattern_mode_off"

	const LEVEL_PLAY: String = "level_play" # 结算页继续下一关
	const REVIVE: String = "revive" # 失败后复活
	const RESTART: String = "restart" # 重开本局

	const GOLDEN_FISH_SKIP: String = "golden_fish_skip"

	const COLOR_CHALLENGE_SKIP: String = "color_challenge_skip"
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

	const GET_TRIPLE: String = "get_triple"
	const GET: String = "get"

	const PLAY: String = "play"
	const SAVE: String = "save"
	const COLLECT_DOUBLE: String = "collect_double"
	const CHALLENGE_INFO: String = "challenge_info"
	const SELF_INFO: String = "self_info"
	const CHALLENGE_ENTRANCE: String = "challenge_entrance"

	const SAVE_PROGRESS: String = "save_progress"
	const SIGN_IN: String = "sign_in"
	const SIGN_OUT: String = "sign_out"
	const SIGN_OUT_CONFIRM: String = "sign_out_confirm"
	const SIGN_OUT_CANCEL: String = "sign_out_cancel"
	const DELETE_ACCOUNT: String = "delete_account"
	const DELETE_ACCOUNT_CONFIRM: String = "delete_account_confirm"
	const RESTART_APP: String = "restart_app"

	const REPLAY: String = "replay"

	const EQUIP: String = "Equip"
	const LATER: String = "Later"

	const GOT_IT_CAP: String = "Got it"
	const COMPANION_CAT: String = "companion_cat"
	const COMPANION_CAT_FEED: String = "companion_cat_feed"
	const COMPANION_CAT_CANDY_BAR: String = "companion_cat_candy_bar"

	const COMPANION_CAT_TREASURE_BOX: String = "companion_cat_treasure_box"


class Prop:
	const HINT: String = "hint" # 提示
	const LOCATE: String = "locate" # 定位
	const MOUSE: String = "mouse"
	const UNDO: String = "undo" # 撤销
	const DRAFT: String = "draft"


class PropSource:
	const HINT_REWARD_AD: String = "hint_reward_ad" # 看激励视频换提示
	const LOCATE_REWARD_AD: String = "locate_reward_ad" # 看激励视频换定位
	const MOUSE_REWARD_AD: String = "mouse_reward_ad"
	const UNDO_REWARD_AD: String = "undo_reward_ad" # 看激励视频换撤销
	const DRAFT_REWARD_AD: String = "draft_reward_ad"
	const REWARD_FAIL_DLG: String = "reward_fail_dlg" # 奖励失败弹窗的补偿
	const STREAK_CHEST: String = "streak_chest" # 连胜宝箱
	const STREAK_REWARD_AD: String = "streak_reward_ad" # 连胜活动看激励视频
	const SWITCH_GROUP: String = "switch_group" # 切换关卡组奖励
	const VIP_DAILY_GIFT: String = "vip_daily_gift"
	const CHALLENGE_GET_DLG: String = "challenge_get_dlg"
	const CHALLENGE_REWARD_GET_DLG: String = "challenge_reward_get_dlg"

	const COMPANION_CAT_REWARD_DLG: String = "companion_cat_reward_dlg"


class CompanionItem:
	const CANDY: String = "candy"
	const CAN: String = "can"


class CompanionItemSource:
	const GAME_WIN_GET: String = "game_win_get"


class Sw:
	const MUSIC: String = "music_sw" # 音乐
	const SOUND: String = "sound_sw" # 音效
	const VIBRATION: String = "vibration_sw" # 震动

	const PATTERN: String = "pattern_mode_sw"


# 用户属性键：走 setUserProperty（属性，不是事件）
class UserProp:
	const UI_LANGUAGE: String = "ui_language" # 界面语言


class Placement:
	const INTERSTITIAL: String = AdPlacement.INTERSTITIAL
	const REWARD: String = AdPlacement.REWARD


class AdPos:
	const NORMAL_GAME_FAIL: String = "normal_game_fail" # 普通模式失败结算
	const DAILY_GAME_FAIL: String = "daily_game_fail" # 每日挑战失败结算
	const PROPS_NORMAL_HINT: String = "props_normal_hint" # 普通模式对局内提示
	const PROPS_NORMAL_LOCATE: String = "props_normal_locate" # 普通模式对局内定位
	const PROPS_DAILY_HINT: String = "props_daily_hint" # 每日挑战对局内提示
	const PROPS_DAILY_LOCATE: String = "props_daily_locate" # 每日挑战对局内定位
	const PROPS_NORMAL_MOUSE: String = "props_normal_mouse"
	const PROPS_DAILY_MOUSE: String = "props_daily_mouse"

	const PROPS_NORMAL_DRAFT: String = "props_normal_draft"
	const PROPS_DAILY_DRAFT: String = "props_daily_draft"
	const STREAK_X2_REWARD: String = "streak_x2_reward" # 连胜奖励翻倍
	const RANK_REWARD: String = "rank_reward"

	const PEEKABOO_REWARD: String = "peekaboo_reward"

	const DAILY_REPLAY: String = "daily_replay"

	const NORMAL_START: String = "normal_start" # 普通模式开局插屏
	const NORMAL_SUCCESS: String = "normal_success" # 普通模式胜利插屏
	const NORMAL_RESTART: String = "normal_restart" # 普通模式重开插屏
	const NORMAL_CONTINUE: String = "normal_continue" # 普通模式继续对局插屏

	const DC_RESTART: String = "dc_restart"


class GameType:
	const NORMAL: String = "normal" # 普通模式
	const DAILY: String = "daily" # 每日挑战

	const GOLDEN_FISH: String = "golden_fish"

	const COLOR_CHALLENGE: String = "color_challenge"


class GameStatus:
	const NEW: String = "new" # 新开一局
	const CONTINUE: String = "continue" # 继续上次残局
	const RESTART: String = "restart" # 重开本局

	const REPLAY: String = "replay"


# 一局的结果：track_game_end 的 result 参数
class GameResult:
	const WIN: String = "win" # 通关
	const FAIL: String = "fail" # 失败
	const QUIT: String = "quit" # 中途退出


class StepAction:
	const PREFILL_SIGN: String = "prefill_sign"
	const SIGN: String = "sign"
	const MARK: String = "mark"
	const ERASE_MARK: String = "erase_mark"
	const SWIPE_MARK: String = "swipe_mark"
	const SWIPE_ERASE: String = "swipe_erase"
	const CLICK_EXISTING_SIGN: String = "click_existing_sign"
	const CLICK_ERROR_MARK: String = "click_error_mark"
	const HINT_SHOW: String = "hint_show"
	const HINT_STOP: String = "hint_stop"
	const HINT_APPLY_MARK: String = "hint_apply_mark"
	const HINT_APPLY_ERASE: String = "hint_apply_erase"
	const HINT_APPLY_SIGN: String = "hint_apply_sign"
	const LOCATE_SIGN: String = "locate_sign"
	const MOUSE_MARK: String = "mouse_mark"
	const MOUSE_SIGN: String = "mouse_sign"


class StepResult:
	const CORRECT: int = 1
	const WRONG: int = 0
	const NO_JUDGE: int = -1


class StepEffect:
	const MARK: String = "mark"
	const SIGN: String = "sign"
	const ERASE: String = "erase"


# 启动性能打点步骤：track_perf_monitor 的 step 参数，Launcher 依次上报
class PerfStep:
	const LOAD_SPLASH: String = "load_splash" # 闪屏加载

	const INIT_GAME_MANAGER: String = "init_game_manager" # 对局管理器初始化

	const INIT_AD_MANAGER: String = "init_ad_manager" # 广告管理器初始化

	const END: String = "end" # 启动流程结束


const SUB_VALUE_UNKNOWN: String = "unknown"


class SubscriptionSource:
	const SETTINGS_GET_PREMIUM: String = "settings_get_premium"
	const INTERSTITIAL_AD_SLOT: String = "interstitial_ad_slot"


class SubscriptionUserState:
	const SUBSCRIBED: String = "subscribed"
	const UNSUBSCRIBED: String = "unsubscribed"


class SubscriptionType:
	const WEEKLY: String = "weekly"
	const MONTHLY: String = "monthly"
	const YEARLY: String = "yearly"


class SubscriptionState:
	const SUBMIT: String = "submit"
	const SUCCESS: String = "success"
	const FAILED: String = "failed"
	const CANCEL: String = "cancel"


class NetworkType:
	const WIFI: String = "wifi"
	const CELLULAR: String = "cellular"
	const NOT_CONNECT: String = "not_connect"
	const UNKNOWN: String = "unknown"


class ThemeType:
	const DARK: String = "dark_theme"
	const LIGHT: String = "light_theme"


# ================= 运行时状态 =================
var _current_game_id: String = "" # _send 会把它附到每个事件的参数里

var _active_game_type: String = "" # Tracker.GameType.NORMAL / DAILY，决定用哪套本局统计

var _source_stack: Array[String] = [] # 来源栈：页面/弹窗曝光时入栈，供后续事件推 source

var _pending_ad_show_ids: Dictionary = {} # 广告位 → 展示 ID 的临时登记表（播放前记、展示回调时取走）

var _main_game_stats: Dictionary = {} # 普通模式本局统计（内存缓存，落盘靠 GameState 的残局存档）
var _daily_game_stats: Dictionary = {} # 每日挑战本局统计
var _main_steps: SolutionStepsLog = SolutionStepsLog.new()
var _daily_steps: SolutionStepsLog = SolutionStepsLog.new()

const _ROUND_STAT_KEYS: Array[String] = [
	"hint_used",
	"locate_used",
	"mouse_used",
	"hint_apply_used",
	"hint_stop_used",
	"hint_detail_used",
	"clear_used",
	"step_used",
	"erase_count",
	"hint_cross_count",
	"cat_click_num",
]


# ================= 对局与统计 API（给业务读写，不发事件） =================
## 取当前对局 ID（外部拼 game_end 参数时会用）
func get_game_id() -> String:
	return _current_game_id


func set_active_game_type(game_type: String) -> void:
	_active_game_type = game_type
	_current_game_id = GameState.get_persisted_game_id(game_type)

	var d: Dictionary = _get_active_stats_dict()
	if d.is_empty():
		var persisted: Dictionary = GameState.get_game_round_stats(game_type)
		if not persisted.is_empty():
			d.merge(persisted)
	var steps_log: SolutionStepsLog = _get_active_steps_log()
	if steps_log.is_empty():
		steps_log.load_dict(GameState.get_solution_steps(game_type))


func new_game_id(game_type: String) -> String:
	_active_game_type = game_type
	_current_game_id = _gen_uuid()
	_get_active_stats_dict().clear()
	_get_active_steps_log().reset_all()
	GameState.reset_solution_steps(game_type)

	GameState.reset_game_total_stats(game_type)

	GameState.reset_game_round_stats(game_type)

	GameState.set_persisted_game_id(game_type, _current_game_id)

	GameState.increment_session_game_count()
	return _current_game_id


## 本局统计 +delta 并落盘（局内 UI 调用最频繁的一个）
func inc_stat(key: String, delta: int = 1) -> void:
	var d: Dictionary = _get_active_stats_dict()
	d[key] = int(d.get(key, 0)) + delta
	GameState.persist_game_round_stats(_active_game_type, d)


## 读本局统计，缺省 0
func get_stat(key: String) -> int:
	return int(_get_active_stats_dict().get(key, 0))


func reset_round_stats() -> void:
	var d: Dictionary = _get_active_stats_dict()
	for key: String in _ROUND_STAT_KEYS:
		d.erase(key)
	GameState.persist_game_round_stats(_active_game_type, d)
	var steps_log: SolutionStepsLog = _get_active_steps_log()
	steps_log.reset_round()
	GameState.persist_solution_steps(_active_game_type, steps_log.to_dict())


func record_solution_step(action: String, cells: Array) -> void:
	var steps_log: SolutionStepsLog = _get_active_steps_log()
	steps_log.append({"action": action, "cells": cells})
	GameState.persist_solution_steps(_active_game_type, steps_log.to_dict())


func remove_latest_single_tap_step(row: int, col: int) -> bool:
	var steps_log: SolutionStepsLog = _get_active_steps_log()
	var removed: bool = steps_log.remove_latest_single_cell_step(
		row, col, [StepAction.MARK, StepAction.ERASE_MARK]
	)
	GameState.persist_solution_steps(_active_game_type, steps_log.to_dict())
	return removed


func build_step_cell(row: int, col: int, region: int, result: int) -> Dictionary:
	return {"r": row, "c": col, "region": region, "result": result}


func build_hint_show_cell(row: int, col: int, region: int, effect: String) -> Dictionary:
	return {"r": row, "c": col, "region": region, "effect": effect}


func get_solution_steps() -> Array:
	return _get_active_steps_log().round_steps.duplicate(true)


func get_solution_steps_total() -> Array:
	return _get_active_steps_log().total_steps.duplicate(true)


## 玩家点了重开：先清本局统计，再计一次 restart_count
func on_restart() -> void:
	reset_round_stats()
	inc_stat("restart_count")


## 按当前对局类型返回本局统计字典的引用（内部用）
func _get_active_stats_dict() -> Dictionary:
	if _active_game_type == GameType.DAILY:
		return _daily_game_stats
	return _main_game_stats


func _get_active_steps_log() -> SolutionStepsLog:
	if _active_game_type == GameType.DAILY:
		return _daily_steps
	return _main_steps


## 取来源栈顶；栈空返回空串
func get_current_source() -> String:
	return _source_stack.back() if not _source_stack.is_empty() else "" # 空栈返回空串


## 弹窗关闭：把该弹窗及其之上压入的来源一起出栈（UIManager 关弹窗时调用）
func notify_dlg_closed(dlg_name: String) -> void:
	if dlg_name == "":
		return
	var idx: int = _source_stack.rfind(dlg_name)
	if idx >= 0:
		_source_stack.resize(idx) # 连同压在这个弹窗之上的来源一起丢掉


func notify_scr_closed(new_source: String) -> void:
	_source_stack.clear()
	if new_source != "":
		_source_stack.append(new_source)


func _get_theme_type() -> String:
	if DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode():
		return ThemeType.DARK
	return ThemeType.LIGHT


func track_scr_show(scr_name: String, source: String = "") -> void:
	if scr_name == "":
		return
	var prev_source: String = source if source != "" else get_current_source()
	var params: Dictionary = {
		"scr_name": scr_name,
		"theme_type": _get_theme_type(),
	}
	if prev_source != "":
		params["source"] = prev_source
	_send(EVT_SCR_SHOW, params)

	_source_stack.clear()
	_source_stack.append(scr_name)


## 上报弹窗曝光：source 同上，extra 会并进参数，弹窗名压入来源栈
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


## 上报按钮点击：source 优先从按钮所在节点向上找，找不到才退回栈顶
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


## 从节点向上冒泡找所属弹窗/页面名（节点自己实现 get_dlg_name / get_scr_name）
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


func track_game_start(
	qid: String,
	qrotate: String,
	status: String,
	game_type: String,
	diffi: int,
	level: int,
	strategy_layer: int,
	scale: int,
	is_challenge: int,
	pre_type: String = "0",
	pace_group: int = 0,
	pace_score: float = 0.0,
	rating: float = 0.0,
	extra: Dictionary = {},
) -> void:
	var params: Dictionary = {
		"qid": qid,
		"qrotate": qrotate,
		"status": status,
		"game_type": game_type,
		"diffi": diffi,
		"level": level,
		"strategy_layer": strategy_layer,
		"is_challenge": is_challenge,
		"scale": scale,
		"pre_type": pre_type,
		"pace_group": pace_group,
		"pace_score": pace_score,
		"rating": rating,
	}
	params.merge(extra)
	_send(EVT_GAME_START, params)


func track_game_end(extra: Dictionary) -> void:
	var steps_log: SolutionStepsLog = _get_active_steps_log()
	extra["solution_steps"] = steps_log.round_steps.duplicate(true)
	extra["solution_steps_total"] = steps_log.total_steps.duplicate(true)
	_send(EVT_GAME_END, extra)


## 上报道具获得：来源 + 本次数量 + 剩余数量
func track_prop_get(prop_name: String, source: String, prop_num: int, prop_left: int) -> void:
	var params: Dictionary = {
		"prop_name": prop_name,
		"source": source,
		"prop_num": prop_num,
		"prop_left": prop_left,
	}
	_send(EVT_PROP_GET, params)


## 上报道具消耗：参数与 prop_get 相同
func track_prop_use(prop_name: String, source: String, prop_num: int, prop_left: int) -> void:
	var params: Dictionary = {
		"prop_name": prop_name,
		"source": source,
		"prop_num": prop_num,
		"prop_left": prop_left,
	}
	_send(EVT_PROP_USE, params)


func track_sub_entry_click(source: String, user_state: String) -> void:
	_send(
		EVT_SUB_ENTRY_CLICK,
		{
			"source": source,
			"user_state": user_state,
		}
	)


func track_sub_page_view(source: String, user_state: String) -> void:
	_send(
		EVT_SUB_PAGE_VIEW,
		{
			"source": source,
			"user_state": user_state,
		}
	)


static func _sub_or_unknown(value: String) -> String:
	return value if not value.is_empty() else SUB_VALUE_UNKNOWN


static func _sub_error_code(sub_state: String, error_code: String) -> String:
	if not error_code.is_empty():
		return error_code
	var is_error_state: bool = (
		sub_state == SubscriptionState.FAILED or sub_state == SubscriptionState.CANCEL
	)
	return SUB_VALUE_UNKNOWN if is_error_state else ""


func track_sub_plan_select(sub_type: String) -> void:
	_send(
		EVT_SUB_PLAN_SELECT,
		{
			"sub_type": _sub_or_unknown(sub_type),
		}
	)


func track_sub_pay(
	sub_state: String, network_type: String, sub_type: String, error_code: String = ""
) -> void:
	_send(
		EVT_SUB_PAY,
		{
			"sub_state": sub_state,
			"network_type": network_type,
			"sub_type": _sub_or_unknown(sub_type),
			"error_code": _sub_error_code(sub_state, error_code),
		}
	)


func track_sub_resume(
	sub_state: String, network_type: String, sub_type: String = "", error_code: String = ""
) -> void:
	_send(
		EVT_SUB_RESUME,
		{
			"sub_state": sub_state,
			"network_type": network_type,
			"sub_type": _sub_or_unknown(sub_type),
			"error_code": _sub_error_code(sub_state, error_code),
		}
	)


## 生成一个广告展示 ID（UUID v4）
func gen_ad_show_id() -> String:
	return _gen_uuid()


## 记住某广告位这次的展示 ID，供广告回调时取用（UniKitManager 调用）
func remember_ad_show_id(placement_type: String, ad_show_id: String) -> void:
	_pending_ad_show_ids[placement_type] = ad_show_id # 同一广告位后一次覆盖前一次


## 取走并清掉某广告位的展示 ID；没有就返回空串
func consume_ad_show_id(placement_type: String) -> String:
	var id: String = _pending_ad_show_ids.get(placement_type, "")
	if id != "":
		_pending_ad_show_ids.erase(placement_type)
	return id


## 上报广告展示耗时（placement 是广告类型，position 是广告位）
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


## 上报插屏广告展示
func track_interstitial_ad_show(ad_show_id: String, level: int, position: String) -> void:
	var params: Dictionary = {
		"ad_show_id": ad_show_id,
		"level": level,
		"position": position,
	}
	_send(EVT_INTERSTITIAL_AD_SHOW, params)


## 上报激励视频展示
func track_rewarded_ad_show(ad_show_id: String, level: int, position: String) -> void:
	var params: Dictionary = {
		"ad_show_id": ad_show_id,
		"level": level,
		"position": position,
	}
	_send(EVT_REWARDED_AD_SHOW, params)


## 上报设置开关点击（state 由调用方按开 = 1 传）
func track_sw_click(sw_name: String, state: int, source: String) -> void:
	var params: Dictionary = {
		"sw_name": sw_name,
		"state": state,
		"source": source,
	}
	_send(EVT_SW_CLICK, params)


## 上报新手引导开始（带触发时的关卡）
func track_new_guide_show(level: int) -> void:
	_send(EVT_NEW_GUIDE_SHOW, {"level": level})


## 上报新手引导结束（time 单位：秒）
func track_new_guide_end(level: int, time_sec: float) -> void:
	_send(EVT_NEW_GUIDE_END, {"level": level, "time": time_sec}) # time 单位为秒


## 上报新手引导走到第几步
func track_new_guide_step(step: int) -> void:
	_send(EVT_NEW_GUIDE_STEP, {"step": step})


func track_golden_fish_guide_show(level: int) -> void:
	_send(EVT_GOLDEN_FISH_GUIDE_SHOW, {"level": level})


func track_golden_fish_guide_end(level: int, time_sec: float) -> void:
	_send(EVT_GOLDEN_FISH_GUIDE_END, {"level": level, "time": time_sec})


## 上报启动阶段耗时：cost_time 本步耗时、total_time 累计（毫秒）
func track_perf_monitor(type: String, step: String, cost_ms: int, total_ms: int) -> void:
	var params: Dictionary = {
		"type": type,
		"step": step,
		"cost_time": cost_ms,
		"total_time": total_ms,
	}
	_send(EVT_PERF_MONITOR, params)


## 上报「从桌面快捷方式冷启动」（Launcher 处理 shortcut 时调用）
func track_remove_app_start() -> void:
	_send(EVT_REMOVE_APP_START, {})


## 上报用户属性「界面语言」（走 setUserProperty，不是事件）
func track_user_property_ui_language(lang_code: String) -> void:
	UniKitManager.set_user_property(UserProp.UI_LANGUAGE, lang_code) # 只同步属性，不发事件


## 上报连胜进度：当前连胜与历史最佳（连胜模块调用）
func track_spark_streak(current_streak: int, best_streak: int) -> void:
	var params: Dictionary = {
		"game_type": _active_game_type,
		"current_streak": current_streak,
		"best_streak": best_streak,
	}
	_send(EVT_SPARK_STREAK, params)


func track_rank_start(rank_id: int) -> void:
	_send(EVT_RANK_START, {"rank_id": rank_id})


func track_rank_data(
	rank_id: int,
	source: String,
	rank: int,
	normal_num: int,
	nick: String,
	avatar: int,
	frame_id: int,
	frame_level: int,
	result_detail: String
) -> void:
	var params: Dictionary = {
		"rank_id": rank_id,
		"rank": rank,
		"normal_num": normal_num,
		"nick": nick,
		"avatar": avatar,
		"frame_id": frame_id,
		"frame_level": frame_level,
		"result_detail": result_detail,
	}
	if source != "":
		params["source"] = source
	_send(EVT_RANK_DATA, params)


func track_frame_get(frame_id: int, source: String) -> void:
	var params: Dictionary = {"frame_id": frame_id}
	if source != "":
		params["source"] = source
	_send(EVT_FRAME_GET, params)


func track_avatar_get(avatar_id: int, source: String) -> void:
	_send(EVT_AVATAR_GET, {"avatar_id": avatar_id, "source": source})


func track_skin_get(skin_id: int, duration_hours: int, source: String) -> void:
	_send(EVT_SKIN_GET, {"skin_id": skin_id, "duration": duration_hours, "source": source})


func track_companion_cat_item_get(
	item_name: String, source: String, item_num: int, item_left: int
) -> void:
	_send(
		EVT_COMPANION_CAT_ITEM_GET,
		{
			"item_name": item_name,
			"source": source,
			"item_num": item_num,
			"item_left": item_left,
		}
	)


func track_companion_cat_item_use(
	item_name: String, source: String, item_num: int, item_left: int, after_fullness: int
) -> void:
	_send(
		EVT_COMPANION_CAT_ITEM_USE,
		{
			"item_name": item_name,
			"source": source,
			"item_num": item_num,
			"item_left": item_left,
			"after_fullness": after_fullness,
		}
	)


# ================= GRT 实验埋点 =================
## 按「留存天数 + 关卡/时长阈值」补报，同一事件只报一次（去重记录存在 GameState 的存档里）
const GRT_PLATFORMS: Array = ["facebook", "appsflyer", "learnings", "firebase"] # 这几个 GRT 事件只发给这 4 个平台

const GRT_LEVEL_D90_LEVELS: Array[int] = [
	2,
	6,
	10,
	15,
	20,
	25,
	30,
	50,
	80,
	120,
	200,
	300,
	500,
	600,
	700,
	800,
	1000,
	1200,
	1500,
	1800,
	2000,
	2500,
	3000,
	3500,
	4000,
	4500,
	5000,
	6000
]

const GRT_LEVEL_D90_MAX_LIVING_DAYS: int = 89 # 超过 89 天的老玩家不再补报 D90 档

const GRT_WINDOW_MAX_LIVING: Dictionary = {"d0": 0, "d2": 1, "d3": 2, "d7": 6} # 窗口 → 允许的最大留存天数，超过就跳过该窗口

## 关卡窗口：窗口 → 触发关卡列表；当前关达到列表里的值就补报（已报过的跳过）
const GRT_LEVEL_WINDOW: Dictionary = {
	"d0": [6, 7, 9, 12],
	"d2": [7, 9, 11, 14],
	"d3": [7, 9, 12, 15],
	"d7": [8, 10, 14, 19],
}

## 时长窗口：窗口 → 累计活跃分钟阈值（分钟）
const GRT_TIME_WINDOW_MIN: Dictionary = {
	"d0": [5, 7, 10, 16],
	"d2": [5, 10, 15, 22],
	"d3": [6, 10, 16, 25],
	"d7": [6, 12, 20, 32],
}


## 通关后按 D90 档位补报 grt_level{N}_d90；报过的（记在 GameState）跳过
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


## 通关后按留存窗口补报 grt_level{N}_{d0|d2|d3|d7}，每个事件只报一次
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


func try_track_grt_time_window(total_active_sec: int) -> void:
	var living_days: int = ABTestManager.living_days.days_since_first_open()
	if living_days < 0:
		return
	@warning_ignore("integer_division")
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
			GameState.mark_grt_event_reported(event_name)


const _PEEKABOO_CAT_BTNS: Array[String] = [
	Btn.PEEKABOO_POT,
	Btn.PEEKABOO_HAMPER,
	Btn.PEEKABOO_BAG,
	Btn.PEEKABOO_LEAF,
	Btn.PEEKABOO_PLANT,
]


func peekaboo_cat_btn_for_prop(prop_index: int) -> String:
	return _PEEKABOO_CAT_BTNS[posmod(prop_index, _PEEKABOO_CAT_BTNS.size())]


# ================= 工具函数 =================
## 把题库的 transform 编号转成埋点用的 qrotate：旋转角度 + 可选的 V/H 翻转前缀
func transform_to_qrotate(transform: int) -> String:
	var rot_part: String = str([0, 90, 180, 270][transform % 4]) # 低 2 位是旋转角度
	if transform >= 8:
		return "V" + rot_part # 8~15 额外带垂直翻转
	if transform >= 4:
		return "H" + rot_part # 4~7 额外带水平翻转
	return rot_part


func _send(event_name: String, params: Dictionary) -> void:
	if _current_game_id != "" and not params.has("game_id"):
		params["game_id"] = _current_game_id
	print("[Tracker] %s %s" % [event_name, JSON.stringify(params)])

	EventBus.emit_event(EventName.TRACK_EVENT, {"event": event_name}.merged(params))
	UniKitManager.send_event(event_name, params)


## 生成 UUID v4 格式字符串（随机 16 字节，取 hex 拼成 8-4-4-4-12）
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
