extends Node



























enum DisplayType{
    DIRECT, 
    STREAK_GIFT, 
}

const _RENDER_DIRECT: Script = preload("res://scripts/module/award/render/award_render_direct.gd")
const _RENDER_STREAK_GIFT: Script = preload("res://scripts/module/award/render/award_render_streak_gift.gd")


var _renders: Dictionary = {}








func _ready() -> void :
    _sweep_in_flight_on_cold_start()











func _sweep_in_flight_on_cold_start() -> void :
    var entries: Array = GameState.get_in_flight_awards()
    for entry in entries:
        _persist_award(int(entry.get("uid", -1)))
















func dispatch(items: Array, display_type: int, reason: String, bonus_reason: String = "") -> int:
    if items.is_empty():
        push_error("AwardManager.dispatch: items 为空")
        return -1
    if reason == "":
        push_error("AwardManager.dispatch: reason 为空(必传归因字符串,见 Tracker.PropSource.*)")
        return -1

    for it in items:
        var k: String = ""
        var c: int = 0
        if it is AwardItem:
            k = (it as AwardItem).kind
            c = (it as AwardItem).count
        elif it is Dictionary:
            k = str(it.get("kind", ""))
            c = int(it.get("count", 0))
        if k == "" or c <= 0:
            push_error("AwardManager.dispatch: 含无效 item(kind=%s, count=%d),整笔拒绝" % [k, c])
            return -1
    var uid: int = GlobalUniqueId.next()
    var entry: Dictionary = {
        "uid": uid, 
        "items": _items_to_dicts(items), 
        "display_type": display_type, 
        "reason": reason, 
        "bonus_reason": bonus_reason, 
    }
    GameState.add_in_flight_award(entry)
    var render: AwardRender = _make_render(display_type)
    _renders[uid] = render
    render.set_info(entry)
    return uid




func show_award(uid: int, display_params: Dictionary = {}) -> void :
    if not _renders.has(uid):
        push_warning("AwardManager.show_award: uid=%d 无 Render 实例(可能已 persist 或被跨进程清扫)" % uid)
        return
    (_renders[uid] as AwardRender).show_award(display_params)









func continue_when_award_end(uid: int, callback: Callable) -> void :
    if not _renders.has(uid):
        push_warning("AwardManager.continue_when_award_end: uid=%d 无 Render 实例(可能已 persist / 不存在)" % uid)
        return
    (_renders[uid] as AwardRender).award_end.connect(
        func(end_uid: int) -> void : callback.call(end_uid), 
        CONNECT_ONE_SHOT, 
    )





func double_award(uid: int) -> void :
    if not _renders.has(uid):
        push_warning("AwardManager.double_award: uid=%d 无 Render 实例" % uid)
        return
    (_renders[uid] as AwardRender).double_award()













func _persist_award(uid: int) -> void :
    var entry: Dictionary = GameState.find_in_flight_award(uid)
    if entry.is_empty():
        push_warning("AwardManager._persist_award: uid=%d 不在中转队列(重复 persist?)" % uid)
        _renders.erase(uid)
        return
    GameState.remove_in_flight_award(uid)
    var items: Array = entry.get("items", [])
    var reason: String = str(entry.get("reason", ""))
    var granted: int = 0
    for it_dict: Dictionary in items:
        var kind: String = str(it_dict.get("kind", ""))
        var count: int = int(it_dict.get("count", 0))
        if kind == "" or count <= 0:
            push_warning("AwardManager._persist_award: uid=%d 含无效 item(kind=%s, count=%d),跳过" % [uid, kind, count])
            continue
        var current: int = GameState.get_tool_count(kind)
        GameState.set_tool_count(kind, current + count)
        Tracker.track_prop_get(kind, reason, count, GameState.get_tool_count(kind))
        granted += 1


    if bool(entry.get("doubled", false)):
        var bonus_reason: String = str(entry.get("bonus_reason", ""))
        if bonus_reason == "":

            bonus_reason = reason
            push_warning("AwardManager._persist_award: uid=%d doubled 但无 bonus_reason,翻倍份额回退原 reason" % uid)
        for it_dict: Dictionary in items:
            var kind: String = str(it_dict.get("kind", ""))
            var count: int = int(it_dict.get("count", 0))
            if kind == "" or count <= 0:
                continue
            var current: int = GameState.get_tool_count(kind)
            GameState.set_tool_count(kind, current + count)
            Tracker.track_prop_get(kind, bonus_reason, count, GameState.get_tool_count(kind))
            granted += 1
    if granted == 0:
        push_warning("AwardManager._persist_award: uid=%d 所有 items 无效,无道具入账" % uid)
    _renders.erase(uid)

func _make_render(display_type: int) -> AwardRender:
    match display_type:
        DisplayType.DIRECT:
            return _RENDER_DIRECT.new() as AwardRender
        DisplayType.STREAK_GIFT:
            return _RENDER_STREAK_GIFT.new() as AwardRender
        _:
            push_error("AwardManager._make_render: 未知 display_type=%d,默认 DIRECT" % display_type)
            return _RENDER_DIRECT.new() as AwardRender

func _items_to_dicts(items: Array) -> Array:
    var out: Array = []
    for it in items:
        if it is AwardItem:
            out.append((it as AwardItem).to_dict())
        elif it is Dictionary:
            out.append(it)
        else:
            push_error("AwardManager.dispatch: items 含非 AwardItem/Dictionary 类型: %s" % str(it))
    return out
