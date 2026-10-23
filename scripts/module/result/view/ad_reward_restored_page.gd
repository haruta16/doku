## 广告奖励恢复页：展示待补发道具，领取或返回时统一执行补发流程。
class_name AdRewardRestoredPage
extends UIFrameWindow

## 玩家点领取时发出，带回领取前的奖励快照（深拷贝）
signal collected(rewards: Array)

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _tool_group: HBoxContainer = $Root/Content/DialogRoot/ToolGroup # 三个道具格所在的行
@onready var _reveal_slot: Control = $Root/Content/DialogRoot/ToolGroup/RevealBtn # 揭示道具格
@onready var _hint_slot: Control = $Root/Content/DialogRoot/ToolGroup/HintBtn # 提示道具格
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 弹窗动画

const _TOOL_SEPARATION_DOUBLE: int = 104 # 两个及以下

## 领取动画播完后再等 12 帧才收起弹窗
const _OBTAIN_TO_DISMISS_DELAY_FRAMES: int = 12

# ---- 运行时状态 ----
var _rewards: Array = [] # 待展示 / 待入账的奖励 [{kind, count}]
var _closing: bool = false # 领取或关闭只结算一次


## 给关闭按钮绑按下缩放
func _ready() -> void:
	bind_press_release_scale($Root/Content/DialogRoot/CloseButton)


## 打开：记下奖励、铺格子、播开场动画
func on_show(params: Dictionary = {}) -> void:
	# 每次打开都重置结算标记
	_closing = false
	# 奖励列表由调用方传入
	_rewards = params.get("rewards", [])
	_render_rewards(_rewards)
	visible = true
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


## 关闭钩子：只负责隐藏（真正的清理靠下次 on_show）
func on_hide() -> void:
	visible = false


## 埋点用弹窗名
func get_dlg_name() -> String:
	return Tracker.Dlg.REWARD_FAIL


func _render_rewards(rewards: Array) -> void:
	var order_lead: Control = (
		_hint_slot if ABTestManager.prop_position.is_hint_first() else _reveal_slot
	)
	if order_lead != null:
		_tool_group.move_child(order_lead, 0)
	_reveal_slot.visible = false
	_hint_slot.visible = false
	for r in rewards:
		var slot: Control = _slot_for_kind(str(r.get("kind", "")))
		if slot == null:
			continue
		slot.visible = true
		var count: int = int(r.get("count", 1))
		slot.label_text = "x%d" % count
	_tool_group.add_theme_constant_override("separation", _TOOL_SEPARATION_DOUBLE)


func _slot_for_kind(kind: String) -> Control:
	match kind:
		"hint":
			return _hint_slot
		"locate":
			return _reveal_slot
		_:
			return null


func _on_collect_btn_tag_pressed() -> void:
	if _closing:
		return
	_closing = true
	Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
	var snapshot: Array = _rewards.duplicate(true)
	_grant_rewards()

	var slots: Array = [_reveal_slot, _hint_slot].filter(func(s: Control) -> bool: return s.visible)
	for s in slots:
		s.play_obtain()
	if not slots.is_empty():
		await slots[0].obtain_finished

		for _i in _OBTAIN_TO_DISMISS_DELAY_FRAMES:
			await get_tree().process_frame
	await _play_dismiss()

	collected.emit(snapshot)


func _on_close_btn_pressed() -> void:
	if _closing:
		return
	_closing = true
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	var snapshot: Array = _rewards.duplicate(true)
	_grant_rewards()
	await _play_dismiss()
	collected.emit(snapshot)


func _on_back_request() -> void:
	_on_close_btn_pressed()


func _grant_rewards() -> void:
	var items: Array = []
	for r in _rewards:
		var kind: String = str(r.get("kind", ""))
		var count: int = int(r.get("count", 0))
		if kind == "" or count <= 0:
			continue
		items.append(AwardItem.make(kind, count))
	if not items.is_empty():
		AwardManager.dispatch(
			items, AwardManager.DisplayType.DIRECT, Tracker.PropSource.REWARD_FAIL_DLG
		)


## 播关闭动画段并等它播完，然后隐藏
func _play_dismiss() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished
	visible = false
