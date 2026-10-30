## 奖励补发弹窗：把待补发的道具演一遍，玩家点领取才真正入账
class_name AdRewardRestoredPage
extends UIFrameWindow

## 玩家点领取时发出，带回领取前的奖励快照（深拷贝）
signal collected(rewards: Array)
## 关闭时发出，由调用方决定后续流程
signal closed

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _tool_group: HBoxContainer = $Root/Content/DialogRoot/ToolGroup # 三个道具格所在的行
@onready var _reveal_slot: Control = $Root/Content/DialogRoot/ToolGroup/RevealBtn # 揭示道具格
@onready var _hint_slot: Control = $Root/Content/DialogRoot/ToolGroup/HintBtn # 提示道具格
@onready var _undo_slot: Control = $Root/Content/DialogRoot/ToolGroup/UndoBtn # 撤销道具格
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 弹窗动画

## 道具个数不同时的行内间距（像素）
const _TOOL_SEPARATION_TRIPLE: int = 38 # 三个道具
const _TOOL_SEPARATION_DOUBLE: int = 104 # 两个及以下

## 领取动画播完后再等 12 帧才收起弹窗
const _OBTAIN_TO_DISMISS_DELAY_FRAMES: int = 12

# ---- 运行时状态 ----
var _rewards: Array = [] # 待展示 / 待入账的奖励 [{kind, count}]
var _closing: bool = false # 领取或关闭只结算一次
var _claim: Callable
var _offer_revision: int = 0 # 同一缓存窗口刷新奖励也算新一批，旧动画不能完成到新批次。


## 给关闭按钮绑按下缩放
func _ready() -> void:
	bind_press_release_scale($Root/Content/DialogRoot/CloseButton)


## 打开：记下奖励、铺格子、播开场动画
func on_show(params: Dictionary = {}) -> void:
	_offer_revision += 1
	# 每次打开都重置结算标记
	_closing = false
	# 奖励列表由调用方传入
	_rewards = params.get("rewards", []).duplicate(true)
	_claim = params.get("claim", Callable())
	_render_rewards(_rewards)
	visible = true
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


## 管理器关闭使本批动画等待失效；可见性与遮罩由管理器统一收尾。
func on_hide() -> void:
	_offer_revision += 1
	_closing = true
	_anim.stop()


func get_offer_revision() -> int:
	return _offer_revision


func _is_current_offer(revision: int) -> bool:
	return revision == _offer_revision and is_showing() and is_inside_tree()


## 埋点用弹窗名
func get_dlg_name() -> String:
	return Tracker.Dlg.REWARD_FAIL


## 按 rewards 铺格子：先全部隐藏，再按 kind 点亮并写数量
func _render_rewards(rewards: Array) -> void:
	_reveal_slot.visible = false
	_hint_slot.visible = false
	_undo_slot.visible = false
	# 逐项找对应格子；未知 kind 直接忽略
	for r in rewards:
		var slot: Control = _slot_for_kind(str(r.get("kind", "")))
		if slot == null:
			continue
		slot.visible = true
		var count: int = int(r.get("count", 1))
		slot.label_text = "x%d" % count

	# 三个都显示时用更大的间距，避免挤在一起
	var shown: int = int(_reveal_slot.visible) + int(_hint_slot.visible) + int(_undo_slot.visible)
	var sep: int = _TOOL_SEPARATION_TRIPLE if shown >= 3 else _TOOL_SEPARATION_DOUBLE
	_tool_group.add_theme_constant_override("separation", sep)


## kind → 格子：hint 提示 / locate 揭示 / undo 撤销，未知返回 null
func _slot_for_kind(kind: String) -> Control:
	match kind:
		"hint":
			return _hint_slot
		"locate":
			return _reveal_slot
		"undo":
			return _undo_slot
		_:
			return null


## 点领取：道具先入账，再播格子动画，最后收起弹窗
func _on_collect_btn_tag_pressed() -> void:
	# 防重入：连点只算一次
	if _closing:
		return
	_closing = true
	var revision: int = _offer_revision
	# 埋点：领取按钮
	Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
	# 深拷贝一份给回调，避免调用方拿到内部数组
	var snapshot: Array = _rewards.duplicate(true)

	if not _claim.is_valid():
		_closing = false
		push_error("[AdRewardRestoredPage] 缺少领取业务入口")
		return
	var result: Dictionary = _claim.call()
	if not _is_current_offer(revision):
		return
	if not result.get("ok", false):
		_closing = false
		push_error("[AdRewardRestoredPage] 奖励未入账: " + str(result))
		return

	# 只让当前可见的格子播领取动画
	var slots: Array = [_reveal_slot, _hint_slot, _undo_slot].filter(
		func(s: Control) -> bool: return s.visible
	)
	var finished := {"value": false}
	var on_finished := func() -> void: finished.value = true
	var slot: Control = slots[0] if not slots.is_empty() else null
	if slot != null:
		slot.obtain_finished.connect(on_finished, CONNECT_ONE_SHOT)
	for s in slots:
		s.play_obtain()
	# 等第一个格子的领取动画播完，再多留 12 帧
	if not slots.is_empty():
		while not finished.value and _is_current_offer(revision) and is_instance_valid(slot):
			await get_tree().process_frame
		if is_instance_valid(slot) and slot.obtain_finished.is_connected(on_finished):
			slot.obtain_finished.disconnect(on_finished)
		if not _is_current_offer(revision):
			return

		# 多等几帧让特效收尾
		for _i in _OBTAIN_TO_DISMISS_DELAY_FRAMES:
			await get_tree().process_frame
			if not _is_current_offer(revision):
				return
	if not await _play_dismiss(revision):
		return

	# 动画完成后通知本批结果；监听者若同步打开下一批，不得再关闭它。
	collected.emit(snapshot)
	if _is_current_offer(revision):
		close_requested.emit()


## 点关闭按钮：领取处理中忽略关闭，避免已入账却被当作取消。
func _on_close_btn_pressed() -> void:
	close()


## 外部调用的关闭入口（防重入）
func close() -> void:
	if _closing:
		return
	_closing = true
	var revision: int = _offer_revision
	if not await _play_dismiss(revision):
		return
	closed.emit()
	if _is_current_offer(revision):
		close_requested.emit()


## 播关闭动画；外部关闭或奖励刷新时停止等待，调用者只完成原批次。
func _play_dismiss(revision: int) -> bool:
	if not _is_current_offer(revision):
		return false
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	while _anim.is_playing() and _is_current_offer(revision):
		await get_tree().process_frame
	return _is_current_offer(revision)
