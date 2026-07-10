extends Node














const EVT_SCR_SHOW: String = "scr_show"
const EVT_DLG_SHOW: String = "dlg_show"
const EVT_BTN_CLICK: String = "btn_click"
const EVT_GAME_START: String = "game_start"
const EVT_GAME_END: String = "game_end"
const EVT_PROP_GET: String = "prop_get"
const EVT_PROP_USE: String = "prop_use"
const EVT_AD_SHOW_TIMING: String = "ad_show_timing"
const EVT_INTERSTITIAL_AD_SHOW: String = "interstitial_ad_show"
const EVT_REWARDED_AD_SHOW: String = "rewarded_ad_show"
const EVT_SW_CLICK: String = "sw_click"
const EVT_NEW_GUIDE_SHOW: String = "new_guide_show"
const EVT_NEW_GUIDE_END: String = "new_guide_end"
const EVT_NEW_GUIDE_STEP: String = "new_guide_step"
const EVT_PERF_MONITOR: String = "perf_monitor"
const EVT_REMOVE_APP_START: String = "remove_app_start"
const EVT_SPARK_STREAK: String = "spark_streak"


class Scr:
    const SPLASH: String = "splash_scr"
    const HOMEPAGE: String = "homepage_scr"
    const NORMAL_GAME: String = "normal_game_scr"
    const NORMAL_GAME_SUCCESS: String = "normal_game_success_scr"
    const NORMAL_GAME_FAIL: String = "normal_game_fail_scr"
    const DAILY_GAME: String = "daily_game_scr"
    const DAILY_GAME_SUCCESS: String = "daily_game_success_scr"
    const DAILY_GAME_FAIL: String = "daily_game_fail_scr"
    const FEEDBACK: String = "feedback_scr"
    const STREAK: String = "streak_scr"
    const GAME_STREAK: String = "game_streak_scr"


class Dlg:
    const PRIVACY: String = "privacy_dlg"
    const PRE_ATT_GUIDE: String = "pre_att_guide_dlg"
    const RATE: String = "rate_dlg"
    const FEEDBACK: String = "feedback_dlg"
    const SETTINGS: String = "settings_dlg"
    const OPTIONS: String = "options_dlg"
    const GAME_NORMAL_TOAST: String = "game_normal_toast_dlg"
    const GAME_HARD_TOAST: String = "game_hard_toast_dlg"
    const REWARD_FAIL: String = "reward_fail_dlg"
    const DAILY_AUTO_MARK_POPUP: String = "daily_auto_mark_popup_dlg"
    const LANGUAGE_PICKER: String = "language_picker_dlg"



class Btn:

    const NORMAL_PLAY: String = "normal_play"
    const DAILY_PLAY: String = "daily_play"
    const SETTINGS: String = "settings"
    const STREAK: String = "streak"

    const BACK: String = "back"
    const HINT: String = "hint"
    const LOCATE: String = "locate"
    const CLEAR: String = "clear"
    const COORD: String = "coord"
    const HINT_APPLY: String = "hint_apply"
    const HINT_STOP: String = "hint_stop"
    const HINT_DETAIL: String = "hint_detail"
    const OPTIONS: String = "options"

    const LEVEL_PLAY: String = "level_play"
    const REVIVE: String = "revive"
    const RESTART: String = "restart"
    const TRY_AGAIN: String = "try_again"
    const CONTINUE: String = "continue"

    const CLOSE: String = "close"
    const FEEDBACK: String = "feedback"
    const TERMS: String = "terms"
    const POLICY: String = "policy"
    const PRIVACY: String = "privacy"
    const PRIVACY_PREFERENCE: String = "privacy_preference"

    const LANGUAGE: String = "language"
    const LANGUAGE_CONFIRM: String = "language_confirm"
    const LANGUAGE_CANCEL: String = "language_cancel"

    const SUBMIT: String = "submit"
    const FEEDBACK_RECORD: String = "feedback_record"

    const ACCEPT: String = "accept"
    const ATT_CONTINUE: String = "att_continue"
    const RATE_US: String = "rate_us"
    const COLLECT: String = "collect"


class Prop:
    const HINT: String = "hint"
    const LOCATE: String = "locate"
    const UNDO: String = "undo"
    const AUTOX: String = "autox"

class PropSource:
    const HINT_REWARD_AD: String = "hint_reward_ad"
    const LOCATE_REWARD_AD: String = "locate_reward_ad"
    const UNDO_REWARD_AD: String = "undo_reward_ad"
    const REWARD_FAIL_DLG: String = "reward_fail_dlg"
    const STREAK_CHEST: String = "streak_chest"
    const STREAK_REWARD_AD: String = "streak_reward_ad"
    const SWITCH_GROUP: String = "switch_group"
    const AUTOX_REWARD_AD: String = "autox_reward_ad"

class Sw:
    const MUSIC: String = "music_sw"
    const SOUND: String = "sound_sw"
    const VIBRATION: String = "vibration_sw"




class UserProp:
    const UI_LANGUAGE: String = "ui_language"

class Placement:
    const INTERSTITIAL: String = "interstitial"
    const REWARD: String = "reward"
    const APPOPEN: String = "appopen"


class AdPos:

    const NORMAL_GAME_FAIL: String = "normal_game_fail"
    const DAILY_GAME_FAIL: String = "daily_game_fail"
    const PROPS_NORMAL_HINT: String = "props_normal_hint"
    const PROPS_NORMAL_LOCATE: String = "props_normal_locate"
    const PROPS_DAILY_HINT: String = "props_daily_hint"
    const PROPS_DAILY_LOCATE: String = "props_daily_locate"
    const STREAK_X2_REWARD: String = "streak_x2_reward"
    const AUTOX_REWARD: String = "autox_reward"

    const NORMAL_START: String = "normal_start"
    const NORMAL_SUCCESS: String = "normal_success"
    const NORMAL_RESTART: String = "normal_restart"
    const NORMAL_CONTINUE: String = "normal_continue"


class GameType:
    const NORMAL: String = "normal"
    const DAILY: String = "daily"

class GameStatus:
    const NEW: String = "new"
    const CONTINUE: String = "continue"
    const RESTART: String = "restart"

class GameResult:
    const WIN: String = "win"
    const FAIL: String = "fail"
    const QUIT: String = "quit"


class PerfStep:
    const LOAD_SPLASH: String = "load_splash"
    const INIT_GAME_MANAGER: String = "init_game_manager"
    const INIT_AD_MANAGER: String = "init_ad_manager"
    const END: String = "end"





var _current_game_id: String = ""


var _active_game_type: String = ""



var _source_stack: Array[String] = []

var _pending_ad_show_ids: Dictionary = {}












var _main_game_stats: Dictionary = {}
var _daily_game_stats: Dictionary = {}

const _ROUND_STAT_KEYS: Array[String] = [
    "hint_used", "locate_used", 
    "hint_apply_used", "hint_stop_used", "hint_detail_used", 
    "clear_used", "step_used", "erase_count", 
]


func get_game_id() -> String:
    return _current_game_id






func set_active_game_type(game_type: String) -> void :
    _active_game_type = game_type
    _current_game_id = GameState.get_persisted_game_id(game_type)

    var d: Dictionary = _get_active_stats_dict()
    if d.is_empty():
        var persisted: Dictionary = GameState.get_game_round_stats(game_type)
        if not persisted.is_empty():
            d.merge(persisted)



func new_game_id(game_type: String) -> String:
    _active_game_type = game_type
    _current_game_id = _gen_uuid()
    _get_active_stats_dict().clear()

    GameState.reset_game_total_stats(game_type)

    GameState.reset_game_round_stats(game_type)


    GameState.set_persisted_game_id(game_type, _current_game_id)
    return _current_game_id


func inc_stat(key: String, delta: int = 1) -> void :
    var d: Dictionary = _get_active_stats_dict()
    d[key] = int(d.get(key, 0)) + delta
    GameState.persist_game_round_stats(_active_game_type, d)


func get_stat(key: String) -> int:
    return int(_get_active_stats_dict().get(key, 0))



func reset_round_stats() -> void :
    var d: Dictionary = _get_active_stats_dict()
    for key: String in _ROUND_STAT_KEYS:
        d.erase(key)
    GameState.persist_game_round_stats(_active_game_type, d)



func on_restart() -> void :
    reset_round_stats()
    inc_stat("restart_count")




func _get_active_stats_dict() -> Dictionary:
    if _active_game_type == GameType.DAILY:
        return _daily_game_stats
    return _main_game_stats


func get_current_source() -> String:
    return _source_stack.back() if not _source_stack.is_empty() else ""



func notify_dlg_closed(dlg_name: String) -> void :
    if dlg_name == "":
        return
    var idx: int = _source_stack.rfind(dlg_name)
    if idx >= 0:
        _source_stack.resize(idx)



func track_scr_show(scr_name: String, source: String = "") -> void :
    if scr_name == "":
        return
    var prev_source: String = source if source != "" else get_current_source()
    var params: Dictionary = {
        "scr_name": scr_name, 
    }
    if prev_source != "":
        params["source"] = prev_source
    _send(EVT_SCR_SHOW, params)

    _source_stack.clear()
    _source_stack.append(scr_name)


func track_dlg_show(dlg_name: String, source: String = "", extra: Dictionary = {}) -> void :
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
    _send(EVT_DLG_SHOW, params)
    _source_stack.append(dlg_name)





func track_btn_click(btn_name: String, source_node: Node = null, extra: Dictionary = {}) -> void :
    if btn_name == "":
        return
    var source: String
    if source_node != null:
        source = _resolve_source_from_node(source_node)
    else:
        source = get_current_source()
        push_warning("Tracker.track_btn_click('%s') 未传 source_node，退化到 source 栈顶" % btn_name)
    var params: Dictionary = {
        "btn_name": btn_name, 
    }
    if source != "":
        params["source"] = source
    for k in extra:
        params[k] = extra[k]
    _send(EVT_BTN_CLICK, params)


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
    scale: int
) -> void :
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

func track_game_end(extra: Dictionary) -> void :






    _send(EVT_GAME_END, extra)


func track_prop_get(prop_name: String, source: String, prop_num: int, prop_left: int) -> void :
    var params: Dictionary = {
        "prop_name": prop_name, 
        "source": source, 
        "prop_num": prop_num, 
        "prop_left": prop_left, 
    }
    _send(EVT_PROP_GET, params)

func track_prop_use(prop_name: String, source: String, prop_num: int, prop_left: int) -> void :
    var params: Dictionary = {
        "prop_name": prop_name, 
        "source": source, 
        "prop_num": prop_num, 
        "prop_left": prop_left, 
    }
    _send(EVT_PROP_USE, params)



func gen_ad_show_id() -> String:
    return _gen_uuid()


func remember_ad_show_id(placement_type: String, ad_show_id: String) -> void :
    _pending_ad_show_ids[placement_type] = ad_show_id


func consume_ad_show_id(placement_type: String) -> String:
    var id: String = _pending_ad_show_ids.get(placement_type, "")
    if id != "":
        _pending_ad_show_ids.erase(placement_type)
    return id

func track_ad_show_timing(
    ad_show_id: String, 
    placement: String, 
    placement_type: String, 
    position: String
) -> void :
    var params: Dictionary = {
        "ad_show_id": ad_show_id, 
        "placement": placement, 
        "placement_type": placement_type, 
        "position": position, 
    }
    _send(EVT_AD_SHOW_TIMING, params)

func track_interstitial_ad_show(ad_show_id: String, level: int, position: String) -> void :
    var params: Dictionary = {
        "ad_show_id": ad_show_id, 
        "level": level, 
        "position": position, 
    }
    _send(EVT_INTERSTITIAL_AD_SHOW, params)

func track_rewarded_ad_show(ad_show_id: String, level: int, position: String) -> void :
    var params: Dictionary = {
        "ad_show_id": ad_show_id, 
        "level": level, 
        "position": position, 
    }
    _send(EVT_REWARDED_AD_SHOW, params)


func track_sw_click(sw_name: String, state: int, source: String) -> void :
    var params: Dictionary = {
        "sw_name": sw_name, 
        "state": state, 
        "source": source, 
    }
    _send(EVT_SW_CLICK, params)


func track_new_guide_show(level: int) -> void :
    _send(EVT_NEW_GUIDE_SHOW, {"level": level})

func track_new_guide_end(level: int, time_sec: float) -> void :
    _send(EVT_NEW_GUIDE_END, {"level": level, "time": time_sec})

func track_new_guide_step(step: int) -> void :
    _send(EVT_NEW_GUIDE_STEP, {"step": step})


func track_perf_monitor(type: String, step: String, cost_ms: int, total_ms: int) -> void :
    var params: Dictionary = {
        "type": type, 
        "step": step, 
        "cost_time": cost_ms, 
        "total_time": total_ms, 
    }
    _send(EVT_PERF_MONITOR, params)


func track_remove_app_start() -> void :
    _send(EVT_REMOVE_APP_START, {})






func track_user_property_ui_language(lang_code: String) -> void :
    UniKitManager.set_user_property(UserProp.UI_LANGUAGE, lang_code)






func track_spark_streak(current_streak: int, best_streak: int) -> void :
    var params: Dictionary = {
        "game_type": _active_game_type, 
        "current_streak": current_streak, 
        "best_streak": best_streak, 
    }
    _send(EVT_SPARK_STREAK, params)




const GRT_PLATFORMS: Array = ["facebook", "appsflyer", "learnings", "firebase"]

const GRT_LEVEL_D90_LEVELS: Array[int] = [2, 6, 10, 15, 20, 25, 30, 50, 80, 120, 200, 300, 500, 600, 700, 800]

const GRT_LEVEL_D90_MAX_LIVING_DAYS: int = 89



const GRT_WINDOW_MAX_LIVING: Dictionary = {"d0": 0, "d2": 1, "d3": 2, "d7": 6}

const GRT_LEVEL_WINDOW: Dictionary = {
    "d0": [6, 7, 9, 12], 
    "d2": [7, 9, 11, 14], 
    "d3": [7, 9, 12, 15], 
    "d7": [8, 10, 14, 19], 
}

const GRT_TIME_WINDOW_MIN: Dictionary = {
    "d0": [5, 7, 10, 16], 
    "d2": [5, 10, 15, 22], 
    "d3": [6, 10, 16, 25], 
    "d7": [6, 12, 20, 32], 
}




























func try_track_grt_level_pass(level_num: int) -> void :

    var living_days: int = ABTestManager.living_days.days_since_first_open()
    if living_days < 0 or living_days > GRT_LEVEL_D90_MAX_LIVING_DAYS:
        return
    for lv: int in GRT_LEVEL_D90_LEVELS:
        if lv > level_num:
            break
        if GameState.has_grt_level_d90_reported(lv):
            continue
        var event_name: String = "grt_level%d_d90" % lv
        print("[Tracker][GRT] %s livingdays=%d trigger_level=%d platforms=%s" %
                [event_name, living_days, level_num, str(GRT_PLATFORMS)])
        UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0)
        GameState.mark_grt_level_d90_reported(lv)





func try_track_grt_level_window(level_num: int) -> void :

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
            print("[Tracker][GRT] %s livingdays=%d trigger_level=%d platforms=%s" %
                    [event_name, living_days, level_num, str(GRT_PLATFORMS)])
            UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0)
            GameState.mark_grt_event_reported(event_name)




func try_track_grt_time_window(total_active_sec: int) -> void :

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
            print("[Tracker][GRT] %s livingdays=%d total_min=%d platforms=%s" %
                    [event_name, living_days, total_min, str(GRT_PLATFORMS)])
            UniKitManager.send_event(event_name, {}, GRT_PLATFORMS, 0.0)
            GameState.mark_grt_event_reported(event_name)






func transform_to_qrotate(transform: int) -> String:
    var rot_part: String = str([0, 90, 180, 270][transform % 4])
    if transform >= 8:
        return "V" + rot_part
    if transform >= 4:
        return "H" + rot_part
    return rot_part


func _send(event_name: String, params: Dictionary) -> void :

    if _current_game_id != "" and not params.has("game_id"):
        params["game_id"] = _current_game_id
    print("[Tracker] %s %s" % [event_name, JSON.stringify(params)])
    UniKitManager.send_event(event_name, params)


func _gen_uuid() -> String:
    var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
    bytes[6] = (bytes[6] & 15) | 64
    bytes[8] = (bytes[8] & 63) | 128
    var hex: String = bytes.hex_encode()
    return "%s-%s-%s-%s-%s" % [
        hex.substr(0, 8), 
        hex.substr(8, 4), 
        hex.substr(12, 4), 
        hex.substr(16, 4), 
        hex.substr(20, 12), 
    ]
