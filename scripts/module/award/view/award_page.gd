# 奖励页（签到宝箱）：展示 1~2 个道具格，可「领取」或「看广告翻倍领取」
extends UIFrameWindow

# 页面场景路径与 UI 名（UIManager 注册用）
const SCENE_PATH := "res://scripts/module/award/ui/award_page.tscn"
const UI_NAME := UiName.AWARD

# ---- 预加载资源（宝箱格 / 道具格） ----
const _GIFT_CELL_SCENE: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_gift_cell.tscn"
)
# 单个道具格（复用奖励格子场景）
const _AWARD_CELL_SCENE: PackedScene = preload(
	"res://scripts/module/award/ui/other/award_cell.tscn"
)
# ---- 广告位（翻倍领取用的激励视频位） ----
const _AD_PLACEMENT: String = Tracker.Placement.REWARD # 广告 placement 名
const _AD_POS: String = Tracker.AdPos.STREAK_X2_REWARD # 广告位标识

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _award_panel: Control = $AwardPanel # 奖励面板
@onready var _gift_open_content: Control = $GiftCenter/GiftOpenContent # 宝箱格容器
@onready var _double_collect_btn: Control = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn # 看广告翻倍按钮
@onready var _collect_btn: Control = $AwardPanel/DoubleBtnGroup/CollectBtn # 普通领取按钮

# 两个道具格：按 items 数量显示
@onready var _cell_slots: Array[Control] = [
	$AwardPanel/AwardContent/CellSlot1,
	$AwardPanel/AwardContent/CellSlot2,
]

# ---- 运行时状态 ----
var _on_persisted: Callable = Callable() # 关闭后要回调的落库函数（AwardRenderStreakGift 传入）
var _streak_uid: int = -1 # 本笔奖励 uid，-1 表示没有

@onready var _double_badge: GameAdBadge = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn/Badge # 翻倍按钮上的广告角标
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗动画

var _ad_settled: bool = false # 广告回调只结算一次（成功 / 失败都会置位）


# ================= 生命周期 =================
# 创建钩子：本页不需要额外初始化
func on_create() -> void:
	pass


# 通用 on_show 不用：数据由 setup_streak_gift 直接注入
func on_show(params: Dictionary = {}) -> void:
	pass


# 关闭：先回调落库（保证道具到账），再清 uid 与格子
func on_hide() -> void:
	if _on_persisted.is_valid():
		var cb: Callable = _on_persisted
		_on_persisted = Callable()
		cb.call()
	_streak_uid = -1
	_clear_gift_cells()


# 销毁钩子：本页不需要额外清理
func on_destroy() -> void:
	pass


# ================= 数据与渲染 =================
# 由 AwardRenderStreakGift 调用：铺宝箱格与道具格，并接上关闭回调
func setup_streak_gift(items: Array, uid: int, on_persisted: Callable) -> void:
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

	# 广告可用才显示翻倍按钮
	var ad_ready: bool = UniKitManager.is_reward_valid(_AD_PLACEMENT, _AD_POS)
	_double_collect_btn.visible = ad_ready
	if ad_ready:
		_double_badge.show_ad()
	_collect_btn.visible = true


# 清空宝箱格（下次展示重新创建）
func _clear_gift_cells() -> void:
	if _gift_open_content == null:
		return
	for c in _gift_open_content.get_children():
		c.queue_free()


# 按 items 依次点亮道具格；没有对应项的格子隐藏
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


# 只清本页创建的道具格（认 set_award 方法）
func _clear_award_cells(slot: Control) -> void:
	for c in slot.get_children():
		# 只清带 set_award 的道具格
		if c.has_method("set_award"):
			c.queue_free()


# ================= 按钮与广告回调 =================
# 普通领取：关弹窗即可，入账在 on_hide 里完成
func _on_collect_pressed() -> void:
	UIManager.hide_ui(UiName.AWARD)


# 翻倍领取：先确认广告就绪，再看激励视频
func _on_collect_double_pressed() -> void:
	# 生成这次广告请求的 show_id
	var show_id := UniKitManager.gen_show_id()
	# 广告没就绪就静默返回（按钮本不该显示）
	if not UniKitManager.is_reward_ready(_AD_PLACEMENT, _AD_POS, show_id):
		return
	# 每次请求都先重置结算标记
	_ad_settled = false

	# 三个信号都只挂一次
	if not UniKitManager.ad_rewarded.is_connected(_on_ad_rewarded):
		connect_managed_once(UniKitManager.ad_rewarded, _on_ad_rewarded)
	if not UniKitManager.ad_closed.is_connected(_on_reward_ad_failed):
		connect_managed_once(UniKitManager.ad_closed, _on_reward_ad_failed)
	if not UniKitManager.ad_error_occurred.is_connected(_on_reward_ad_error):
		connect_managed_once(UniKitManager.ad_error_occurred, _on_reward_ad_error)
	# 拉起激励视频
	UniKitManager.show_reward(_AD_PLACEMENT, _AD_POS, show_id)


# 广告发奖 → 标记翻倍并关弹窗（关闭时才真正入账）
func _on_ad_rewarded(placement_id: String) -> void:
	# 不是本广告位或已结算就忽略
	if placement_id != _AD_PLACEMENT or _ad_settled:
		return
	_ad_settled = true
	# 告诉 AwardManager：本笔奖励要双份
	if _streak_uid >= 0:
		AwardManager.double_award(_streak_uid)
	UIManager.hide_ui(UiName.AWARD)


# 广告被关闭且未发奖 → 不算翻倍，照样关弹窗
func _on_reward_ad_failed(placement_id: String) -> void:
	if placement_id != _AD_PLACEMENT or _ad_settled:
		return
	_ad_settled = true
	UIManager.hide_ui(UiName.AWARD)


# 广告出错：与未发奖同路处理
func _on_reward_ad_error(placement_id: String, _msg: String) -> void:
	_on_reward_ad_failed(placement_id)
