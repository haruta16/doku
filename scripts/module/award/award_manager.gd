# 奖励总闸（Autoload 节点）：dispatch 登记奖励并选渲染形态，真正入账在 _persist_award
extends Node

# 展示形态：DIRECT 立即到账（无界面）/ STREAK_GIFT 走签到宝箱弹窗
enum DisplayType {
	DIRECT, # 直接入账，不弹界面
	STREAK_GIFT, # 弹签到宝箱页，玩家操作后才入账
}

# ---- 渲染实现（按形态 preload，dispatch 时 new 出实例） ----
const _RENDER_DIRECT: Script = preload("res://scripts/module/award/render/award_render_direct.gd")
const _RENDER_STREAK_GIFT: Script = preload(
	"res://scripts/module/award/render/award_render_streak_gift.gd"
)

# ---- 运行时状态 ----
var _renders: Dictionary = {} # uid → AwardRender 实例；入账后从这里移除


# ================= 生命周期 =================
# 节点就绪时做一次冷启动补发
func _ready() -> void:
	# 冷启动补发：上次没走完的奖励不能丢
	_sweep_in_flight_on_cold_start()


# 扫描存档里的「中转队列」，逐笔直接入账（跳过界面）
func _sweep_in_flight_on_cold_start() -> void:
	# 中转队列写进存档，进程被杀也还在
	var entries: Array = GameState.get_in_flight_awards()
	for entry in entries:
		_persist_award(int(entry.get("uid", -1)))


# 派发一笔奖励：校验 → 记进中转队列 → 建 Render，返回 uid；失败返回 -1
func dispatch(items: Array, display_type: int, reason: String, bonus_reason: String = "") -> int:
	# 空 items 直接拒绝
	if items.is_empty():
		push_error("AwardManager.dispatch: items 为空")
		return -1
	# reason 必传：道具来源归因（Tracker.PropSource.*）
	if reason == "":
		push_error("AwardManager.dispatch: reason 为空(必传归因字符串,见 Tracker.PropSource.*)")
		return -1

	# 逐项校验：kind 非空且 count > 0，否则整笔拒绝
	for it in items:
		var k: String = ""
		var c: int = 0
		# 兼容 AwardItem 与 Dictionary 两种入参
		if it is AwardItem:
			k = (it as AwardItem).kind
			c = (it as AwardItem).count
		elif it is Dictionary:
			k = str(it.get("kind", ""))
			c = int(it.get("count", 0))
		if k == "" or c <= 0:
			push_error("AwardManager.dispatch: 含无效 item(kind=%s, count=%d),整笔拒绝" % [k, c])
			return -1
	# uid 全局唯一，调用方靠它 show_award / double_award
	var uid: int = GlobalUniqueId.next()
	# 先落进中转队列（写存档），再建 Render
	var entry: Dictionary = {
		"uid": uid,
		"items": _items_to_dicts(items),
		"display_type": display_type,
		"reason": reason,
		"bonus_reason": bonus_reason,
	}
	GameState.add_in_flight_award(entry)
	# 建 Render 并注入数据：DIRECT 形态在这一步就完成入账
	var render: AwardRender = _make_render(display_type)
	_renders[uid] = render
	render.set_info(entry)
	# 把 uid 交回调用方，供后续 show / double / 等结束
	return uid


# 触发展示（STREAK_GIFT 这类要玩家操作的形态用）
func show_award(uid: int, display_params: Dictionary = {}) -> void:
	# uid 不在说明已入账，或被冷启动清扫过
	if not _renders.has(uid):
		push_warning("AwardManager.show_award: uid=%d 无 Render 实例(可能已 persist 或被跨进程清扫)" % uid)
		return
	(_renders[uid] as AwardRender).show_award(display_params)


# 注册「本笔奖励结束」回调，只触发一次（奖励入账后）
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


# 标记本笔奖励翻倍：入账时按 bonus_reason 再发一份
func double_award(uid: int) -> void:
	# 没有 Render 就没法标记
	if not _renders.has(uid):
		push_warning("AwardManager.double_award: uid=%d 无 Render 实例" % uid)
		return
	(_renders[uid] as AwardRender).double_award()


# 真正入账：写 GameState 道具数、记埋点、清中转队列；doubled 时再发一份
func _persist_award(uid: int) -> void:
	# 从存档队列里找到这一笔
	var entry: Dictionary = GameState.find_in_flight_award(uid)
	# 不在队列说明已经入账过，只清内存
	if entry.is_empty():
		push_warning("AwardManager._persist_award: uid=%d 不在中转队列(重复 persist?)" % uid)
		_renders.erase(uid)
		return
	# 先出队再入账，避免中途异常导致重复发放
	GameState.remove_in_flight_award(uid)
	var items: Array = entry.get("items", [])
	var reason: String = str(entry.get("reason", ""))
	var granted: int = 0
	# 第一份：正常份额
	for it_dict: Dictionary in items:
		var kind: String = str(it_dict.get("kind", ""))
		var count: int = int(it_dict.get("count", 0))
		if kind == "" or count <= 0:
			push_warning(
				(
					"AwardManager._persist_award: uid=%d 含无效 item(kind=%s, count=%d),跳过"
					% [uid, kind, count]
				)
			)
			continue
		# 累加道具数量并记一条获取埋点
		var current: int = GameState.get_tool_count(kind)
		GameState.set_tool_count(kind, current + count)
		Tracker.track_prop_get(kind, reason, count, GameState.get_tool_count(kind))
		granted += 1

	# 第二份：翻倍份额（归因用 bonus_reason）
	if bool(entry.get("doubled", false)):
		var bonus_reason: String = str(entry.get("bonus_reason", ""))
		# 没配 bonus_reason 就退回原 reason
		if bonus_reason == "":
			bonus_reason = reason
			push_warning(
				"AwardManager._persist_award: uid=%d doubled 但无 bonus_reason,翻倍份额回退原 reason" % uid
			)
		for it_dict: Dictionary in items:
			var kind: String = str(it_dict.get("kind", ""))
			var count: int = int(it_dict.get("count", 0))
			if kind == "" or count <= 0:
				continue
			var current: int = GameState.get_tool_count(kind)
			GameState.set_tool_count(kind, current + count)
			Tracker.track_prop_get(kind, bonus_reason, count, GameState.get_tool_count(kind))
			granted += 1
	# 全部无效时告警：这一笔不会到账
	if granted == 0:
		push_warning("AwardManager._persist_award: uid=%d 所有 items 无效,无道具入账" % uid)
	# 入账完成，释放 Render
	_renders.erase(uid)


# 按 display_type 造渲染实现，未知类型告警并回退 DIRECT
func _make_render(display_type: int) -> AwardRender:
	match display_type:
		DisplayType.DIRECT:
			return _RENDER_DIRECT.new() as AwardRender
		DisplayType.STREAK_GIFT:
			return _RENDER_STREAK_GIFT.new() as AwardRender
		_:
			push_error("AwardManager._make_render: 未知 display_type=%d,默认 DIRECT" % display_type)
			return _RENDER_DIRECT.new() as AwardRender


# 把入参统一成 Dictionary 数组（AwardItem → dict，Dictionary 原样保留）
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
