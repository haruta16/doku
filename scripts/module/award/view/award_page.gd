## 奖励演出页：展示打卡和排行榜礼包，协调激励翻倍、头像框升级与飞行动画。
extends UIFrameWindow

## 页面场景路径与 UI 名（UIManager 注册用）
const SCENE_PATH := "res://scripts/module/award/ui/award_page.tscn"

# ---- 预加载资源（宝箱格 / 道具格） ----
const _GIFT_CELL_SCENE: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_gift_cell.tscn"
)
## 单个道具格（复用奖励格子场景）
const _AWARD_CELL_SCENE: PackedScene = preload(
	"res://scripts/module/award/ui/other/award_cell.tscn"
)

const _FRAME_AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _FRAME_ADD_SCALE: Vector2 = Vector2(2.1621623, 2.1621623)

const _RANK_GIFT_CELL: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_gift_cell.tscn"
)

const _FRAME_TRAIL_SCENE: PackedScene = preload("res://assets/prefab/effect_score_trail.tscn")
const _FRAME_BURST_SCENE: PackedScene = preload("res://assets/prefab/effect_score_burst.tscn")

const _FRAME_TRAIL_SHOW_DELAY: float = 0.2667
const _FRAME_FLY_START_DELAY: float = 0.3
const _FRAME_FLY_DURATION: float = 0.45

const _FRAME_TRAIL_HIDE_DELAY: float = 0.1

const _FRAME_FLY_BEZIER_X: Array = [0.389, -0.006, 0.933, 1.0]
const _FRAME_FLY_BEZIER_Y: Array = [0.544, -0.46, 1.0, 1.001]

const _FRAME_HOLD_NO_ROLL: float = 0.6334
const _FRAME_HOLD_WITH_ROLL: float = 0.8

const _TIER_UP_ANIM: StringName = &"Up"
const _TIER_FRAME_SWAP_SEC: float = 0.3

const _TIER_WINS_COLOR: String = "#02BE52"
const _TIER_WINS_FONT_SIZE: int = 80

const _TIER_GROUP_FADE_IN_SEC: float = 0.25

var _tier_fade_tw: Tween = null
const _AD_POS: String = Tracker.AdPos.STREAK_X2_REWARD # 广告位标识

const _AD_REWARD_GRACE_SEC: float = 1.0

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _award_panel: Control = $AwardPanel # 奖励面板
@onready var _award_content: Control = $AwardPanel/AwardContent

@onready var _gift_cell_layer: Control = $GiftCellLayer
@onready var _double_collect_btn: Control = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn # 看广告翻倍按钮
@onready var _collect_btn: Control = $AwardPanel/DoubleBtnGroup/CollectBtn # 普通领取按钮

var _collect_btn_orig_top: float = 0.0
var _collect_btn_orig_bottom: float = 0.0

@onready var _cell_slots: Array[Control] = [
	$AwardPanel/AwardContent/CellSlot1,
	$AwardPanel/AwardContent/CellSlot2,
	$AwardPanel/AwardContent/CellSlot3,
]

const _POS_CENTER: Vector2 = Vector2(442, 0)
const _POS_BOTTOM_LEFT: Vector2 = Vector2(244, 0)
const _POS_BOTTOM_RIGHT: Vector2 = Vector2(640, 0)

const _POS_ROW_LEFT: Vector2 = Vector2(146, 0)
const _POS_ROW_CENTER: Vector2 = Vector2(442, 0)
const _POS_ROW_RIGHT: Vector2 = Vector2(738, 0)

# ---- 运行时状态 ----
var _on_persisted: Callable = Callable() # 关闭后要回调的落库函数（AwardRenderStreakGift 传入）
var _streak_uid: int = -1 # 本笔奖励 uid，-1 表示没有

@onready var _double_badge: GameAdBadge = $AwardPanel/DoubleBtnGroup/DoubleCollectBtn/Badge # 翻倍按钮上的广告角标
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗动画

@onready var _frame_add_effect: Control = $FrameAddEffect

@onready var _frame_anim: AnimationPlayer = $FrameAddEffect/AnimationPlayer

var _frame_add_cell = null

var _ad_settled: bool = false # 广告回调只结算一次（成功 / 失败都会置位）

var _ad_grace_timer: Timer = null

var _ad_grace_id: int = 0

var _ad_closed_ms: int = 0

var _frame_award_id: int = 0
var _frame_award_count: int = 0

@onready var _tier_group: Control = $FrameAddEffect/TierGroup

@onready var _tier_title: RichTextLabel = $FrameAddEffect/TierGroup/TierTitle
@onready var _tier_equip_btn: Control = $FrameAddEffect/TierGroup/TierBtnGroup/EquipBtn
@onready var _tier_collect_btn: Control = $FrameAddEffect/TierGroup/TierBtnGroup/TierCollectBtn

signal _tier_choice(equipped: bool)

var _tier_choice_pending: bool = false

var _tier_gate_id: int = 0

var _pending_equip_form: int = -1

var _pending_presented_form: int = -1

var _frame_only: bool = false

var _closing: bool = false

var _buttons_locked: bool = false
var _appear_gate_id: int = 0

var _show_seq_id: int = 0

var _double_ad_show_id: String = ""

var _double_ad_check_pending: bool = false

var _is_rank_mode: bool = false
var _rank_phase: int = 0
var _rank_gift_cell = null
var _streak_gift_cell = null


func on_create() -> void:
	var cell = _FRAME_AVATAR_CELL.instantiate()
	cell.anchor_left = 0.5
	cell.anchor_top = 0.5
	cell.anchor_right = 0.5
	cell.anchor_bottom = 0.5
	cell.offset_left = -92.5
	cell.offset_top = -92.5
	cell.offset_right = 92.5
	cell.offset_bottom = 92.5
	cell.pivot_offset = Vector2(92.5, 92.5)
	cell.scale = _FRAME_ADD_SCALE
	_frame_add_effect.add_child(cell)
	cell.set_base_visible(false)
	_frame_add_cell = cell

	_collect_btn_orig_top = _collect_btn.offset_top
	_collect_btn_orig_bottom = _collect_btn.offset_bottom

	_hide_btn_shadow(_collect_btn)
	_hide_btn_shadow(_double_collect_btn)

	_warm_rank_gift_cell()
	_gpu_warm_rank_gift_cell()
	_tier_equip_btn.tag_pressed.connect(_on_tier_equip_pressed)
	_tier_collect_btn.tag_pressed.connect(_on_tier_collect_pressed)


func _warm_rank_gift_cell() -> void:
	var w: Control = _RANK_GIFT_CELL.instantiate()
	add_child(w)
	remove_child(w)
	w.free()


func _gpu_warm_rank_gift_cell() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var host: Node = tree.current_scene
	if host == null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(270, 600)
	vp.transparent_bg = true

	if "disable_3d" in vp:
		vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var cell := _RANK_GIFT_CELL.instantiate() as Control
	if cell == null:
		vp.queue_free()
		return
	cell.position = Vector2.ZERO
	cell.size = Vector2(1080, 2400)
	cell.scale = Vector2(0.25, 0.25)
	vp.add_child(cell)

	for ci in cell.find_children("*", "CanvasItem", true, false):
		(ci as CanvasItem).visible = true
	for p in cell.find_children("*", "GPUParticles2D", true, false):
		(p as GPUParticles2D).emitting = true
	for p2 in cell.find_children("*", "CPUParticles2D", true, false):
		(p2 as CPUParticles2D).emitting = true
	for fw in cell.find_children("*", "FireworkLineTrail", true, false):
		(fw as FireworkLineTrail).emitting = true

	for sp in cell.find_children("*", "SpineSprite", true, false):
		var sk = (sp as SpineSprite).get_skeleton()
		if sk != null:
			sk.set_skin_by_name("RankBox1")
			sk.set_slots_to_setup_pose()
			(sp as SpineSprite).update_skeleton(0.0)

	for _i in 5:
		await tree.process_frame
	if is_instance_valid(vp):
		vp.queue_free()


func _apply_single_btn_layout(single: bool) -> void:
	if single:
		_collect_btn.offset_top = _double_collect_btn.offset_top
		_collect_btn.offset_bottom = _double_collect_btn.offset_bottom
	else:
		_collect_btn.offset_top = _collect_btn_orig_top
		_collect_btn.offset_bottom = _collect_btn_orig_bottom


func _hide_btn_shadow(btn: Control) -> void:
	if btn == null:
		return
	var sh: CanvasItem = btn.get_node_or_null("Root/Shadow") as CanvasItem
	if sh != null:
		sh.visible = false


func show_frame_add(frame_id: int):
	if _frame_add_cell != null:
		_frame_add_cell.set_avatar(ProfileService.get_avatar_id())
		_frame_add_cell.set_base_visible(true)

		_frame_add_cell.set_frame(frame_id, _current_frame_form(frame_id))
	if _frame_add_effect != null:
		_frame_add_effect.visible = true
	return _frame_add_cell


func hide_frame_add() -> void:
	if _frame_add_effect != null:
		_frame_add_effect.visible = false


func on_show(_params: Dictionary = {}) -> void:
	_reset_double_ad_opportunity()


func on_hide() -> void:
	_reset_double_ad_opportunity()

	_cancel_ad_grace()

	_ad_settled = false

	if _on_persisted.is_valid():
		var persist_callback: Callable = _on_persisted
		_on_persisted = Callable()
		persist_callback.call()

	if ProfileCatalog.is_valid_form(_pending_equip_form):
		ProfileService.set_frame_id(ProfileCatalog.FIRST_PLACE_FRAME_ID)
		ProfileService.set_frame_form(_pending_equip_form)
	_pending_equip_form = -1
	_streak_uid = -1
	if ProfileCatalog.is_valid_form(_pending_presented_form):
		ProfileService.mark_frame_tier_presented(_pending_presented_form)
	_pending_presented_form = -1
	_frame_award_id = 0
	_frame_award_count = 0
	_frame_only = false
	_closing = false

	_buttons_locked = false
	_appear_gate_id += 1

	_is_rank_mode = false
	_rank_phase = 0

	_tier_choice_pending = false

	_tier_gate_id += 1
	_tier_group.visible = false
	hide_frame_add()
	_clear_gift_cells()


## 销毁钩子：本页不需要额外清理
func on_destroy() -> void:
	pass


func on_escape() -> bool:
	return _tier_choice_pending


func get_dlg_name() -> String:
	if not _is_rank_mode:
		return ""
	return Tracker.Dlg.CHALLENGE_REWARD_GET if _rank_phase == 2 else Tracker.Dlg.CHALLENGE_REWARD


func setup_streak_gift(items: Array, uid: int, on_persisted: Callable) -> void:
	_reset_double_ad_opportunity()

	_buttons_locked = true
	_clear_gift_cells()

	_destroy_rank_gift_cell()
	_award_panel.visible = true
	_award_content.visible = true

	var cell: UIChildWindow = create_child(_GIFT_CELL_SCENE)
	if cell:
		cell.reparent(_gift_cell_layer, false)

		cell.name = &"StreakGiftCell"
		cell.offset_left = 435.0
		cell.offset_top = 493.0
		cell.offset_right = 1515.0
		cell.offset_bottom = 2893.0
		cell.pivot_offset = Vector2(
			_gift_cell_layer.size.x * 0.5 - 20.0, _gift_cell_layer.size.y * 0.5
		)
		cell.scale = Vector2(0.18, 0.18)
		cell.visible = true
	_streak_gift_cell = cell

	_center_gift_cell_layer()

	_is_rank_mode = false
	_rank_phase = 0
	_play_content_appear()

	_render_award_cells(items)

	_scan_frame_award(items)
	_closing = false
	hide_frame_add()
	_streak_uid = uid
	_on_persisted = on_persisted

	if _frame_only:
		_double_collect_btn.visible = false
		_collect_btn.visible = false
		_close_with_frame_effect()
		return
	_prepare_double_collect()


func _prepare_double_collect() -> void:
	_double_collect_btn.visible = false
	_collect_btn.visible = true
	_apply_single_btn_layout(true)
	_double_ad_show_id = UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, _ad_pos())
	_refresh_double_collect_stock_async()


func _reset_double_ad_opportunity() -> void:
	_show_seq_id += 1
	_double_ad_show_id = ""
	_double_ad_check_pending = false


func _refresh_double_collect_stock_async() -> void:
	var seq: int = _show_seq_id
	var position: String = _ad_pos()
	var show_id: String = _double_ad_show_id
	var ad_ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, position, show_id)
	if seq != _show_seq_id or not is_showing() or _closing:
		return
	_double_collect_btn.visible = ad_ready
	if ad_ready:
		_double_badge.show_ad()
	_apply_single_btn_layout(not ad_ready)


func _play_content_appear(skip_gift: bool = false) -> void:
	if _anim == null or not _anim.has_animation(&"Appear"):
		_buttons_locked = false
		return

	_award_content.scale = Vector2(0.5, 0.5)
	_award_content.modulate = Color(1, 1, 1, 0)
	_anim.play(&"Appear")
	if skip_gift:
		_anim.seek(1.6, true)
	_gate_buttons_during_appear()


func _gate_buttons_during_appear() -> void:
	_buttons_locked = true
	_appear_gate_id += 1
	var my_id: int = _appear_gate_id
	await _anim.animation_finished
	if my_id == _appear_gate_id:
		_buttons_locked = false


func setup_rank_gift(
	items: Array, uid: int, on_persisted: Callable, params: Dictionary = {}
) -> void:
	_reset_double_ad_opportunity()
	_clear_gift_cells()
	_is_rank_mode = true
	_rank_phase = 1

	_destroy_rank_gift_cell()
	_rank_gift_cell = create_child(_RANK_GIFT_CELL)
	if _rank_gift_cell != null:
		_rank_gift_cell.reparent(_gift_cell_layer, false)
		if _rank_gift_cell.has_method("setup"):
			_rank_gift_cell.setup(
				params.get("top3_infos", []),
				int(params.get("place", 1)),
				int(params.get("win_count", 0))
			)

		if _rank_gift_cell.has_signal("collect_pressed"):
			connect_managed(_rank_gift_cell.collect_pressed, _enter_rank_phase2)
	_center_gift_cell_layer()

	_award_panel.visible = false
	_award_content.visible = false

	_render_award_cells(items)

	_scan_frame_award(items)
	_closing = false
	hide_frame_add()
	_streak_uid = uid
	_on_persisted = on_persisted

	_double_collect_btn.visible = false
	_collect_btn.visible = false


func _enter_rank_phase2() -> void:
	if _rank_phase != 1:
		return

	_buttons_locked = true

	Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
	_rank_phase = 2

	Tracker.notify_dlg_closed(Tracker.Dlg.CHALLENGE_REWARD)
	Tracker.track_dlg_show(Tracker.Dlg.CHALLENGE_REWARD_GET)

	if _frame_only:
		_double_collect_btn.visible = false
		_collect_btn.visible = false
		_close_with_frame_effect()
		return

	_award_panel.visible = true
	_award_content.visible = true
	_play_content_appear(true)
	_prepare_double_collect()


func _hide_award_backdrop() -> void:
	_award_panel.visible = false
	if _streak_gift_cell != null and is_instance_valid(_streak_gift_cell):
		_streak_gift_cell.visible = false
	if _rank_gift_cell != null and is_instance_valid(_rank_gift_cell):
		_rank_gift_cell.visible = false


func _destroy_rank_gift_cell() -> void:
	if _rank_gift_cell != null and is_instance_valid(_rank_gift_cell):
		destroy_child(_rank_gift_cell)
	_rank_gift_cell = null


func _clear_gift_cells() -> void:
	if _streak_gift_cell != null and is_instance_valid(_streak_gift_cell):
		destroy_child(_streak_gift_cell)
	_streak_gift_cell = null


func _center_gift_cell_layer() -> void:
	if _gift_cell_layer == null:
		return
	var dy: float = (get_viewport_rect().size.y - 2400.0) * 0.5
	_gift_cell_layer.offset_top = dy
	_gift_cell_layer.offset_bottom = dy


func _scan_frame_award(items: Array) -> void:
	_frame_award_id = 0
	_frame_award_count = 0
	var has_tool: bool = false
	for it in items:
		if int(it.category) == AwardItem.Category.FRAME:
			if _frame_award_id == 0 and int(it.frame_id) > 0:
				_frame_award_id = int(it.frame_id)
				_frame_award_count = int(it.count)
		else:
			has_tool = true
	_frame_only = _frame_award_id > 0 and not has_tool


func _render_award_cells(items: Array) -> void:
	var display_items: Array = []
	for it in items:
		if int(it.category) != AwardItem.Category.FRAME:
			display_items.append(it)

	AwardItem.apply_prop_position(display_items, ABTestManager.prop_position.is_hint_first())
	var n: int = mini(display_items.size(), _cell_slots.size())
	var layout: Array = _layout_positions(n)
	for i in range(_cell_slots.size()):
		var slot: Control = _cell_slots[i]
		if slot == null:
			continue
		_clear_award_cells(slot)
		var has_item: bool = i < n
		slot.visible = has_item
		if not has_item:
			continue
		slot.position = layout[i]
		var it = display_items[i]

		var cell := create_child(
			_AWARD_CELL_SCENE,
			{
				"category": int(it.category),
				"kind": str(it.kind),
				"frame_id": int(it.frame_id),
				"count": int(it.count),
			}
		)
		if cell:
			cell.reparent(slot, false)


func _layout_positions(n: int) -> Array:
	if n <= 1:
		return [_POS_CENTER]
	if n == 2:
		return [_POS_BOTTOM_LEFT, _POS_BOTTOM_RIGHT]

	return [_POS_ROW_CENTER, _POS_ROW_LEFT, _POS_ROW_RIGHT]


func _clear_award_cells(slot: Control) -> void:
	for c in slot.get_children():
		if c.has_method("set_award"):
			if c is UIChildWindow:
				destroy_child(c)
			else:
				c.queue_free()


## 入场锁定或广告查询中忽略点击，其余情况进入统一头像框表现和关闭流程。
func _on_collect_pressed() -> void:
	if _buttons_locked or _double_ad_check_pending:
		return

	if _is_rank_mode:
		Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
	_close_with_frame_effect()


func _ad_pos() -> String:
	return Tracker.AdPos.RANK_REWARD if _is_rank_mode else _AD_POS


func _on_collect_double_pressed() -> void:
	if (
		_buttons_locked
		or _double_ad_check_pending
		or _closing
		or not is_showing()
		or not _double_collect_btn.visible
	):
		return
	if _is_rank_mode and _rank_phase == 1:
		return

	if _is_rank_mode:
		Tracker.track_btn_click(Tracker.Btn.COLLECT_DOUBLE, self)
	var seq: int = _show_seq_id
	var position: String = _ad_pos()
	var show_id: String = _double_ad_show_id
	_double_ad_check_pending = true
	var ad_ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, position, show_id)
	if seq != _show_seq_id or not is_showing() or _closing:
		return
	_double_ad_check_pending = false
	if not ad_ready:
		Toast.popup("AD_TOAST_NOT_READY", self)
		return
	_ad_settled = false
	_cancel_ad_grace()

	if not UniKitManager.ad_rewarded.is_connected(_on_ad_rewarded):
		connect_managed_once(UniKitManager.ad_rewarded, _on_ad_rewarded)
	if not UniKitManager.ad_closed.is_connected(_on_reward_ad_closed):
		connect_managed_once(UniKitManager.ad_closed, _on_reward_ad_closed)
	if not UniKitManager.ad_error_occurred.is_connected(_on_reward_ad_error):
		connect_managed_once(UniKitManager.ad_error_occurred, _on_reward_ad_error)

	_buttons_locked = true
	UniKitManager.show_reward(AdPlacement.REWARD, position, show_id)


## 同一笔广告只结算一次，标记奖励翻倍并关闭；迟于关闭的奖励会取消宽限计时。
func _on_ad_rewarded(placement_id: String) -> void:
	if placement_id != AdPlacement.REWARD or _ad_settled:
		return
	_ad_settled = true

	if _ad_grace_timer != null:
		_report_reward_after_close()
	_cancel_ad_grace()
	if _streak_uid >= 0:
		AwardManager.double_award(_streak_uid)
	_close_with_frame_effect()


## 关闭事件暂不决定是否翻倍，启动一秒宽限以等待可能迟到的奖励回执。
func _on_reward_ad_closed(placement_id: String) -> void:
	if placement_id != AdPlacement.REWARD or _ad_settled:
		return
	if _ad_grace_timer != null:
		return
	_ad_closed_ms = Time.get_ticks_msec()
	_ad_grace_id += 1
	var my_id: int = _ad_grace_id
	_ad_grace_timer = create_countdown(
		_AD_REWARD_GRACE_SEC, func() -> void: _on_ad_grace_timeout(my_id)
	)


## 用递增标识排除旧计时回调，宽限结束后按普通奖励收尾。
func _on_ad_grace_timeout(grace_id: int) -> void:
	if grace_id != _ad_grace_id or _ad_settled:
		return
	_ad_grace_timer = null
	_ad_settled = true
	_close_with_frame_effect()


func _on_reward_ad_error(placement_id: String, _msg: String) -> void:
	if placement_id != AdPlacement.REWARD or _ad_settled:
		return
	_cancel_ad_grace()
	_ad_settled = true
	_close_with_frame_effect()


func _cancel_ad_grace() -> void:
	_ad_grace_id += 1
	if _ad_grace_timer != null:
		remove_timer(_ad_grace_timer)
		_ad_grace_timer = null


func _report_reward_after_close() -> void:
	var late_ms: int = Time.get_ticks_msec() - _ad_closed_ms
	print(
		(
			"[AwardPage] x2 rescued by grace: reward %dms after close, mode=%s, uid=%d"
			% [late_ms, "rank" if _is_rank_mode else "streak", _streak_uid]
		)
	)
	push_error(
		(
			"AwardPage: reward ad closed before rewarded, x2 double reward rescued, position=%s"
			% _ad_pos()
		)
	)


func _close_with_frame_effect() -> void:
	if _closing:
		return
	_closing = true
	if _frame_award_id > 0:
		await _play_frame_add()

	if is_showing():
		UIManager.hide_ui(get_ui_name())


func _play_frame_add() -> void:
	_pending_equip_form = -1
	_pending_presented_form = -1
	var cell: Control = show_frame_add(_frame_award_id)
	if cell == null:
		return

	_hide_award_backdrop()

	cell.scale = _FRAME_ADD_SCALE
	cell.modulate = Color(1, 1, 1, 1)
	cell.rotation = 0.0

	var before: int = maxi(0, ProfileService.get_frame_count(_frame_award_id))
	var after: int = before + _frame_award_count

	var tier_unlocked: int = -1
	var tier_choice: bool = false
	var from_form: int = -1
	var title_key: String = "RANK_TIER_UNLOCK"
	if (
		ABTestManager.rank_1st_frame.is_enabled()
		and _frame_award_id == ProfileCatalog.FIRST_PLACE_FRAME_ID
	):
		var before_form: int = ProfileCatalog.form_for_wins(before)
		var after_form: int = ProfileCatalog.form_for_wins(after)
		var pending_before: int = ProfileService.get_pending_frame_tier_form(before)
		var pending_after: int = ProfileService.get_pending_frame_tier_form(after)
		if pending_after >= 0:
			tier_choice = true

			if after_form > 0:
				tier_unlocked = after_form
			from_form = (
				_current_frame_form(_frame_award_id)
				if pending_before >= 0
				else maxi(0, before_form)
			)
			if before > 0 and pending_before >= 0:
				title_key = "RANK_TIER_CELE"
		var display_form: int = from_form if tier_unlocked > 0 else maxi(0, after_form)
		cell.set_frame(_frame_award_id, display_form)

	if before <= 0:
		cell.show_count_static(after)
	else:
		cell.show_count_static(before)

	if _frame_anim != null and _frame_anim.has_animation(&"Appear"):
		_frame_anim.play(&"Appear")
		await _frame_anim.animation_finished

	var hold_sec: float
	if before <= 0:
		hold_sec = _FRAME_HOLD_NO_ROLL
	else:
		cell.play_count_increase(before, after)
		hold_sec = _FRAME_HOLD_WITH_ROLL
	var hold_tween := create_tween()
	hold_tween.tween_interval(hold_sec)
	await hold_tween.finished

	if tier_choice:
		await _play_frame_tier_upgrade(
			maxi(tier_unlocked, 0),
			_title_with_wins(title_key, after),
			tier_unlocked >= 0,
			from_form
		)
		return

	if before <= 0 and _is_home_visible():
		if _frame_anim != null and _frame_anim.has_animation(&"Disappear"):
			_frame_anim.play(&"Disappear")
		await _fly_frame_to_profile()
	else:
		if _frame_anim != null and _frame_anim.has_animation(&"Disappear"):
			_frame_anim.play(&"Disappear")
			await _frame_anim.animation_finished


func show_frame_tier_only(form: int, wins: int, title_key: String) -> void:
	_frame_award_id = ProfileCatalog.FIRST_PLACE_FRAME_ID
	_frame_award_count = 0
	_pending_equip_form = -1
	_pending_presented_form = -1
	var cell: Control = show_frame_add(_frame_award_id)
	if cell == null:
		push_error("AwardPage: show_frame_tier_only cell is null, form=%d" % form)

		UIManager.hide_ui(get_ui_name())
		return
	_hide_award_backdrop()

	cell.scale = _FRAME_ADD_SCALE
	cell.modulate = Color(1, 1, 1, 1)
	cell.rotation = 0.0
	await _play_frame_tier_upgrade(form, _title_with_wins(title_key, wins))


func _title_with_wins(title_key: String, wins: int) -> String:
	var text: String = tr(title_key)
	if title_key != "RANK_TIER_CELE":
		return text
	return text.format(
		[
			(
				"[color=%s][font_size=%d]%d[/font_size][/color]"
				% [_TIER_WINS_COLOR, _TIER_WINS_FONT_SIZE, wins]
			)
		]
	)


func _current_frame_form(frame_id: int) -> int:
	if frame_id != ProfileCatalog.FIRST_PLACE_FRAME_ID:
		return 0
	return ProfileService.get_frame_form()


func _play_frame_tier_upgrade(
	form: int, title_text: String, play_up_anim: bool = true, from_form: int = -1
) -> void:
	_tier_gate_id += 1
	var my_tier_id: int = _tier_gate_id

	if play_up_anim:
		var start_form: int = (
			from_form
			if ProfileCatalog.is_valid_form(from_form)
			else _current_frame_form(_frame_award_id)
		)
		_frame_add_cell.set_frame(_frame_award_id, start_form)

		_frame_add_cell.set_count_forced(ProfileService.get_first_place_wins() + _frame_award_count)
	_tier_title.text = title_text
	if play_up_anim and _frame_anim != null and _frame_anim.has_animation(_TIER_UP_ANIM):
		_frame_anim.play(_TIER_UP_ANIM)

		await get_tree().create_timer(_TIER_FRAME_SWAP_SEC).timeout

		if my_tier_id != _tier_gate_id:
			return
		_frame_add_cell.set_frame(_frame_award_id, form)
		await _frame_anim.animation_finished
	elif play_up_anim:
		_frame_add_cell.set_frame(_frame_award_id, form)

	if my_tier_id != _tier_gate_id:
		return

	_tier_choice_pending = true

	if _tier_fade_tw != null and _tier_fade_tw.is_valid():
		_tier_fade_tw.kill()
	_tier_group.modulate.a = 0.0
	_tier_group.visible = true
	_tier_fade_tw = create_tween()
	_tier_fade_tw.tween_property(_tier_group, "modulate:a", 1.0, _TIER_GROUP_FADE_IN_SEC)

	var equipped: bool = await _tier_choice

	if my_tier_id != _tier_gate_id:
		return
	_tier_choice_pending = false
	_tier_group.visible = false
	_pending_presented_form = form

	if _frame_anim != null and _frame_anim.has_animation(&"Disappear"):
		_frame_anim.play(&"Disappear")

	ProfileService.set_frame_red_dot()
	if equipped:
		_pending_equip_form = form

		if _podium_gold_available():
			await _fly_frame_to_podium(form)
		else:
			await _fly_frame_to_profile()
	else:
		await _fly_frame_to_profile()

	if my_tier_id != _tier_gate_id:
		return

	UIManager.hide_ui(get_ui_name())


func _on_tier_equip_pressed() -> void:
	if not _tier_choice_pending:
		return
	_tier_choice.emit(true)


func _on_tier_collect_pressed() -> void:
	if not _tier_choice_pending:
		return
	_tier_choice.emit(false)


func _fly_frame_to_profile() -> void:
	var from_pos: Vector2 = _frame_add_effect.get_global_rect().get_center()
	var to_pos: Vector2 = _resolve_profile_entry_center()

	var show_tw := create_tween()
	show_tw.tween_interval(_FRAME_TRAIL_SHOW_DELAY)
	await show_tw.finished
	var trail: Node = _FRAME_TRAIL_SCENE.instantiate()
	add_child(trail)
	trail.z_index = 100
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return
	sprite.global_position = from_pos
	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from_pos
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false

	var head_particles: Array[CPUParticles2D] = []
	for child in sprite.get_children():
		if child is CPUParticles2D:
			sprite.remove_child(child)
			fly_target.add_child(child)
			child.visible = true
			child.emitting = true
			head_particles.append(child)

	var lead_tw := create_tween()
	lead_tw.tween_interval(_FRAME_FLY_START_DELAY - _FRAME_TRAIL_SHOW_DELAY)
	await lead_tw.finished
	UIManager.fade_out_mask_early(0.2)

	var tw: Tween = trail.create_tween()
	tw.tween_method(
		func(t: float) -> void:
			if is_instance_valid(fly_target):
				fly_target.global_position = _frame_fly_pos(t, from_pos, to_pos)
				sprite.notify_target_moved(),
		0.0,
		1.0,
		_FRAME_FLY_DURATION
	)
	await tw.finished

	for p in head_particles:
		if is_instance_valid(p):
			p.visible = false
			p.emitting = false
	if is_instance_valid(trail):
		var trail_ref: Node = trail
		get_tree().create_timer(_FRAME_TRAIL_HIDE_DELAY).timeout.connect(
			func() -> void:
				if is_instance_valid(trail_ref):
					trail_ref.queue_free()
		)

	_spawn_frame_burst(to_pos)
	_play_profile_shake()

	var hold := create_tween()
	hold.tween_interval(0.4)
	await hold.finished


func _fly_frame_to_podium(form: int) -> void:
	var from_pos: Vector2 = _frame_add_effect.get_global_rect().get_center()
	var to_pos: Vector2 = _resolve_podium_gold_center()

	var show_tw := create_tween()
	show_tw.tween_interval(_FRAME_TRAIL_SHOW_DELAY)
	await show_tw.finished
	var trail: Node = _FRAME_TRAIL_SCENE.instantiate()
	add_child(trail)
	trail.z_index = 100
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return
	sprite.global_position = from_pos
	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from_pos
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false

	var head_particles: Array[CPUParticles2D] = []
	for child in sprite.get_children():
		if child is CPUParticles2D:
			sprite.remove_child(child)
			fly_target.add_child(child)
			child.visible = true
			child.emitting = true
			head_particles.append(child)

	var lead_tw := create_tween()
	lead_tw.tween_interval(_FRAME_FLY_START_DELAY - _FRAME_TRAIL_SHOW_DELAY)
	await lead_tw.finished
	UIManager.fade_out_mask_early(0.2)

	var tw: Tween = trail.create_tween()
	tw.tween_method(
		func(t: float) -> void:
			if is_instance_valid(fly_target):
				fly_target.global_position = _frame_fly_pos(t, from_pos, to_pos)
				sprite.notify_target_moved(),
		0.0,
		1.0,
		_FRAME_FLY_DURATION
	)
	await tw.finished

	for p in head_particles:
		if is_instance_valid(p):
			p.visible = false
			p.emitting = false
	if is_instance_valid(trail):
		var trail_ref: Node = trail
		get_tree().create_timer(_FRAME_TRAIL_HIDE_DELAY).timeout.connect(
			func() -> void:
				if is_instance_valid(trail_ref):
					trail_ref.queue_free()
		)

	_spawn_frame_burst(to_pos)
	_apply_podium_gold_frame_form(form)

	var podium_hold := create_tween()
	podium_hold.tween_interval(0.4)
	await podium_hold.finished


func _frame_fly_pos(t: float, from: Vector2, to: Vector2) -> Vector2:
	var ex: float = _cubic_bezier(t, _FRAME_FLY_BEZIER_X)
	var ey: float = _cubic_bezier(t, _FRAME_FLY_BEZIER_Y)
	return Vector2(lerpf(from.x, to.x, ex), lerpf(from.y, to.y, ey))


func _cubic_bezier(t: float, cp: Array) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var u: float = _solve_bezier_x(t, cp[0], cp[2])
	return _bezier_axis(u, cp[1], cp[3])


func _bezier_axis(u: float, a1: float, a2: float) -> float:
	var v: float = 1.0 - u
	return 3.0 * v * v * u * a1 + 3.0 * v * u * u * a2 + u * u * u


func _bezier_deriv(u: float, a1: float, a2: float) -> float:
	var v: float = 1.0 - u
	return 3.0 * v * v * a1 + 6.0 * v * u * (a2 - a1) + 3.0 * u * u * (1.0 - a2)


func _solve_bezier_x(t: float, x1: float, x2: float) -> float:
	var u: float = t
	for _i in range(8):
		var fx: float = _bezier_axis(u, x1, x2) - t
		if absf(fx) < 0.0001:
			return u
		var d: float = _bezier_deriv(u, x1, x2)
		if absf(d) < 1e-06:
			break
		u -= fx / d
	var lo: float = 0.0
	var hi: float = 1.0
	u = t
	for _i in range(20):
		var x: float = _bezier_axis(u, x1, x2)
		if absf(x - t) < 0.0001:
			break
		if x < t:
			lo = u
		else:
			hi = u
		u = (lo + hi) * 0.5
	return u


func _play_profile_shake() -> void:
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home != null and home.has_method("play_profile_shake"):
		home.play_profile_shake()


func _resolve_podium_node() -> Node:
	return UIManager.get_ui(UiName.RANK_ACTIVITY_PAGE)


func _podium_gold_available() -> bool:
	var podium: Node = _resolve_podium_node()
	return (
		podium != null
		and podium.has_method("get_podium_avatar_center")
		and podium.has_method("set_podium_frame_form")
		and podium.has_method("has_podium_avatar")
		and podium.has_podium_avatar(1)
	)


func _resolve_podium_gold_center() -> Vector2:
	var podium: Node = _resolve_podium_node()
	if podium != null and podium.has_method("get_podium_avatar_center"):
		return podium.get_podium_avatar_center(1)
	return Vector2.ZERO


func _apply_podium_gold_frame_form(form: int) -> void:
	var podium: Node = _resolve_podium_node()
	if podium != null and podium.has_method("set_podium_frame_form"):
		podium.set_podium_frame_form(
			1,
			ProfileCatalog.FIRST_PLACE_FRAME_ID,
			form,
			ProfileService.get_first_place_wins() + _frame_award_count
		)


func _spawn_frame_burst(pos: Vector2) -> void:
	var burst: Node = _FRAME_BURST_SCENE.instantiate()
	add_child(burst)
	burst.z_index = 100
	burst.global_position = pos
	for child_name: String in ["GlowAlp", "StarAlp", "StarAdd"]:
		var p: Node = burst.get_node_or_null(child_name)
		if p != null and p is CPUParticles2D:
			(p as CPUParticles2D).emitting = true
	var bt: Tween = burst.create_tween()
	bt.tween_interval(1.5)
	bt.tween_callback(burst.queue_free)


func _is_home_visible() -> bool:
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	return home != null and home.is_showing()


func _resolve_profile_entry_center() -> Vector2:
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home != null and home.has_method("get_profile_entry_center"):
		return home.get_profile_entry_center()
	return Vector2(119.5, 240.0)
