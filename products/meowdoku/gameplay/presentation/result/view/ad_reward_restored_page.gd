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
var _claim_requests: Array = []
var _claim_generation: int = 0
var _claim: Callable
var _obtain_slot: Control
var _obtain_callback: Callable

func _ready() -> void:
	bind_press_release_scale($Root/Content/DialogRoot/CloseButton)


func on_show(params: Dictionary = {}) -> void:
	_cancel_offer()
	_closing = false
	_claim_requests.clear()
	for entry: Dictionary in params.get("entries", []):
		_claim_requests.append({"entry": entry.duplicate(true)})
	_claim = params.get("claim", Callable())
	_rewards = params.get("rewards", []).duplicate(true)
	_render_rewards(_rewards)
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


func on_hide() -> void:
	_cancel_offer()


func on_destroy() -> void:
	_cancel_offer()


func _cancel_offer() -> void:
	_claim_generation += 1
	_closing = true
	_anim.stop()
	_disconnect_obtain()


func _disconnect_obtain() -> void:
	if is_instance_valid(_obtain_slot) and _obtain_callback.is_valid() and _obtain_slot.obtain_finished.is_connected(_obtain_callback):
		_obtain_slot.obtain_finished.disconnect(_obtain_callback)
	_obtain_slot = null
	_obtain_callback = Callable()


func get_offer_revision() -> int:
	return _claim_generation


func _is_current_offer(generation: int) -> bool:
	return generation == _claim_generation and is_showing() and is_inside_tree() and not is_queued_for_deletion()


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
	await _collect(true)


## 1.22 的关闭和返回同样领取；外部隐藏只是取消表现，不能替玩家领取。
func _on_close_btn_pressed() -> void:
	await _collect(false)


func close() -> void:
	await _collect(false)


func _on_back_request() -> void:
	await _collect(false)


func _collect(animate: bool) -> void:
	if _closing or not is_showing():
		return
	_closing = true
	Tracker.track_btn_click(Tracker.Btn.COLLECT if animate else Tracker.Btn.CLOSE, self)
	var snapshot: Array = _rewards.duplicate(true)
	var generation: int = _claim_generation
	if not _grant_rewards():
		return
	if animate:
		var slots: Array = [_reveal_slot, _hint_slot].filter(func(slot: Control) -> bool: return slot.visible)
		if not slots.is_empty():
			var done := {"value": false}
			_obtain_slot = slots[0]
			_obtain_callback = func() -> void: done.value = true
			_obtain_slot.obtain_finished.connect(_obtain_callback, CONNECT_ONE_SHOT)
			for slot: Control in slots:
				slot.play_obtain()
			var deadline: int = Time.get_ticks_msec() + 5000
			while not done.value and _is_current_offer(generation) and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if not _is_current_offer(generation):
				return  # on_hide/on_show already disconnected this generation's listener.
			_disconnect_obtain()
			for _index: int in _OBTAIN_TO_DISMISS_DELAY_FRAMES:
				await get_tree().process_frame
				if not _is_current_offer(generation):
					return
	if not await _play_dismiss(generation):
		return
	collected.emit(snapshot)
	if _is_current_offer(generation):
		close_requested.emit()


func _grant_rewards() -> bool:
	var generation: int = _claim_generation
	var result: Dictionary = _claim.call() if _claim.is_valid() else GameState.claim_restored_rewards(_claim_requests)
	if not _is_current_offer(generation):
		return false
	if not result.get("ok", false):
		_closing = false
		Toast.popup("RECOVERY_SAVE_ERROR", self)
		return false
	return true


func _play_dismiss(generation: int) -> bool:
	if not _is_current_offer(generation):
		return false
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	while _anim.is_playing() and _is_current_offer(generation):
		await get_tree().process_frame
	return _is_current_offer(generation)
