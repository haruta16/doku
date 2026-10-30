## 奖励总闸（Autoload 节点）：dispatch 登记奖励并选渲染形态，真正入账在 _persist_award
extends Node

# 展示形态：DIRECT 立即到账（无界面）/ STREAK_GIFT 走签到宝箱弹窗
enum DisplayType {
	DIRECT, # 直接入账，不弹界面
	STREAK_GIFT, # 弹签到宝箱页，玩家操作后才入账
}

# ---- 渲染实现（按形态 preload，dispatch 时 new 出实例） ----
const _RENDER_DIRECT: Script = preload("res://products/meowdoku/app/features/award/render/award_render_direct.gd")
const _RENDER_STREAK_GIFT: Script = preload(
	"res://products/meowdoku/app/features/award/render/award_render_streak_gift.gd"
)

# ---- 运行时状态 ----
var _renders: Dictionary = {} # uid → AwardRender 实例；入账后从这里移除
var _generation: int = 0 # 清档会复用 uid；旧提交回执不得操作新档里的同号奖励


# ================= 生命周期 =================
## 节点就绪时做一次冷启动补发
func _ready() -> void:
	GameState.all_data_reset.connect(_clear_runtime_awards)
	# 冷启动补发：上次没走完的奖励不能丢
	_sweep_in_flight_on_cold_start()


func _clear_runtime_awards() -> void:
	_generation += 1
	_renders.clear()


## 扫描存档里的「中转队列」，逐笔直接入账（跳过界面）
func _sweep_in_flight_on_cold_start() -> void:
	# 中转队列写进存档，进程被杀也还在
	var generation: int = _generation
	var entries: Array = GameState.get_in_flight_awards()
	for entry in entries:
		if generation != _generation:
			break
		_persist_award(int(entry.get("uid", -1)))


## 派发一笔奖励：校验 → 记进中转队列 → 建 Render，返回 uid；失败返回 -1
func dispatch(items: Array, display_type: int, reason: String, bonus_reason: String = "", claim_key: String = "") -> int:
	var normalized := _items_to_dicts(items)
	var generation: int = _generation
	var result: Dictionary = GameState.get_economy_service().register_award(normalized, display_type, reason, bonus_reason, claim_key)
	if generation != _generation:
		return -1
	if not result.get("ok", false):
		push_error("[AwardManager] 奖励未登记: " + str(result))
		return -1
	var uid: int = int(result.uid)
	attach_award(uid)
	return uid


## 为已经在业务事务中登记的奖励附加展示，不重复登记或生成流水。
func attach_award(uid: int) -> bool:
	if _renders.has(uid):
		return true
	var entry := GameState.find_in_flight_award(uid)
	if entry.is_empty():
		return false
	var render: AwardRender = _make_render(int(entry.get("display_type", DisplayType.DIRECT)))
	_renders[uid] = render
	render.set_info(entry)
	return true


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
func double_award(uid: int) -> bool:
	var generation: int = _generation
	var result: Dictionary = GameState.get_economy_service().double_award(uid)
	if generation != _generation:
		return false
	if not result.get("ok", false):
		push_error("[AwardManager] 翻倍资格未保存: " + str(result))
		return false
	return true


## 真正入账：写 GameState 道具数、记埋点、清中转队列；doubled 时再发一份
func _persist_award(uid: int) -> bool:
	var generation: int = _generation
	var result: Dictionary = GameState.get_economy_service().claim_award(uid)
	if generation != _generation:
		return false
	if not result.get("ok", false):
		push_error("[AwardManager] 奖励尚未入账，保留待领取记录: " + str(result))
		return false
	for grant: Dictionary in result.get("grants", []):
		Tracker.track_prop_get(str(grant.kind), str(grant.reason), int(grant.count), int(grant.balance))
	_renders.erase(uid)
	return true


## 按 display_type 造渲染实现，未知类型告警并回退 DIRECT
func _make_render(display_type: int) -> AwardRender:
	match display_type:
		DisplayType.DIRECT:
			return _RENDER_DIRECT.new() as AwardRender
		DisplayType.STREAK_GIFT:
			return _RENDER_STREAK_GIFT.new() as AwardRender
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
			out.append(it.duplicate(true))
		else:
			push_error("AwardManager.dispatch: items 含非 AwardItem/Dictionary 类型: %s" % str(it))
			return []
	return out
