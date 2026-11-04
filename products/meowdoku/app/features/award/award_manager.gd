## 奖励表现入口（Autoload）：dispatch 先持久登记待领流水，再为 uid 附加展示对象。
## _persist_award 委托 EconomyService 一次提交资产和队列移除；本节点只在成功后记埋点、清表现缓存。
extends Node

# 展示形态只决定何时演出/请求领取，资产入账和幂等仍由核心奖励事务保证。
enum DisplayType {
	DIRECT, # 直接入账，不弹界面
	STREAK_GIFT, # 弹签到宝箱页，玩家操作后才入账
	RANK_GIFT, # 排行礼包的展示形态，仍共用同一个领取 uid。
}

# ---- 渲染实现（按形态 preload，dispatch 时 new 出实例） ----
const _RENDER_DIRECT: Script = preload("res://products/meowdoku/app/features/award/render/award_render_direct.gd")
const _RENDER_STREAK_GIFT: Script = preload(
	"res://products/meowdoku/app/features/award/render/award_render_streak_gift.gd"
)

const _RENDER_RANK_GIFT: Script = preload("res://products/meowdoku/app/features/award/render/award_render_rank_gift.gd")

# ---- 运行时状态 ----
var _renders: Dictionary = {} # uid → AwardRender 实例，仅为当前进程表现缓存；可由持久待发队列重新附加。
var _generation: int = 0 # 清档后使旧表现/提交收尾失效，不能仅凭 uid 判断回调仍属当前玩家状态。


# ================= 生命周期 =================
## 节点就绪时做一次冷启动补发
func _ready() -> void:
	GameState.all_data_reset.connect(_clear_runtime_awards)
	# 冷启动补发：上次没走完的奖励不能丢
	_sweep_in_flight_on_cold_start()


## 清档通知先推进本节点代次，再丢弃 Render 缓存；只清运行时表现，不在此删除存档奖励。
func _clear_runtime_awards() -> void:
	_generation += 1
	_renders.clear()


## 冷启动读取已登记待发流水，逐笔尝试直接领取；失败仍留队列，清档重入则停止旧扫描。
func _sweep_in_flight_on_cold_start() -> void:
	# 中转队列写进存档，进程被杀也还在
	var generation: int = _generation
	var entries: Array = GameState.get_in_flight_awards()
	for entry in entries:
		if generation != _generation:
			break
		_persist_award(int(entry.get("uid", -1)))


## 规范化条目 → 持久登记 → 附加 Render，返回 uid；登记失败或清档重入返回 -1。
## claim_key 应代表稳定业务资格，重试复用同一键；uid 成功登记不等于所有展示形态都已实际入账。
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


## 为已登记 uid 附加/复用展示，不重新生成流水；返回是否找到可附加奖励，不作为领取成功凭证。
func attach_award(uid: int) -> bool:
	if _renders.has(uid):
		return true
	var entry := GameState.find_in_flight_award(uid)
	if entry.is_empty():
		return false
	var render: AwardRender = _make_render(int(entry.get("display_type", DisplayType.DIRECT)))
	# 先注册再注入数据：DIRECT 的 set_info 会同步调用 show_award，可能在本函数返回前已经领取并移除缓存。
	_renders[uid] = render
	render.set_info(entry)
	return true


## 触发既有 Render 的表现；是否立即请求入账由具体形态决定，本函数不登记或重新创建奖励。
func show_award(uid: int, display_params: Dictionary = {}) -> void:
	# uid 不在说明已入账，或被冷启动清扫过
	if not _renders.has(uid):
		push_warning("AwardManager.show_award: uid=%d 无 Render 实例(可能已 persist 或被跨进程清扫)" % uid)
		return
	(_renders[uid] as AwardRender).show_award(display_params)


## 给当前 Render 的结束信号挂一次性回调；这里只监听未来信号，不为已经结束/不存在的 Render 补调。
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


## 持久确认本笔翻倍资格，返回保存是否成功；真正领取时按产品规则只为可翻倍资产多发一份。
func double_award(uid: int) -> bool:
	var generation: int = _generation
	var result: Dictionary = GameState.get_economy_service().double_award(uid)
	if generation != _generation:
		return false
	if not result.get("ok", false):
		push_error("[AwardManager] 翻倍资格未保存: " + str(result))
		return false
	return true


## 委托核心一次完成资产入账和待发移除；写入失败返回 false，待发资格保留，可用原 uid 重试。
## 成功后才按实际 grants 记道具/头像框埋点并移除 Render；重复领取回执没有 grants，不会重复记到账。
func _persist_award(uid: int) -> bool:
	var generation: int = _generation
	# 先捕获代次再提交；保存成功的同步通知也可能清档，旧收尾不能删新状态的表现或继续记领取事件。
	var result: Dictionary = GameState.get_economy_service().claim_award(uid)
	if generation != _generation:
		return false
	if not result.get("ok", false):
		push_error("[AwardManager] 奖励尚未入账，保留待领取记录: " + str(result))
		return false
	for grant: Dictionary in result.get("grants", []):
		if int(grant.get("category", 0)) == AwardItem.Category.FRAME:
			Tracker.track_frame_get(int(grant.frame_id), str(grant.reason))
		else:
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
		DisplayType.RANK_GIFT:
			return _RENDER_RANK_GIFT.new() as AwardRender
		_:
			push_error("AwardManager._make_render: 未知 display_type=%d,默认 DIRECT" % display_type)
			return _RENDER_DIRECT.new() as AwardRender


## 把 AwardItem 转成字典、已有字典深拷贝；发现不支持的条目就返回空数组，交登记校验拒绝整笔奖励。
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
