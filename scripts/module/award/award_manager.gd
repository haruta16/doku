## 奖励账本管理器：先持久化待发记录，再由展示器触发入账，冷启动补发未完成奖励。
extends Node

enum DisplayType {
	DIRECT,
	STREAK_GIFT,
	RANK_GIFT,
}

# ---- 渲染实现（按形态 preload，dispatch 时 new 出实例） ----
const _RENDER_DIRECT: Script = preload("res://scripts/module/award/render/award_render_direct.gd")
const _RENDER_STREAK_GIFT: Script = preload(
	"res://scripts/module/award/render/award_render_streak_gift.gd"
)
const _RENDER_RANK_GIFT: Script = preload(
	"res://scripts/module/award/render/award_render_rank_gift.gd"
)

# ---- 运行时状态 ----
var _renders: Dictionary = {} # uid → AwardRender 实例；入账后从这里移除


# ================= 生命周期 =================
## 节点就绪时做一次冷启动补发
func _ready() -> void:
	# 冷启动补发：上次没走完的奖励不能丢
	_sweep_in_flight_on_cold_start()


## 扫描存档里的「中转队列」，逐笔直接入账（跳过界面）
func _sweep_in_flight_on_cold_start() -> void:
	# 中转队列写进存档，进程被杀也还在
	var entries: Array = GameState.get_in_flight_awards()
	for entry in entries:
		_persist_award(int(entry.get("uid", -1)))


## 先整笔验证奖励与归因，再写入待发账本并创建展示器，返回本次进程的奖励 UID。
func dispatch(items: Array, display_type: int, reason: String, bonus_reason: String = "") -> int:
	if items.is_empty():
		push_error("AwardManager.dispatch: items 为空")
		return -1
	if reason == "":
		push_error("AwardManager.dispatch: reason 为空(必传归因字符串,见 Tracker.PropSource.*)")
		return -1

	for it in items:
		var valid: bool = false
		if it is AwardItem:
			valid = (it as AwardItem).is_valid()
		elif it is Dictionary:
			valid = _item_dict_valid(it)
		if not valid:
			push_error(
				(
					"AwardManager.dispatch: 含无效 item(%s),整笔拒绝"
					% str(it.to_dict() if it is AwardItem else it)
				)
			)
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


## 触发展示（STREAK_GIFT 这类要玩家操作的形态用）
func show_award(uid: int, display_params: Dictionary = {}) -> void:
	# uid 不在说明已入账，或被冷启动清扫过
	if not _renders.has(uid):
		push_warning("AwardManager.show_award: uid=%d 无 Render 实例(可能已 persist 或被跨进程清扫)" % uid)
		return
	(_renders[uid] as AwardRender).show_award(display_params)


## 注册「本笔奖励结束」回调，只触发一次（奖励入账后）
func continue_when_award_end(uid: int, callback: Callable) -> void:
	# 没有 Render 就没法挂回调
	if not _renders.has(uid):
		push_warning(
			"AwardManager.continue_when_award_end: uid=%d 无 Render 实例(可能已 persist / 不存在)" % uid
		)
		return
	# 把内部信号桥成外部回调，ONE_SHOT 保证只回调一次
	(_renders[uid] as AwardRender).award_end.connect(
		func(end_uid: int) -> void: callback.call(end_uid),
		CONNECT_ONE_SHOT,
	)


## 标记本笔奖励翻倍：入账时按 bonus_reason 再发一份
func double_award(uid: int) -> void:
	# 没有 Render 就没法标记
	if not _renders.has(uid):
		push_warning("AwardManager.double_award: uid=%d 无 Render 实例" % uid)
		return
	(_renders[uid] as AwardRender).double_award()


## 从待发账本取出并移除记录，再发放有效条目；翻倍只追加道具，不重复头像框。
func _persist_award(uid: int) -> void:
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
		if _apply_item(it_dict, reason):
			granted += 1

	if bool(entry.get("doubled", false)):
		var bonus_reason: String = str(entry.get("bonus_reason", ""))
		if bonus_reason == "":
			bonus_reason = reason
			push_warning(
				"AwardManager._persist_award: uid=%d doubled 但无 bonus_reason,翻倍份额回退原 reason" % uid
			)
		for it_dict: Dictionary in items:
			if int(it_dict.get("category", AwardItem.Category.TOOL)) != AwardItem.Category.TOOL:
				continue
			if _apply_item(it_dict, bonus_reason):
				granted += 1
	if granted == 0:
		push_warning("AwardManager._persist_award: uid=%d 所有 items 无效,无奖励入账" % uid)
	_renders.erase(uid)


## 头像框交给 ProfileService，道具直接累加 GameState 库存，并分别记录获取来源。
func _apply_item(it_dict: Dictionary, reason: String) -> bool:
	if not _item_dict_valid(it_dict):
		push_warning("AwardManager._apply_item: 无效 item(%s),跳过" % str(it_dict))
		return false
	var count: int = int(it_dict.get("count", 0))
	var category: int = int(it_dict.get("category", AwardItem.Category.TOOL))
	if category == AwardItem.Category.FRAME:
		var frame_id: int = int(it_dict.get("frame_id", 0))
		var ok: bool = ProfileService.grant_frame(frame_id, count)

		if ok:
			Tracker.track_frame_get(frame_id, reason)
		return ok
	var kind: String = str(it_dict.get("kind", ""))
	var current: int = GameState.get_tool_count(kind)
	GameState.set_tool_count(kind, current + count)
	Tracker.track_prop_get(kind, reason, count, GameState.get_tool_count(kind))
	return true


func _item_dict_valid(it_dict: Dictionary) -> bool:
	if int(it_dict.get("count", 0)) <= 0:
		return false
	if int(it_dict.get("category", AwardItem.Category.TOOL)) == AwardItem.Category.FRAME:
		return int(it_dict.get("frame_id", 0)) > 0
	return str(it_dict.get("kind", "")) != ""


func _make_render(display_type: int) -> AwardRender:
	match display_type:
		DisplayType.DIRECT:
			return _RENDER_DIRECT.new() as AwardRender
		DisplayType.STREAK_GIFT:
			return _RENDER_STREAK_GIFT.new() as AwardRender
		DisplayType.RANK_GIFT:
			return _RENDER_RANK_GIFT.new() as AwardRender
		_:
			push_error("AwardManager._make_render: 未知 display_type=%d,默认 DIRECT" % display_type)
			return _RENDER_DIRECT.new() as AwardRender


## 把入参统一成 Dictionary 数组（AwardItem → dict，Dictionary 原样保留）
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
