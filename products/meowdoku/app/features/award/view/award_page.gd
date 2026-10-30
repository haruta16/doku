## 奖励页（签到宝箱）：展示 1~2 个道具格，可「领取」或「看广告翻倍领取」
extends UIFrameWindow

## 页面场景路径与 UI 名（UIManager 注册用）
const SCENE_PATH := "res://products/meowdoku/app/features/award/ui/award_page.tscn"
const UI_NAME := UiName.AWARD

# ---- 预加载资源（宝箱格 / 道具格） ----
const _GIFT_CELL_SCENE: PackedScene = preload(
	"res://products/meowdoku/app/features/daily_streak/ui/streak_gift_cell.tscn"
)
## 单个道具格（复用奖励格子场景）
const _AWARD_CELL_SCENE: PackedScene = preload(
	"res://products/meowdoku/app/features/award/ui/other/award_cell.tscn"
)
# ---- 广告位（翻倍领取用的激励视频位） ----
const _AD_PLACEMENT: String = Tracker.Placement.REWARD # 广告 placement 名
const _AD_POS: String = Tracker.AdPos.STREAK_X2_REWARD # 广告位标识

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _award_panel: Control = $AwardPanel # 奖励面板
@onready var _gift_open_content: Control = $GiftCenter/GiftOpenContent # 宝箱格容器
@onready var _double_collect_btn: Control = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn # 看广告翻倍按钮
@onready var _collect_btn: Control = $AwardPanel/DoubleBtnGroup/CollectBtn # 普通领取按钮

## 两个道具格：按 items 数量显示
@onready var _cell_slots: Array[Control] = [
	$AwardPanel/AwardContent/CellSlot1,
	$AwardPanel/AwardContent/CellSlot2,
]

# ---- 运行时状态 ----
var _on_persisted: Callable = Callable() # 入账回调，返回成功后才关闭领取界面。
var _streak_uid: int = -1 # 本笔奖励 uid，-1 表示没有

@onready var _double_badge: GameAdBadge = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn/Badge # 翻倍按钮上的广告角标
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗动画

var _ad_settled: bool = false # 广告回调只结算一次（成功 / 失败都会置位）
var _reward_revision: int = 0 # 每次奖励注入都替换归属，包括同一uid的页面刷新
var _persisting: bool = false # 同一次领取的提交/回调期间阻止重复进入
var _double_pending: bool = false # 已收到翻倍回调但尚未确认保存，重试先保存翻倍。


# ================= 生命周期 =================
## 创建钩子：本页不需要额外初始化
func on_create() -> void:
	pass


## 在显示通知发布之前装配本笔奖励；缓存页重开会取消旧广告消费者。
func on_show(params: Dictionary = {}) -> void:
	# 缓存页可被直接复用，旧广告消费者不能借用新奖励。
	UniKitManager.disconnect_reward_callbacks(self)
	if params.has("uid"):
		setup_streak_gift(params.get("items", []), int(params.uid), params.get("on_persisted", Callable()))


## 外部强制关闭时仍尝试入账；失败保留核心 pending，冷启动可继续补发。
func on_hide() -> void:
	var revision: int = _reward_revision
	var uid: int = _streak_uid
	UniKitManager.disconnect_reward_callbacks(self)
	_try_persist_reward()
	if not _is_current_reward(revision, uid):
		return
	_streak_uid = -1
	_clear_gift_cells()


## 销毁可以跳过 on_hide；同步撤销消费者，避免 queue_free 前同帧迟到回奖。
func on_destroy() -> void:
	UniKitManager.disconnect_reward_callbacks(self)


# ================= 数据与渲染 =================
## 由 AwardRenderStreakGift 调用：铺宝箱格与道具格，并接上关闭回调
func setup_streak_gift(items: Array, uid: int, on_persisted: Callable) -> void:
	_reward_revision += 1
	# 先清掉上次的宝箱格
	_clear_gift_cells()

	var cell := create_child(_GIFT_CELL_SCENE)
	if cell:
		cell.reparent(_gift_open_content, false)

	# 场景里有 Appear 动画才播
	if _anim and _anim.has_animation(&"Appear"):
		_anim.play(&"Appear")

	# 按 items 填道具格
	_render_award_cells(items)
	_streak_uid = uid
	_on_persisted = on_persisted
	_persisting = false
	_ad_settled = false
	_double_pending = false

	# 广告可用才显示翻倍按钮
	var ad_ready: bool = UniKitManager.is_reward_valid(_AD_PLACEMENT, _AD_POS)
	_double_collect_btn.visible = ad_ready
	if ad_ready:
		_double_badge.show_ad()
	_collect_btn.visible = true


## 清空宝箱格（下次展示重新创建）
func _clear_gift_cells() -> void:
	if _gift_open_content == null:
		return
	for c in _gift_open_content.get_children():
		if c is UIChildWindow:
			destroy_child(c)
		else:
			c.queue_free()


## 按 items 依次点亮道具格；没有对应项的格子隐藏
func _render_award_cells(items: Array) -> void:
	# 逐格填：i 超出 items.size() 就隐藏
	for i in range(_cell_slots.size()):
		var slot: Control = _cell_slots[i]
		if slot == null:
			continue
		_clear_award_cells(slot)
		# 这一格有没有道具
		var has_item: bool = i < items.size()
		slot.visible = has_item
		if not has_item:
			continue
		# items 元素是 AwardItem
		var it = items[i]

		var cell := create_child(_AWARD_CELL_SCENE, {"kind": str(it.kind), "count": int(it.count)})
		if cell:
			cell.reparent(slot, false)


## 只清本页创建的道具格（认 set_award 方法）
func _clear_award_cells(slot: Control) -> void:
	for c in slot.get_children():
		# 只清带 set_award 的道具格
		if c.has_method("set_award"):
			if c is UIChildWindow:
				destroy_child(c)
			else:
				c.queue_free()


# ================= 按钮与广告回调 =================
## 普通领取：先确认入账，保存失败留在本页重试。
func _on_collect_pressed() -> void:
	var revision: int = _reward_revision
	var uid: int = _streak_uid
	if _try_persist_reward() and _is_current_reward(revision, uid):
		UIManager.hide_ui(UiName.AWARD)


func _is_current_reward(revision: int, uid: int) -> bool:
	return revision == _reward_revision and uid == _streak_uid and is_inside_tree() and not is_queued_for_deletion()


func _try_persist_reward() -> bool:
	if _persisting:
		return false
	var revision: int = _reward_revision
	var uid: int = _streak_uid
	_persisting = true
	if _double_pending:
		var doubled: bool = AwardManager.double_award(uid)
		if not _is_current_reward(revision, uid):
			return false
		if not doubled:
			_persisting = false
			Toast.popup("RECOVERY_SAVE_ERROR", self)
			return false
		_double_pending = false
	if not _on_persisted.is_valid():
		_persisting = false
		return true
	var callback := _on_persisted
	# 成功信号可能同步关闭或复用页面；旧回调不能覆盖新展示的回调。
	_on_persisted = Callable()
	var persisted: bool = bool(callback.call())
	if not _is_current_reward(revision, uid):
		return false
	_persisting = false
	if persisted:
		return true
	_on_persisted = callback
	Toast.popup("RECOVERY_SAVE_ERROR", self)
	return false


## 翻倍领取：先确认广告就绪，再看激励视频
func _on_collect_double_pressed() -> void:
	# 生成这次广告请求的 show_id
	var show_id := UniKitManager.gen_show_id()
	# 广告没就绪就静默返回（按钮本不该显示）
	if not UniKitManager.is_reward_ready(_AD_PLACEMENT, _AD_POS, show_id):
		return
	# 每次请求都先重置结算标记
	_ad_settled = false

	# 领奖按逐次身份绑定，其他展示生命周期仍使用托管信号。
	UniKitManager.disconnect_reward_callbacks(self)
	var revision: int = _reward_revision
	var uid: int = _streak_uid
	UniKitManager.connect_reward_once(show_id, func(placement: String) -> void:
		if _is_current_reward(revision, uid) and is_showing():
			_on_ad_rewarded(placement)
	)
	connect_managed_once(UniKitManager.ad_closed, func(placement: String) -> void:
		if _is_current_reward(revision, uid) and is_showing():
			_on_reward_ad_failed(placement)
	)
	connect_managed_once(UniKitManager.ad_error_occurred, func(placement: String, message: String) -> void:
		if _is_current_reward(revision, uid) and is_showing():
			_on_reward_ad_error(placement, message)
	)
	# 拉起激励视频
	UniKitManager.show_reward(_AD_PLACEMENT, _AD_POS, show_id)


## 广告发奖 → 保存翻倍并确认入账，成功后才关闭弹窗。
func _on_ad_rewarded(placement_id: String) -> void:
	# 不是本广告位或已结算就忽略
	if placement_id != _AD_PLACEMENT or _ad_settled:
		return
	_ad_settled = true
	# 保存失败也保留已看到的翻倍意图，不让后续 close 回调降成普通领取。
	_double_pending = _streak_uid >= 0
	_on_collect_pressed()


## 广告被关闭且未发奖 → 尝试普通领取，保存失败仍留在本页。
func _on_reward_ad_failed(placement_id: String) -> void:
	if placement_id != _AD_PLACEMENT or _ad_settled:
		return
	_ad_settled = true
	_on_collect_pressed()


## 广告出错：与未发奖同路处理
func _on_reward_ad_error(placement_id: String, _msg: String) -> void:
	_on_reward_ad_failed(placement_id)
