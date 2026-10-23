## 排行榜变动页的虚拟列表版本；协调名次上升、前三名换位、收集飞行和连胜演出。
## 异步动画可能在页面关闭后返回，因此重用/关闭路径必须停止 Tween、取消旧回调并恢复最终状态。

extends UIFrameWindow

const _RANK_CELL: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")
const _AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")
const _RANK_BULLET: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_bullet.tscn")

const _COLLECTION_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_change_collection.tscn"
)

const _PODIUM_COUNT: int = 3

const _APPEAR3_START: float = 0.2
const _APPEAR3_INTERVAL: float = 0.0667
const _COUNT_START: float = 0.7333
const _SCORE_ROLL_DELAY: float = 1.0
const _ARROW_HIDE_DELAY: float = 0.03
const _RISE_DOWN_SWAP_DELAY: float = 0.23
const _TAP_FADE_IN_DUR: float = 0.25

const _TAP_BOTTOM_GAP_MIN_H: float = 111.0
const _TAP_BOTTOM_GAP_MAX_H: float = 315.0
const _TAP_VIS_H_MIN: float = 1920.0
const _TAP_VIS_H_MAX: float = 2400.0

const _SAFE_BOTTOM_BASELINE_META: StringName = &"_safe_bottom_baseline"

const _LIST_PAD_TOP: float = 20.0

const _LIST_PAD_BOTTOM: float = 200.0

const _PODIUM_DROP_DUR: float = 0.167
const _PODIUM_FLY_DUR: float = 0.4
const _PODIUM_SETTLE_DUR: float = 0.1
const _PODIUM_BOUNCE_DUR: float = 0.167

const _PODIUM_OVERSHOOT: float = 50.0

const _PODIUM_AVATAR_DOWN_Y: float = 300.0

const _PODIUM_SCALE_LOW: float = 0.9
const _PODIUM_SCALE_HIGH: float = 1.2
const _PODIUM_SCALE_DIP: float = 0.95
const _PODIUM_SCALE_END: float = 1.05

const _PODIUM_SWEEP_DELAY: float = 0.1

const _PODIUM_OTHERS_SWAP_DELAY: float = 0.4

const _PODIUM_AVATAR_SCALE: float = 210.0 / 185.0

const _PODIUM_TAG_TOP: float = 415.0

const _LIST_TOP_TAG_DELTA: float = 20.0

const _C_COUNT_LEN: float = 1.6667
const _C_ROLL_DELAY: float = 1.0
const _C_LIFT_START: float = 1.7667
const _C_LIFT_DOWN: float = 1.9667
const _C_FLY_START: float = 2.0667
const _C_SWEEP_AT: float = 2.2334
const _C_MID_AT: float = 2.3667
const _C_LAND_AT: float = 2.5
const _C_END_AT: float = 2.6667

const _CLOCK_SPAN: float = 3600.0
const _C_MID_ABOVE: float = 85.0
const _C_LIFT_SCALE: float = 0.85

const _C_SCALE_MID: float = 1.2
const _C_SCALE_LAND: float = 0.9

const _C_BEZ_FLY_X: Vector4 = Vector4(0.389, 0.25, 1.0, 1.0)
const _C_BEZ_FLY_Y: Vector4 = Vector4(0.0, 0.0, 0.667, 1.0)

const _C_BEZ_DROP_Y: Vector4 = Vector4(0.75, 0.0, 1.0, 1.0)
const _C_BEZ_SCALE_FLY: Vector4 = Vector4(0.6667, 0.0, 0.3333, 1.0)
const _C_BEZ_SCALE_MID: Vector4 = Vector4(0.75, 0.0, 1.0, 1.0)
const _C_BEZ_SCALE_LAND: Vector4 = Vector4(0.0198, 0.0, 1.0, 1.0)
const _C_BEZ_LINEAR: Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)

const _C_FLYER_Z: int = 4

const _C_COLLECTION_OFFSET: Vector2 = Vector2(292.5, 21.0)
const _C_COLLECTION_SIZE: float = 40.0

@onready var _list_group: Control = $Root/ListGroup
@onready var _virtual_list: VirtualList = $Root/ListGroup/RankCellMask/VirtualList
var _scroll: ScrollContainer:
	get:
		return _virtual_list.scroll
@onready var _celebrate_layer: Control = $Root/PlayerCelebrate

@onready var _celebrate_clip: Control = $Root/PlayerCelebrate/CellClip
@onready var _podium: Control = $Root/PodiumArea/Top3Podium
@onready var _podium_anim: AnimationPlayer = $Root/PodiumArea/Top3Podium/AnimationPlayer
@onready var _countdown_label: Label = $Root/Countdown/CountdownText
@onready var _progress_label: RichTextLabel = $Root/EncourageTopBar/ProgressLabel
@onready var _encourage_bar: Control = $Root/EncourageTopBar
@onready var _encourage_anim: AnimationPlayer = $Root/EncourageTopBar/AnimationPlayer
@onready var _mask: ColorRect = $Mask
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _tap: Button = $Root/TapToContinue
@onready var _bullets_area: Control = $Root/BulletsArea

@onready var _heart_bg: Control = $Root/HeartBg
@onready var _heart_slot1: LifeSlot = $Root/HeartBg/LifeSlot
@onready var _heart_slot2: LifeSlot = $Root/HeartBg/LifeSlot2
@onready var _heart_slot3: LifeSlot = $Root/HeartBg/LifeSlot3
const _SETTLE_TRAIL_SCENE: PackedScene = preload("res://assets/prefab/effect_score_trail.tscn")
const _SETTLE_BURST_SCENE: PackedScene = preload("res://assets/prefab/effect_score_burst.tscn")

const _SETTLE_TRAIL_Z: int = 20
const _SETTLE_FISH_Z: int = 21

const _STREAK_PODIUM_FISH_SCALE: float = 0.5
const _SETTLE_BEZIER_X: Vector4 = Vector4(0.125, 0.0, 0.875, 1.0)
const _SETTLE_BEZIER_Y: Vector4 = Vector4(0.0, 0.141343, 0.7, 1.0)
const _SETTLE_FLY_DELAY: float = 0.2
const _SETTLE_FLY_INTERVAL: float = 0.083
const _SETTLE_FLY_DUR: float = 0.4
const _SETTLE_TRAIL_FADE: float = 0.3
const _SETTLE_BURST_PODIUM_SCALE: float = 0.6
const _SETTLE_TRAIL_ARC_X: float = 50.0
var _settle_lives: int = 0

var _is_golden_fish: bool = false

var _suppress_settle_flight: bool = false
var _settle_trails: Array = []

const _STREAK_BAR_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_streak_bar.tscn"
)

const _STREAK_BAR_GAP: float = 30.0
const _STREAK_BAR_HALF_WIDTH: float = 540.0

const _STREAK_FLY_MAX: int = RankStreakFishShow.MAX_FISH

const _STREAK_TIER_UP_AT: float = 0.634
const _STREAK_FLASH_AT: float = 0.3
var _streak_bar: RankStreakBar = null

var _streak_fly_active: bool = false
var _streak_multiplier: int = 1
var _streak_prev_multiplier: int = 0
var _streak_tier_up: bool = false

var _streak_timeline: Dictionary = {}

var _c_time_shift: float = 0.0
var _barrage_bullets: Array[RankBullet] = []
var _barrage_generation: int = 0

var _bullets_z_baseline: int = 0

@export_group("上浮动效")
@export var rise_base_dur: float = 1.0
@export var rise_per_place: float = 0.05
@export var rise_min_dur: float = 1.0
@export var rise_max_dur: float = 3.0
@export var domino_drop_ratio: float = 1.0
@export var score_roll_dur: float = 0.6333
@export var lift_hold_dur: float = 0.3
@export var settle_hold_dur: float = 0.3
@export var finish_hold_dur: float = 0.5
@export var arrow_fade_dur: float = 0.5

@export_group("升进前 3 · 上浮 + 飞出")
@export var flyout_rise_per_place: float = 0.25
@export var flyout_rise_min_dur: float = 0.5

@export var flyout_dist_px: float = 936.0

@export var flyout_handoff_at_px: float = 74.0

var _row_infos: Array = []
var _list_state: RankChangeListState = RankChangeListState.new()
var _list_adapter: RankChangeVirtualListAdapter
var _intro_tweens: Dictionary = {}
var _show_generation: int = 0
var _like_states_by_target: Dictionary = {}
var _podium_avatars: Array = [null, null, null]
var _my_rank_info: RankInfo = null
var _my_cell: Control = null
var _fake_active: bool = false
var _win_increment: int = 0
var _advance: int = 0
var _show_encourage: bool = false
var _anim_active: bool = false
var _rise_tween: Tween = null
var _score_tween: Tween = null

var _ff_gen: int = 0

var _ff_done: bool = false

var _ff_ready: bool = false

var _rise_ctx: Dictionary = {}
var _last_shown_rank: int = -1
var _was_unranked: bool = false

var _my_on_podium: bool = false
var _my_old_on_podium: bool = false

var _podium_old_infos: Array = []

var _list_top_baseline: float = NAN
var _my_new_rank: int = 0
var _my_old_rank: int = 0

var _flyout_start_y: float = 0.0

var _clock_tween: Tween = null

var _podium_tweens: Array[Tween] = []

var _c_fly_tween: Tween = null

var _c_flyer: Control = null

var _c_collections: Array = [null, null, null]


func on_create() -> void:
	add_update_listener(_sync_fake_cell)

	add_update_listener(_anim_watchdog_tick)

	_list_adapter = RankChangeVirtualListAdapter.new(self, _list_state)
	_virtual_list.set_adapter(_list_adapter)
	connect_managed(_bullets_area.resized, _align_barrage_lanes)
	_bullets_z_baseline = _bullets_area.z_index
	_podium.connect(&"like_heart_pressed", _on_like_heart_pressed)
	_warm_first_cell()


func _warm_first_cell() -> void:
	var w: Control = _RANK_CELL.instantiate()
	add_child(w)
	w.set_collection_visual()
	remove_child(w)
	w.free()


func _is_settle_flight_active() -> bool:
	if _streak_fly_active:
		return true
	return _is_heart_bg_flight()


func _is_heart_bg_flight() -> bool:
	if _suppress_settle_flight:
		return false
	if _is_golden_fish:
		return false
	if _streak_fly_active:
		return false
	return ABTestManager.leaderboard_collection_levelwin.is_settle_page_flight()


func _setup_streak_bar(from_game: bool) -> void:
	var table: Array = RankActivityManager.get_streak_table() if from_game else []
	_streak_multiplier = RankActivityManager.get_last_win_multiplier()
	_streak_prev_multiplier = RankActivityManager.get_prev_win_multiplier()
	_streak_tier_up = RankActivityManager.did_last_win_tier_up()
	_streak_fly_active = not table.is_empty() and _win_increment > 0 and not _suppress_settle_flight
	_streak_timeline = (
		RankStreakFishShow.timeline(mini(_win_increment, _STREAK_FLY_MAX), _streak_tier_up)
		if _streak_fly_active
		else {}
	)
	if table.is_empty():
		_bullets_area.z_index = _bullets_z_baseline
		if _streak_bar != null and is_instance_valid(_streak_bar):
			_streak_bar.visible = false
		return

	var fish_total_z: int = _celebrate_layer.z_index + _SETTLE_TRAIL_Z
	if _streak_bar == null or not is_instance_valid(_streak_bar):
		var countdown: Control = $Root/Countdown
		var bar_top: float = countdown.size.y + _STREAK_BAR_GAP
		_streak_bar = _STREAK_BAR_SCENE.instantiate() as RankStreakBar
		_streak_bar.z_index = 6
		_streak_bar.anchor_left = 0.5
		_streak_bar.anchor_right = 0.5
		_streak_bar.offset_left = -_STREAK_BAR_HALF_WIDTH
		_streak_bar.offset_right = _STREAK_BAR_HALF_WIDTH
		_streak_bar.offset_top = bar_top
		_streak_bar.offset_bottom = bar_top + _streak_bar.custom_minimum_size.y
		countdown.add_child(_streak_bar)

		_streak_bar.set_plus_z_index(fish_total_z + 1 - countdown.z_index - _streak_bar.z_index)

	_bullets_area.z_index = fish_total_z - 1
	_streak_bar.setup(table)
	_streak_bar.visible = true

	if _streak_tier_up:
		_streak_bar.show_tier(_streak_tier_index(_streak_prev_multiplier))
	else:
		_streak_bar.show_tier(_streak_tier_index(_streak_multiplier))


func _streak_tier_index(multiplier: int) -> int:
	if _streak_bar == null:
		return -1
	var table: Array = RankActivityManager.get_streak_table()
	return table.find(multiplier)


func _play_streak_tier_anim(gen: int) -> void:
	if _streak_bar == null or not is_instance_valid(_streak_bar) or not _streak_bar.visible:
		return
	await _await_abs(_STREAK_TIER_UP_AT if _streak_tier_up else _STREAK_FLASH_AT)
	if gen != _ff_gen or not is_showing():
		return
	var to_index: int = _streak_tier_index(_streak_multiplier)
	if _streak_tier_up:
		SoundManager.play(SoundManager.Kind.RANK_RISE_UP)
		_streak_bar.play_tier_up(_streak_tier_index(_streak_prev_multiplier), to_index)
	else:
		_streak_bar.flash_tier(to_index)


func _start_streak_fish_show(gen: int, on_podium_no_row: bool) -> void:
	if (
		not _streak_fly_active
		or _streak_timeline.is_empty()
		or _streak_bar == null
		or not is_instance_valid(_streak_bar)
	):
		return
	var to_provider: Callable
	var arrive: Callable

	var reseed := func(burst: Node) -> void: RankStreakFishShow.reseed_particles(burst)
	if on_podium_no_row:
		if _podium == null:
			return
		var rank_slot: int = clampi(_my_old_rank - 1, 0, _PODIUM_COUNT - 1) + 1
		to_provider = func() -> Vector2: return _podium.get_fish_icon_global(rank_slot)
		arrive = func() -> void: _spawn_podium_fish_burst(rank_slot, reseed)
	elif _my_cell != null and is_instance_valid(_my_cell):
		var cell := _my_cell
		to_provider = func() -> Vector2:
			return cell.get_fish_icon_global() if is_instance_valid(cell) else Vector2.ZERO

		var behind_icon := func(burst: Node) -> void:
			reseed.call(burst)
			(burst as CanvasItem).show_behind_parent = true
		arrive = func() -> void:
			if is_instance_valid(cell):
				cell.emit_fish_collect_burst(behind_icon)
	else:
		return
	var tier_index: int = _streak_tier_index(_streak_multiplier)
	var alive := func() -> bool: return gen == _ff_gen and is_showing()
	var fish_show := RankStreakFishShow.new()
	fish_show.layer = _celebrate_layer
	fish_show.clock = func() -> float:
		return (
			_clock_tween.get_total_elapsed_time()
			if _clock_tween != null and _clock_tween.is_valid()
			else 0.0
		)
	fish_show.alive = alive

	fish_show.register = func(node: Node) -> void: _settle_trails.append(node)
	fish_show.release = _free_settle_trail
	fish_show.fish_z = _SETTLE_TRAIL_Z
	fish_show.arrive_scale = _STREAK_PODIUM_FISH_SCALE if on_podium_no_row else 1.0
	fish_show.to_podium = on_podium_no_row

	var fish_kinds: Array = [
		SoundManager.Kind.RANK_FISH_COLLECT_1,
		SoundManager.Kind.RANK_FISH_COLLECT_2,
		SoundManager.Kind.RANK_FISH_COLLECT_3,
	]
	var on_launch := func(order: int) -> void:
		SoundManager.play(fish_kinds[clampi(order, 0, fish_kinds.size() - 1)])
	fish_show.play(
		_streak_bar.get_tier_global_center(tier_index),
		int(_streak_timeline["count"]),
		_streak_tier_up,
		to_provider,
		on_launch,
		arrive
	)
	var plus_delay: float = float(_streak_timeline["plus"]) - float(fish_show.clock.call())
	var bar := _streak_bar
	get_tree().create_timer(maxf(0.0, plus_delay)).timeout.connect(
		func() -> void:
			if alive.call() and is_instance_valid(bar):
				bar.play_plus(_win_increment, tier_index)
	)


func _streak_roll_dur() -> float:
	if _streak_timeline.is_empty():
		return score_roll_dur
	return maxf(
		0.0, float(_streak_timeline["last_arrive"]) - float(_streak_timeline["first_arrive"])
	)


const _ANIM_WATCHDOG_SEC: float = 15.0

var _anim_elapsed_sec: float = 0.0
var _watchdog_fired: bool = false

const _TRACE_MAX: int = 16
const _TRACE_TAG: String = "[RankStuck]"

var _trace: Array[String] = []


## 监测演出是否异常停滞；超出允许时长时走强制收尾，让页面恢复可继续操作。
func _anim_watchdog_tick() -> void:
	if not _anim_active:
		_anim_elapsed_sec = 0.0
		_watchdog_fired = false
		return
	_anim_elapsed_sec += get_process_delta_time()
	if _anim_elapsed_sec > _ANIM_WATCHDOG_SEC and not _watchdog_fired:
		_watchdog_fired = true
		_force_finish_stuck_anim()


func _trace_add(what: String) -> void:
	_trace.append(
		(
			"%7.2fs f=%d %s | gen=%d active=%s"
			% [
				Time.get_ticks_msec() / 1000.0,
				Engine.get_frames_drawn(),
				what,
				_ff_gen,
				_anim_active
			]
		)
	)
	if _trace.size() > _TRACE_MAX:
		_trace.remove_at(0)


## 把未完成演出收敛到最终排名状态，清理动画占用，避免玩家被卡在禁用输入的页面。
func _force_finish_stuck_anim() -> void:
	push_warning("rank change v2: 动画 %.0fs 未收尾,强制收尾(卡死兜底)" % _ANIM_WATCHDOG_SEC)

	print(
		(
			"%s 动画 %.1fs 未收尾。ff_ready=%s ff_done=%s 名次%d→%d adv=%d on_podium=%s slots=%d"
			% [
				_TRACE_TAG,
				_anim_elapsed_sec,
				_ff_ready,
				_ff_done,
				_my_old_rank,
				_my_new_rank,
				_advance,
				_my_on_podium,
				int(_rise_ctx.get("slots", -1))
			]
		)
	)
	for i in _trace.size():
		print("%s  %2d) %s" % [_TRACE_TAG, i + 1, _trace[i]])
	_ff_gen += 1
	_anim_active = false
	_finish_and_enable_scroll()


## 从结算数据构造旧名次到新名次的展示过程，选择普通列表上升或领奖台换位演出。
func on_show(params: Dictionary = {}) -> void:
	_show_generation += 1
	_virtual_list.set_active(true)

	RankActivityManager.set_online_window_sec(RankOnlineHelper.window_sec_from_ab())

	_anim_elapsed_sec = 0.0
	_watchdog_fired = false

	_trace_add("on_show 进场 active=%s ff_ready=%s ff_done=%s" % [_anim_active, _ff_ready, _ff_done])
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_scroll.scroll_vertical = int(_scroll_top_floor())
	_align_celebrate_clip()
	_fake_active = false
	connect_managed(_mask.gui_input, _on_mask_input)
	_apply_tap_bottom_gap()

	connect_managed(get_viewport().size_changed, _apply_tap_bottom_gap)

	var mock_infos: Array = params.get("mock_infos", [])
	_win_increment = 0
	if mock_infos.is_empty():
		connect_managed(RankActivityManager.ranking_changed, _on_ranking_changed)
		connect_managed(ClockTicker.second_tick, _update_countdown)
		_win_increment = RankActivityManager.get_last_win_increment()
	_win_increment = int(params.get("score_increment", _win_increment))
	_advance = int(params.get("advance_places", 0))

	_settle_lives = int(params.get("lives", 0))

	_is_golden_fish = bool(params.get("is_golden_fish", false))

	_suppress_settle_flight = bool(params.get("suppress_settle_flight", false))

	_setup_streak_bar(mock_infos.is_empty() and not params.has("score_increment"))
	var _is_g1: bool = _is_heart_bg_flight()
	if _heart_bg != null:
		_heart_bg.visible = _is_g1
	if _is_g1:
		var _hb_slots: Array = [_heart_slot1, _heart_slot2, _heart_slot3]
		for i in _hb_slots.size():
			var slot: LifeSlot = _hb_slots[i] as LifeSlot
			if slot == null:
				continue
			if i < _settle_lives:
				slot.show_alive()
			else:
				slot.show_lost(false, true)

	_rebuild(mock_infos, false)

	if mock_infos.is_empty():
		_apply_encouragement(
			RankActivityManager.consume_progress_encouragement(_reach_rank_limit(), _advance)
		)
	else:
		_apply_encouragement({"kind": "climb", "advance": _advance})

	_encourage_bar.visible = false
	_tap.visible = false
	_play_barrages(params.get("rank_like_result", {}) as Dictionary)
	_play_win_anim(_advance)


func _apply_tap_bottom_gap() -> void:
	if _tap == null or not is_instance_valid(_tap):
		return
	var vis_h: float = get_viewport().get_visible_rect().size.y
	var t: float = clampf((vis_h - _TAP_VIS_H_MIN) / (_TAP_VIS_H_MAX - _TAP_VIS_H_MIN), 0.0, 1.0)
	var gap: float = lerpf(_TAP_BOTTOM_GAP_MIN_H, _TAP_BOTTOM_GAP_MAX_H, t)

	var height: float = _tap.offset_bottom - _tap.offset_top
	var new_top: float = -gap
	var new_bottom: float = new_top + height
	var inset: float = 0.0
	if _tap.has_meta(_SAFE_BOTTOM_BASELINE_META):
		var baseline: Vector2 = _tap.get_meta(_SAFE_BOTTOM_BASELINE_META)
		inset = baseline.x - _tap.offset_top
	_tap.set_meta(_SAFE_BOTTOM_BASELINE_META, Vector2(new_top, new_bottom))
	_tap.offset_top = new_top - inset
	_tap.offset_bottom = new_bottom - inset


func on_stack_bottom() -> void:
	_cancel_row_intros()
	_list_adapter.intro_pending = false
	_virtual_list.set_active(false)


func on_stack_top() -> void:
	if is_showing():
		_virtual_list.set_active(true)
		_virtual_list.refresh_presentation()


## 关闭时停止弹幕、飞行与列表演出并清理节点；异步回调不能继续操作已关闭的展示。
func on_hide() -> void:
	_show_generation += 1
	_cancel_row_intros()
	_virtual_list.set_active(false)
	_clear_barrages()

	if _c_fly_tween != null and _c_fly_tween.is_valid():
		_c_fly_tween.kill()
	_c_fly_tween = null
	if _clock_tween != null and _clock_tween.is_valid():
		_clock_tween.kill()
	_clock_tween = null
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = null
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = null
	_anim_active = false
	_kill_podium_tweens()
	_reset_settle_trails()

	_trace_add("on_hide 改编号 %d→%d" % [_ff_gen, _ff_gen + 1])
	_ff_gen += 1
	_ff_done = false
	_ff_ready = false
	_rise_ctx = {}
	_clear_cells()
	_reset_visuals_to_baseline()


func _play_barrages(rank_like_result: Dictionary) -> void:
	_clear_barrages()
	var barrages: Array = rank_like_result.get("barrages", [])
	if barrages.is_empty() or _bullets_area == null:
		return
	_align_barrage_lanes()
	_start_barrage_sequence(barrages, _barrage_generation)


func _start_barrage_sequence(barrages: Array, generation: int) -> void:
	var barrage_rng := RandomNumberGenerator.new()
	barrage_rng.randomize()
	var schedule: Array[Dictionary] = RankLikeLogic.make_barrage_schedule(
		barrages.size(), barrage_rng
	)
	for index: int in barrages.size():
		if generation != _barrage_generation or not is_showing():
			return
		var barrage: Dictionary = barrages[index]
		var schedule_item: Dictionary = schedule[index]
		_spawn_barrage(barrage, int(schedule_item["lane_index"]))
		if index < barrages.size() - 1:
			await get_tree().create_timer(float(schedule_item["next_delay_sec"])).timeout


func _align_barrage_lanes() -> void:
	if _bullets_area == null:
		return
	var start_x: float = _bullets_area.size.x
	for lane_index: int in range(1, 4):
		var lane: Control = _bullets_area.get_node_or_null("Pos%d" % lane_index) as Control
		if lane != null:
			lane.position = Vector2(start_x, lane.position.y)


func _spawn_barrage(barrage: Dictionary, lane_index: int) -> void:
	var lane: Control = _bullets_area.get_node_or_null("Pos%d" % (lane_index + 1)) as Control
	if lane == null:
		return
	var bullet: RankBullet = _RANK_BULLET.instantiate() as RankBullet
	if bullet == null:
		return
	_bullets_area.add_child(bullet)
	bullet.set_barrage(barrage)
	_barrage_bullets.append(bullet)
	bullet.start_moving(lane.position, -bullet.size.x)


func _clear_barrages() -> void:
	_barrage_generation += 1
	for bullet: RankBullet in _barrage_bullets:
		if not is_instance_valid(bullet):
			continue
		bullet.stop_motion()
		bullet.queue_free()
	_barrage_bullets.clear()


func _reset_visuals_to_baseline() -> void:
	_scroll.scroll_vertical = 0
	if _tap != null:
		_tap.visible = false

	if _streak_bar != null and is_instance_valid(_streak_bar):
		_streak_bar.snap_to(-1)
		_streak_bar.visible = false
	_streak_fly_active = false

	if _c_flyer != null and is_instance_valid(_c_flyer):
		destroy_child(_c_flyer)
	_c_flyer = null
	if _podium != null:
		for r in range(1, _PODIUM_COUNT + 1):
			var m: Control = _podium.get_avatar_mount(r)
			if m != null:
				m.visible = true

			_podium.set_fish_icon_above_z(r, 0)
	for i in range(_c_collections.size()):
		var inst: Node = _c_collections[i] as Node
		if inst == null or not is_instance_valid(inst):
			continue
		var cap := inst.get_node_or_null("CollectionAppear") as AnimationPlayer
		if cap != null and cap.has_animation(&"RESET"):
			cap.play(&"RESET")
			cap.advance(0.0)
			cap.pause()
	if _encourage_bar != null:
		_encourage_bar.visible = false
	if _podium_anim != null and _podium_anim.has_animation(&"RESET"):
		_podium_anim.play(&"RESET")
		_podium_anim.advance(0.0)
		_podium_anim.pause()
	if _anim != null and _anim.has_animation(&"Appear"):
		AnimUtil.play(_anim, &"Appear")
		_anim.pause()


## 重建排行快照、领奖台和虚拟列表绑定，给本次名次变化准备统一的数据来源。
func _rebuild(override_infos: Array = [], show_now: bool = true) -> void:
	_clear_cells()
	_my_cell = null
	_row_infos.clear()
	var is_mock: bool = not override_infos.is_empty()
	var infos: Array = override_infos if is_mock else RankActivityManager.get_rank_infos()
	_like_states_by_target.clear()
	if ABTestManager.rank_like_func.is_like_enabled():
		_like_states_by_target = RankActivityManager.get_rank_like_display_states()
	_my_rank_info = _find_self(infos)
	_was_unranked = _my_rank_info != null and (_my_rank_info.score - _win_increment) <= 0

	var my_new: int = _my_rank_info.rank if _my_rank_info != null else 0
	var my_old: int = my_new
	if _my_rank_info != null:
		var old_score: int = maxi(0, _my_rank_info.score - _win_increment)
		if not is_mock:
			var rank_from_score: int = RankActivityManager.get_rank_for_score(old_score)
			if rank_from_score >= 1:
				my_old = clampi(rank_from_score, my_new, infos.size())
				_advance = maxi(0, my_old - my_new)
			else:
				my_old = my_new
		elif _advance > 0:
			my_old = mini(my_new + _advance, infos.size())
	_my_new_rank = my_new
	_my_old_rank = my_old
	_my_on_podium = my_new >= 1 and my_new <= _PODIUM_COUNT
	_my_old_on_podium = my_old >= 1 and my_old <= _PODIUM_COUNT

	_podium_old_infos = _build_old_order(infos, my_new, my_old).slice(0, _PODIUM_COUNT)
	_populate_podium(_podium_old_infos)

	var snapshots: Array[Dictionary] = []
	for info: RankInfo in infos:
		if info.rank <= _PODIUM_COUNT:
			continue
		_row_infos.append(info)
		var snapshot: Dictionary = (
			RankRowSnapshot
			. from_info(info, RankActivityManager.get_online_window_sec(), str(_show_generation))
			. duplicate()
		)
		var target: String = (
			RankActivityManager.SELF_LIKE_TARGET_ID
			if info.is_self()
			else info.player_info.player_id
		)
		var likes: Dictionary = _like_states_by_target.get(target, {})
		snapshot.like_enabled = (
			ABTestManager.rank_like_func.is_like_enabled() and bool(likes.get("valid", false))
		)
		snapshot.heart_count = int(likes.get("heart_count", 0))
		snapshot.liked = bool(likes.get("liked_by_player", false))
		snapshot.target = target
		snapshot.make_read_only()
		snapshots.append(snapshot)
	_list_state.configure(
		_row_infos.size(), my_new - 4 if not _my_on_podium else -1, my_new, _was_unranked
	)
	var will_animate: bool = _advance > 0 or _win_increment > 0
	_list_state.player_replaced = not show_now and will_animate and not _my_on_podium
	_list_adapter.intro_pending = not show_now
	_list_adapter.snapshots = snapshots
	_virtual_list.reload(false)
	if not show_now and will_animate and _my_rank_info != null and not _my_old_on_podium:
		var fake: RankCell = create_child(_RANK_CELL, {}) as RankCell
		_mount(fake, _celebrate_clip)
		fake.like_heart_pressed.connect(_on_like_heart_pressed)
		fake.apply_score_icon()
		fake.set_show_chest(false)
		_update_row_cell(_my_rank_info, fake)
		fake.set_collection_visual()
		fake.set_entry(
			0 if _was_unranked else my_old,
			true,
			_display_name(_my_rank_info.player_info),
			maxi(0, _my_rank_info.score - _win_increment)
		)
		_my_cell = fake
		_fake_active = not _my_on_podium
	_update_countdown()


func _build_old_order(infos: Array, my_new: int, my_old: int) -> Array:
	var out: Array = infos.duplicate()
	if my_new < 1 or my_old <= my_new or my_new > out.size():
		return out
	var me = out[my_new - 1]
	out.remove_at(my_new - 1)
	out.insert(mini(my_old - 1, out.size()), me)
	return out


func _populate_podium(ordered: Array) -> void:
	_podium.set_show_box(false)

	_podium.set_online_layout(false, _PODIUM_TAG_TOP)
	_apply_list_top_for_online()
	for slot in range(_PODIUM_COUNT):
		var mount: Control = _podium.get_avatar_mount(slot + 1)
		if mount != null:
			mount.z_index = 0
		var info: RankInfo = ordered[slot] if slot < ordered.size() else null
		_set_podium_slot(slot, info)


func _apply_list_top_for_online() -> void:
	if is_nan(_list_top_baseline):
		_list_top_baseline = _list_group.offset_top
	var delta: float = (
		_LIST_TOP_TAG_DELTA if RankActivityManager.get_online_window_sec() > 0 else 0.0
	)
	_list_group.offset_top = _list_top_baseline + delta


func _set_podium_slot(slot: int, info: RankInfo) -> void:
	var rank_no: int = slot + 1
	if _podium_avatars[slot] != null and is_instance_valid(_podium_avatars[slot]):
		destroy_child(_podium_avatars[slot])
	_podium_avatars[slot] = null
	if info == null:
		_podium.apply(rank_no, "", 0)
		_podium.apply_online(rank_no, false, false, 0)
		_apply_podium_like_display(rank_no, null)
		return
	var pinfo: PlayerInfo = info.player_info
	_podium.apply(rank_no, _display_name(pinfo), info.score)
	var window_sec: int = RankActivityManager.get_online_window_sec()
	_podium.apply_online(
		rank_no,
		RankOnlineHelper.should_show(pinfo, window_sec),
		RankOnlineHelper.is_online(info.next_score_sec, window_sec),
		info.idle_sec,
		info.is_self()
	)
	_apply_podium_like_display(rank_no, info)
	var mount: Control = _podium.get_avatar_mount(rank_no)
	if mount == null or pinfo == null:
		return
	var av = create_child(_AVATAR_CELL, {})
	_mount(av, mount)
	av.apply_player_info(pinfo)
	var avatar_scale: float = (mount.size.x / 185.0) if mount.size.x > 0.0 else _PODIUM_AVATAR_SCALE
	av.scale = Vector2(avatar_scale, avatar_scale)
	av.pivot_offset = av.size * 0.5
	av.position = mount.size * 0.5 - av.pivot_offset
	_podium_avatars[slot] = av


func _update_row_cell(info: RankInfo, cell) -> void:
	var pinfo: PlayerInfo = info.player_info
	cell.set_player(pinfo)
	var shown_rank: int = 0 if (info.is_self() and info.score <= 0) else info.rank
	cell.set_entry(shown_rank, info.is_self(), _display_name(pinfo), info.score)

	var window_sec: int = RankActivityManager.get_online_window_sec()
	cell.set_online(
		RankOnlineHelper.should_show(pinfo, window_sec),
		RankOnlineHelper.is_online(info.next_score_sec, window_sec),
		info.idle_sec,
		info.is_self()
	)
	_apply_row_like_display(info, cell)


func _apply_row_like_display(info: RankInfo, cell) -> void:
	if not ABTestManager.rank_like_func.is_like_enabled():
		cell.set_like_display(false)
		return
	var pinfo: PlayerInfo = info.player_info
	if info.is_self():
		var like_state: Dictionary = _like_states_by_target.get(
			RankActivityManager.SELF_LIKE_TARGET_ID, {}
		)
		if not bool(like_state.get("valid", false)):
			cell.set_like_display(false)
			cell.set_meta(&"rank_like_robot_id", "")
			return
		cell.set_like_display(
			true,
			int(like_state.get("heart_count", 0)),
			bool(like_state.get("liked_by_player", false)),
			RankActivityManager.SELF_LIKE_TARGET_ID
		)
		cell.set_meta(&"rank_like_robot_id", RankActivityManager.SELF_LIKE_TARGET_ID)
		return
	if pinfo == null or not pinfo.is_robot:
		cell.set_like_display(false)
		cell.set_meta(&"rank_like_robot_id", "")
		return
	var robot_id: String = pinfo.player_id
	var like_state: Dictionary = _like_states_by_target.get(robot_id, {})
	if not bool(like_state.get("valid", false)):
		cell.set_like_display(false)
		cell.set_meta(&"rank_like_robot_id", "")
		return
	cell.set_like_display(
		true,
		int(like_state.get("heart_count", 0)),
		bool(like_state.get("liked_by_player", false)),
		robot_id
	)
	cell.set_meta(&"rank_like_robot_id", robot_id)


func _apply_podium_like_display(rank: int, info: RankInfo) -> void:
	if not ABTestManager.rank_like_func.is_like_enabled():
		_podium.set_like_display(rank, false)
		return
	if info == null:
		_podium.set_like_display(rank, true, 0, false)
		return
	var pinfo: PlayerInfo = info.player_info
	if info.is_self():
		var like_state: Dictionary = _like_states_by_target.get(
			RankActivityManager.SELF_LIKE_TARGET_ID, {}
		)
		if not bool(like_state.get("valid", false)):
			_podium.set_like_display(rank, false)
			return
		_podium.set_like_display(
			rank,
			true,
			int(like_state.get("heart_count", 0)),
			bool(like_state.get("liked_by_player", false)),
			RankActivityManager.SELF_LIKE_TARGET_ID
		)
		return
	if pinfo == null or not pinfo.is_robot:
		_podium.set_like_display(rank, false)
		return
	var robot_id: String = pinfo.player_id
	var like_state: Dictionary = _like_states_by_target.get(robot_id, {})
	if not bool(like_state.get("valid", false)):
		_podium.set_like_display(rank, false)
		return
	_podium.set_like_display(
		rank,
		true,
		int(like_state.get("heart_count", 0)),
		bool(like_state.get("liked_by_player", false)),
		robot_id
	)


func _on_like_heart_pressed(target_id: String) -> void:
	if not ABTestManager.rank_like_func.is_like_enabled():
		return
	var like_state: Dictionary = (
		RankActivityManager.toggle_player_self_like()
		if target_id == RankActivityManager.SELF_LIKE_TARGET_ID
		else RankActivityManager.toggle_player_like(target_id)
	)
	if not bool(like_state.get("valid", false)):
		return
	_like_states_by_target[target_id] = like_state
	var heart_count: int = int(like_state.get("heart_count", 0))
	var liked_by_player: bool = bool(like_state.get("liked_by_player", false))
	for index in _list_adapter.snapshots.size():
		var snapshot: Dictionary = _list_adapter.snapshots[index]
		if snapshot.target == target_id:
			var updated: Dictionary = snapshot.duplicate()
			updated.heart_count = heart_count
			updated.liked = liked_by_player
			updated.make_read_only()
			_list_adapter.snapshots[index] = updated
			_virtual_list.refresh_item(index)
			_play_bound_row_like_feedback(index, target_id, heart_count, liked_by_player)
	if (
		is_instance_valid(_my_cell)
		and str(_my_cell.get_meta(&"rank_like_robot_id", "")) == target_id
	):
		_my_cell.set_like_display(true, heart_count, liked_by_player, target_id, true)
	_podium.refresh_robot_like_display(target_id, heart_count, liked_by_player, true)


func _play_bound_row_like_feedback(
	index: int, target_id: String, heart_count: int, liked_by_player: bool
) -> void:
	var binding: VirtualListBinding = _list_adapter.bindings.get(index) as VirtualListBinding
	if binding == null or not _virtual_list.is_binding_current(binding):
		return
	var row: RankCell = binding.get_cell() as RankCell
	if row != null:
		row.set_like_display(true, heart_count, liked_by_player, target_id, true)


func _on_ranking_changed() -> void:
	if _anim_active:
		return
	_rebuild()


func _update_countdown() -> void:
	_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())


func _reveal_encourage_bar() -> void:
	if not _show_encourage:
		_encourage_bar.visible = false
		return
	_encourage_bar.visible = true
	if _encourage_anim != null and _encourage_anim.has_animation(&"Appear"):
		_encourage_anim.play(&"Appear")


func _reach_rank_limit() -> int:
	return maxi(3, ABTestManager.podium_per_game.podium_rank_limit())


const _PODIUM_TEXT_KEYS := {
	1: "RANK_PODIUM_1ST",
	2: "RANK_PODIUM_2ND",
	3: "RANK_PODIUM_3RD",
}


func _apply_encouragement(enc: Dictionary) -> void:
	var kind: String = str(enc.get("kind", "none"))
	if kind == "reach":
		var r: int = clampi(int(enc.get("rank", 1)), 1, _PODIUM_COUNT)
		_progress_label.text = tr(_PODIUM_TEXT_KEYS.get(r, "RANK_PODIUM_3RD")).replace(
			"{0}", str(r)
		)
		_show_encourage = true
	elif kind == "climb":
		var n: int = int(enc.get("advance", 0))
		_progress_label.text = tr("RANK_ENCOURAGE_CLIMB_%d" % (randi() % 4 + 1)) % n
		_show_encourage = true
	else:
		_show_encourage = false


func _play_win_anim(advance: int) -> void:
	var gen: int = _ff_gen
	_trace_add("_play_win_anim 起编排 快照=%d adv=%d" % [gen, advance])
	_ff_done = false

	_ff_ready = false
	_rise_ctx = {}
	_c_time_shift = 0.0

	if _anim != null and _anim.has_animation(&"Appear"):
		_anim.play(&"Appear")

	if _win_increment <= 0 and advance <= 0:
		_list_adapter.intro_pending = false
		if _streak_bar != null and is_instance_valid(_streak_bar) and _streak_bar.visible:
			_streak_bar.snap_to(_streak_tier_index(_streak_multiplier))
		_finish_and_enable_scroll()
		_anim_active = false
		_reveal_encourage_bar()
		return
	_anim_active = true

	if _clock_tween != null and _clock_tween.is_valid():
		_clock_tween.kill()
	_clock_tween = create_tween()
	_clock_tween.tween_interval(_CLOCK_SPAN)

	_play_streak_tier_anim(gen)

	var on_podium_no_row: bool = (
		_my_on_podium and (_my_cell == null or not is_instance_valid(_my_cell))
	)
	if on_podium_no_row and _my_rank_info != null:
		_play_podium_count(clampi(_my_old_rank - 1, 0, _PODIUM_COUNT - 1))

	_start_streak_fish_show(gen, on_podium_no_row and _my_rank_info != null)

	await get_tree().process_frame
	if gen != _ff_gen:
		_trace_add("编排作废@process_frame 快照=%d(未复位 active)" % gen)
		return
	if not is_showing():
		_anim_active = false
		return
	_center_scroll_on_player()

	_rise_ctx = {}
	if _my_on_podium:
		if not _my_old_on_podium and _my_cell != null and is_instance_valid(_my_cell):
			_rise_ctx = _prepare_flyout()
	elif advance > 0 and _my_new_rank >= 4:
		_rise_ctx = _prepare_rise(advance)

	_list_adapter.intro_pending = false
	var queue: Array[Dictionary] = []
	var current: Array = _list_adapter.bindings.values()
	var clip: Rect2 = _virtual_list.get_clip_rect_in_viewport()
	for binding: VirtualListBinding in current:
		if not _virtual_list.is_binding_current(binding):
			continue
		var rect: Rect2 = _virtual_list.get_item_rect_in_viewport(binding.index)
		rect.position.y += _list_state.get_row_offset(binding.index)
		if binding.data.is_self and _list_state.player_replaced:
			continue
		if rect.intersects(clip):
			queue.append({"cy": rect.position.y, "binding": binding})
		else:
			binding.get_cell().show_static()
	if is_instance_valid(_my_cell):
		queue.append({"cy": _my_cell.global_position.y, "binding": null})
	queue.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool: return float(left.cy) < float(right.cy)
	)
	var show_generation: int = _show_generation
	for ordinal in queue.size():
		var binding: VirtualListBinding = queue[ordinal].binding
		var tween: Tween = create_tween()
		tween.tween_interval(_APPEAR3_START + _APPEAR3_INTERVAL * ordinal)
		var key: Variant = binding if binding != null else &"copy"
		_intro_tweens[key] = tween
		tween.tween_callback(
			func() -> void:
				_intro_tweens.erase(key)
				if show_generation != _show_generation or gen != _ff_gen or not is_showing():
					return
				if binding != null:
					if _virtual_list.is_binding_current(binding):
						binding.get_cell().play_intro(&"Appear3")
				elif is_instance_valid(_my_cell):
					_my_cell.play_intro(&"Appear3")
		)

	await get_tree().create_timer(_COUNT_START).timeout
	if gen != _ff_gen:
		_trace_add("编排作废@COUNT_START 快照=%d(未复位 active)★" % gen)
		return
	if not is_showing():
		_anim_active = false
		return

	_trace_add("闸门开 _ff_ready=true 快照=%d(此后卡住则在位移段之后)" % gen)
	_ff_ready = true
	if _my_cell != null and is_instance_valid(_my_cell):
		var _g1: bool = _is_settle_flight_active()
		if _g1:
			_set_fake_unclipped(true)

			if _is_heart_bg_flight():
				_my_cell.set_fish_icon_above_z(_SETTLE_FISH_Z)
			var cell := _my_cell
			var to_provider := func() -> Vector2:
				return cell.get_fish_icon_global() if is_instance_valid(cell) else Vector2.ZERO
			var arrive := func() -> void:
				if is_instance_valid(cell):
					cell.emit_fish_collect_burst()
			_play_settle_collect_flight(to_provider, arrive, _SETTLE_TRAIL_Z)
		else:
			_set_fake_unclipped(true)
			_my_cell.play_count()
		if _win_increment > 0 and _my_rank_info != null:
			var roll_dur: float = score_roll_dur
			if _streak_fly_active:
				await _await_abs(float(_streak_timeline.get("first_arrive", 0.0)))
				roll_dur = _streak_roll_dur()
			else:
				var roll_delay: float = (
					(_SETTLE_FLY_DELAY + _SETTLE_FLY_DUR) if _g1 else _SCORE_ROLL_DELAY
				)
				await get_tree().create_timer(roll_delay).timeout
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return
			var new_score: int = _my_rank_info.score
			await _roll_score(_my_cell, maxi(0, new_score - _win_increment), new_score, roll_dur)
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return

	_set_fake_unclipped(_my_on_podium or _my_new_rank == _PODIUM_COUNT + 1)

	if _my_on_podium and advance > 0:
		if _my_old_on_podium:
			if _streak_fly_active:
				_c_time_shift = maxf(
					0.0,
					(
						float(_streak_timeline.get("last_arrive", 0.0))
						- (_C_ROLL_DELAY + score_roll_dur)
					)
				)
			await _run_podium_swap()
		else:
			await _run_podium_promotion(_rise_ctx)
	elif on_podium_no_row:
		var wait_end: float = _C_COUNT_LEN
		if _streak_fly_active:
			wait_end = maxf(wait_end, float(_streak_timeline.get("last_arrive", 0.0)))
		elif _is_settle_flight_active():
			wait_end = maxf(
				wait_end, _COUNT_START + _SETTLE_FLY_DELAY + _SETTLE_FLY_DUR + score_roll_dur
			)
		await _await_abs(wait_end)
	elif not _rise_ctx.is_empty() and _my_cell != null and is_instance_valid(_my_cell):
		await _run_list_rise(_rise_ctx)
	elif _my_cell != null and is_instance_valid(_my_cell):
		await _my_cell.await_collection_finished()
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return
		await _my_cell.play_lift()
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return

		_ff_ready = false
		await _my_cell.play_drop()
		VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return
		if finish_hold_dur > 0.0:
			await get_tree().create_timer(finish_hold_dur).timeout
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return

	if gen != _ff_gen:
		return
	if not is_showing():
		_anim_active = false
		return
	_anim_active = false
	_reveal_encourage_bar()
	_finish_and_enable_scroll()


## 普通列表内上升时驱动布局状态与玩家副本，虚拟行按相同进度更新偏移。
func _run_list_rise(ctx: Dictionary) -> void:
	var gen: int = _ff_gen
	_my_cell.play_arrow(arrow_fade_dur)
	await _my_cell.play_lift()
	if gen != _ff_gen:
		return
	if not is_showing():
		return
	_my_cell.play_rise_idle()
	await get_tree().create_timer(lift_hold_dur).timeout
	if gen != _ff_gen:
		return
	if not is_showing():
		return
	await _run_rise(ctx)
	if gen != _ff_gen:
		return
	if not is_showing():
		return
	await get_tree().create_timer(settle_hold_dur).timeout
	if gen != _ff_gen:
		return
	if not is_showing():
		return

	get_tree().create_timer(_RISE_DOWN_SWAP_DELAY).timeout.connect(
		_swap_rise_rows_to_final.bind(ctx)
	)

	_ff_ready = false
	await _my_cell.play_drop()
	VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)
	if gen != _ff_gen:
		return
	if not is_showing():
		return
	await get_tree().create_timer(_ARROW_HIDE_DELAY).timeout
	if is_instance_valid(_my_cell):
		_my_cell.hide_arrow()
	if finish_hold_dur > 0.0:
		await get_tree().create_timer(finish_hold_dur).timeout


## 玩家进入前三时衔接列表飞出与领奖台落位；两种容器的坐标和生命周期分别处理。
func _run_podium_promotion(ctx: Dictionary) -> void:
	var gen: int = _ff_gen
	var slot: int = (_my_rank_info.rank - 1) if _my_rank_info != null else 0
	slot = clampi(slot, 0, _PODIUM_COUNT - 1)

	if not ctx.is_empty() and _my_cell != null and is_instance_valid(_my_cell):
		_my_cell.play_arrow(arrow_fade_dur)
		await _my_cell.play_lift()
		if gen != _ff_gen:
			return
		if not is_showing():
			return
		_my_cell.play_rise_idle()
		await get_tree().create_timer(lift_hold_dur).timeout
		if gen != _ff_gen:
			return
		if not is_showing():
			return

		if int(ctx.get("slots", 0)) > 0:
			await _run_flyout_rise(ctx)
			if gen != _ff_gen:
				return
			if not is_showing():
				return

		_set_fake_unclipped(false)

		_run_flyout(ctx)
		await (
			get_tree()
			. create_timer(
				(
					flyout_handoff_at_px
					/ _flyout_speed(int(ctx.get("slots", 0)), float(ctx.get("row_h", 0.0)))
				)
			)
			. timeout
		)
		if gen != _ff_gen:
			return
		if not is_showing():
			return
		_fake_active = false

	await _run_podium_swap_from_below(slot)


func _run_podium_swap_from_below(slot: int) -> void:
	var gen: int = _ff_gen

	_ff_ready = false

	if (
		_podium_anim != null
		and _podium_anim.is_playing()
		and _podium_anim.current_animation == "Appear"
	):
		await _podium_anim.animation_finished
		if gen != _ff_gen or not is_showing():
			return

	await _drop_podium_occupant(slot)
	if gen != _ff_gen or not is_showing():
		return

	await _run_podium_swap_from_below_no_drop(slot)


func _run_podium_swap_from_below_no_drop(slot: int) -> void:
	var gen: int = _ff_gen
	_set_podium_slot(slot, _my_rank_info)
	_fly_podium_winner(slot)
	await get_tree().create_timer(_PODIUM_SWEEP_DELAY).timeout
	if gen != _ff_gen or not is_showing():
		return
	_play_podium_sweep(slot + 1)
	await get_tree().create_timer(_PODIUM_OTHERS_SWAP_DELAY).timeout
	if gen != _ff_gen or not is_showing():
		return

	var final_top: Array = _final_top_infos()
	for i in range(_PODIUM_COUNT):
		if i == slot:
			continue
		_set_podium_slot(i, final_top[i] if i < final_top.size() else null)
	VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)

	var remain: float = (
		_PODIUM_FLY_DUR
		+ _PODIUM_SETTLE_DUR
		+ _PODIUM_BOUNCE_DUR
		- _PODIUM_SWEEP_DELAY
		- _PODIUM_OTHERS_SWAP_DELAY
	)
	if remain > 0.0:
		await get_tree().create_timer(remain).timeout


func _run_podium_swap() -> void:
	var gen: int = _ff_gen
	if _my_rank_info == null or _podium == null:
		return
	var slot_new: int = clampi(_my_rank_info.rank - 1, 0, _PODIUM_COUNT - 1)
	var slot_old: int = clampi(_my_old_rank - 1, 0, _PODIUM_COUNT - 1)

	if (
		_podium_anim != null
		and _podium_anim.is_playing()
		and _podium_anim.current_animation == "Appear"
	):
		await _podium_anim.animation_finished
		if gen != _ff_gen or not is_showing():
			return
	var mount_old: Control = _podium.get_avatar_mount(slot_old + 1)
	var mount_new: Control = _podium.get_avatar_mount(slot_new + 1)
	if mount_old == null or mount_new == null or slot_old == slot_new:
		return

	await _await_abs(_C_LIFT_START + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return

	_ff_ready = false
	var lift: Tween = _track_podium_tween(create_tween())
	lift.tween_property(
		mount_old, "scale", Vector2(_C_LIFT_SCALE, _C_LIFT_SCALE), _C_LIFT_DOWN - _C_LIFT_START
	)
	lift.tween_property(mount_old, "scale", Vector2.ONE, _C_FLY_START - _C_LIFT_DOWN)

	await _await_abs(_C_FLY_START + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return

	var start_center: Vector2 = mount_old.global_position + mount_old.size * 0.5
	var target_center: Vector2 = mount_new.global_position + mount_new.size * 0.5
	var mid_center: Vector2 = target_center - Vector2(0.0, _C_MID_ABOVE)

	var base_scale: float = (
		(mount_new.size.x / 185.0) if mount_new.size.x > 0.0 else _PODIUM_AVATAR_SCALE
	)

	var flyer = create_child(_AVATAR_CELL, {})
	_mount(flyer, _celebrate_layer)
	flyer.apply_player_info(_my_rank_info.player_info)
	(flyer as Control).scale = Vector2(base_scale, base_scale)

	(flyer as Control).global_position = start_center - (flyer as Control).size * base_scale * 0.5
	(flyer as Control).z_index = _C_FLYER_Z
	_c_flyer = flyer
	_c_fly_segment(
		flyer,
		start_center,
		mid_center,
		_C_BEZ_FLY_X,
		_C_BEZ_FLY_Y,
		1.0,
		_C_SCALE_MID,
		_C_BEZ_SCALE_FLY,
		base_scale,
		_C_MID_AT - _C_FLY_START
	)

	await _await_abs(_C_SWEEP_AT + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return
	_play_podium_sweep(slot_new + 1)

	await _await_abs(_C_MID_AT + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return
	_swap_podium_final(slot_new)

	_c_fly_segment(
		flyer,
		mid_center,
		target_center,
		_C_BEZ_LINEAR,
		_C_BEZ_DROP_Y,
		_C_SCALE_MID,
		_C_SCALE_LAND,
		_C_BEZ_SCALE_MID,
		base_scale,
		_C_LAND_AT - _C_MID_AT
	)

	await _await_abs(_C_LAND_AT + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return
	VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)
	_c_fly_segment(
		flyer,
		target_center,
		target_center,
		_C_BEZ_LINEAR,
		_C_BEZ_LINEAR,
		_C_SCALE_LAND,
		1.0,
		_C_BEZ_SCALE_LAND,
		base_scale,
		_C_END_AT - _C_LAND_AT
	)

	await _await_abs(_C_END_AT + _c_time_shift)
	if gen != _ff_gen or not is_showing():
		return
	var landed: Control = _podium.get_avatar_mount(slot_new + 1)
	if landed != null:
		landed.visible = true

	if _c_fly_tween != null and _c_fly_tween.is_valid():
		_c_fly_tween.kill()
	_c_fly_tween = null
	if _c_flyer != null and is_instance_valid(_c_flyer):
		destroy_child(_c_flyer)
	_c_flyer = null


func _ff_run_podium_swap_change(slot_old: int, slot_new: int) -> void:
	var gen: int = _ff_gen
	if _my_rank_info == null or _podium == null or slot_old == slot_new:
		return
	var mount_old: Control = _podium.get_avatar_mount(slot_old + 1)
	var mount_new: Control = _podium.get_avatar_mount(slot_new + 1)
	if mount_old == null or mount_new == null:
		return

	var lift: Tween = _track_podium_tween(create_tween())
	lift.tween_property(
		mount_old, "scale", Vector2(_C_LIFT_SCALE, _C_LIFT_SCALE), _C_LIFT_DOWN - _C_LIFT_START
	)
	lift.tween_property(mount_old, "scale", Vector2.ONE, _C_FLY_START - _C_LIFT_DOWN)
	await get_tree().create_timer(_C_FLY_START - _C_LIFT_START).timeout
	if gen != _ff_gen or not is_showing():
		return

	var start_center: Vector2 = mount_old.global_position + mount_old.size * 0.5
	var target_center: Vector2 = mount_new.global_position + mount_new.size * 0.5
	var mid_center: Vector2 = target_center - Vector2(0.0, _C_MID_ABOVE)
	var base_scale: float = (
		(mount_new.size.x / 185.0) if mount_new.size.x > 0.0 else _PODIUM_AVATAR_SCALE
	)
	var flyer = create_child(_AVATAR_CELL, {})
	_mount(flyer, _celebrate_layer)
	flyer.apply_player_info(_my_rank_info.player_info)
	(flyer as Control).scale = Vector2(base_scale, base_scale)
	(flyer as Control).global_position = start_center - (flyer as Control).size * base_scale * 0.5
	(flyer as Control).z_index = _C_FLYER_Z
	_c_flyer = flyer
	_c_fly_segment(
		flyer,
		start_center,
		mid_center,
		_C_BEZ_FLY_X,
		_C_BEZ_FLY_Y,
		1.0,
		_C_SCALE_MID,
		_C_BEZ_SCALE_FLY,
		base_scale,
		_C_MID_AT - _C_FLY_START
	)

	await get_tree().create_timer(_C_SWEEP_AT - _C_FLY_START).timeout
	if gen != _ff_gen or not is_showing():
		return
	_play_podium_sweep(slot_new + 1)

	await get_tree().create_timer(_C_MID_AT - _C_SWEEP_AT).timeout
	if gen != _ff_gen or not is_showing():
		return
	_swap_podium_final(slot_new)
	_c_fly_segment(
		flyer,
		mid_center,
		target_center,
		_C_BEZ_LINEAR,
		_C_BEZ_DROP_Y,
		_C_SCALE_MID,
		_C_SCALE_LAND,
		_C_BEZ_SCALE_MID,
		base_scale,
		_C_LAND_AT - _C_MID_AT
	)

	await get_tree().create_timer(_C_LAND_AT - _C_MID_AT).timeout
	if gen != _ff_gen or not is_showing():
		return
	VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)
	_c_fly_segment(
		flyer,
		target_center,
		target_center,
		_C_BEZ_LINEAR,
		_C_BEZ_LINEAR,
		_C_SCALE_LAND,
		1.0,
		_C_BEZ_SCALE_LAND,
		base_scale,
		_C_END_AT - _C_LAND_AT
	)

	await get_tree().create_timer(_C_END_AT - _C_LAND_AT).timeout
	if gen != _ff_gen or not is_showing():
		return
	var landed: Control = _podium.get_avatar_mount(slot_new + 1)
	if landed != null:
		landed.visible = true
	if _c_fly_tween != null and _c_fly_tween.is_valid():
		_c_fly_tween.kill()
	_c_fly_tween = null
	if _c_flyer != null and is_instance_valid(_c_flyer):
		destroy_child(_c_flyer)
	_c_flyer = null


func _swap_podium_final(slot_new: int) -> void:
	var final_top: Array = _final_top_infos()
	for i in range(_PODIUM_COUNT):
		_set_podium_slot(i, final_top[i] if i < final_top.size() else null)
		var m: Control = _podium.get_avatar_mount(i + 1)
		if m != null:
			m.visible = i != slot_new


func _c_fly_segment(
	node: Control,
	from_pos: Vector2,
	to_pos: Vector2,
	bez_x: Vector4,
	bez_y: Vector4,
	from_scale: float,
	to_scale: float,
	bez_s: Vector4,
	base_scale: float,
	dur: float
) -> void:
	if node == null or not is_instance_valid(node) or dur <= 0.0:
		return
	var setter := func(p: float) -> void:
		if not is_instance_valid(node):
			return
		var s: float = base_scale * (from_scale + (to_scale - from_scale) * _bezier_ease(p, bez_s))
		node.scale = Vector2(s, s)
		var center: Vector2 = Vector2(
			from_pos.x + (to_pos.x - from_pos.x) * _bezier_ease(p, bez_x),
			from_pos.y + (to_pos.y - from_pos.y) * _bezier_ease(p, bez_y)
		)
		node.global_position = center - node.size * s * 0.5

	if _c_fly_tween != null and _c_fly_tween.is_valid():
		_c_fly_tween.kill()
	_c_fly_tween = create_tween()
	_c_fly_tween.tween_method(setter, 0.0, 1.0, dur)


func _final_top_infos() -> Array:
	var live: Array = RankActivityManager.get_rank_infos()
	if _my_rank_info != null and live.size() >= _PODIUM_COUNT:
		var me: RankInfo = _find_self(live)
		if me != null and me.rank == _my_rank_info.rank:
			return live.slice(0, _PODIUM_COUNT)

	var out: Array = _podium_old_infos.duplicate()
	out.insert(clampi(_my_rank_info.rank - 1, 0, out.size()), _my_rank_info)
	return out.slice(0, _PODIUM_COUNT)


func _track_podium_tween(tw: Tween) -> Tween:
	_podium_tweens.append(tw)
	return tw


func _kill_podium_tweens() -> void:
	for tw: Tween in _podium_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_podium_tweens.clear()


func _drop_podium_occupant(slot: int) -> void:
	var mount: Control = _podium.get_avatar_mount(slot + 1)
	if mount == null:
		return
	mount.set_meta(&"podium_rest_y", mount.position.y)

	mount.z_index = 1
	var t: Tween = _track_podium_tween(create_tween().set_parallel(true))
	(
		t
		. tween_property(mount, "position:y", _PODIUM_AVATAR_DOWN_Y, _PODIUM_DROP_DUR)
		. set_ease(Tween.EASE_IN)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		t
		. tween_property(mount, "scale", Vector2.ZERO, _PODIUM_DROP_DUR)
		. set_ease(Tween.EASE_IN)
		. set_trans(Tween.TRANS_QUAD)
	)
	await t.finished


func _fly_podium_winner(slot: int) -> void:
	var mount: Control = _podium.get_avatar_mount(slot + 1)
	if mount == null:
		return
	var rest_y: float = float(mount.get_meta(&"podium_rest_y", 0.0))
	mount.z_index = 1
	mount.position.y = _PODIUM_AVATAR_DOWN_Y
	mount.scale = Vector2(_PODIUM_SCALE_LOW, _PODIUM_SCALE_LOW)
	var t: Tween = _track_podium_tween(create_tween())

	(
		t
		. tween_property(mount, "position:y", rest_y - _PODIUM_OVERSHOOT, _PODIUM_FLY_DUR)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_CUBIC)
	)
	(
		t
		. tween_property(mount, "position:y", rest_y, _PODIUM_SETTLE_DUR)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_SINE)
	)

	var s: Tween = _track_podium_tween(create_tween())
	(
		s
		. tween_property(
			mount, "scale", Vector2(_PODIUM_SCALE_HIGH, _PODIUM_SCALE_HIGH), _PODIUM_FLY_DUR
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_CUBIC)
	)
	(
		s
		. tween_property(
			mount, "scale", Vector2(_PODIUM_SCALE_DIP, _PODIUM_SCALE_DIP), _PODIUM_SETTLE_DUR
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		s
		. tween_property(
			mount, "scale", Vector2(_PODIUM_SCALE_END, _PODIUM_SCALE_END), _PODIUM_BOUNCE_DUR
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)

	s.tween_callback(
		func() -> void:
			if is_instance_valid(mount):
				mount.z_index = 0
	)


func _ff_drop_and_snap_mount(slot: int) -> void:
	var mount: Control = _podium.get_avatar_mount(slot + 1)
	if mount == null:
		return
	mount.set_meta(&"podium_rest_y", mount.position.y)
	mount.z_index = 1
	var mount_rest_y: float = mount.position.y

	var old_av: Control = null
	if slot >= 0 and slot < _podium_avatars.size():
		old_av = _podium_avatars[slot] as Control

		_podium_avatars[slot] = null
	if old_av != null and is_instance_valid(old_av):
		var old_global: Vector2 = old_av.global_position
		var old_scale: Vector2 = old_av.scale
		mount.remove_child(old_av)
		_celebrate_layer.add_child(old_av)

		old_av.global_position = old_global
		old_av.scale = old_scale

		var target_y: float = old_global.y + (_PODIUM_AVATAR_DOWN_Y - mount_rest_y)
		var drop_t: Tween = create_tween().set_parallel(true)
		(
			drop_t
			. tween_property(old_av, "global_position:y", target_y, _PODIUM_DROP_DUR)
			. set_ease(Tween.EASE_IN)
			. set_trans(Tween.TRANS_QUAD)
		)
		(
			drop_t
			. tween_property(old_av, "scale", Vector2.ZERO, _PODIUM_DROP_DUR)
			. set_ease(Tween.EASE_IN)
			. set_trans(Tween.TRANS_QUAD)
		)

		drop_t.chain().tween_callback(
			func() -> void:
				if is_instance_valid(old_av):
					destroy_child(old_av)
		)

	mount.position.y = _PODIUM_AVATAR_DOWN_Y
	mount.scale = Vector2.ZERO


func _play_podium_sweep(rank_no: int) -> void:
	if _podium_anim == null:
		return
	var nm: StringName = StringName("Sweep%d" % rank_no)
	if not _podium_anim.has_animation(nm):
		push_error("rank_activity_change_page_v2: top3_podium 缺 %s 动画，台座高光无表现" % nm)
		return
	if _anim != null and _anim.is_playing() and _podium_anim.current_animation != &"Appear":
		_anim.clear_caches()
	_podium_anim.play(nm)


func _align_celebrate_clip() -> void:
	if _celebrate_clip == null or _scroll == null or _scroll.size.y <= 0.0:
		return

	_celebrate_clip.clip_contents = true
	_celebrate_clip.anchor_bottom = _celebrate_clip.anchor_top
	_celebrate_clip.global_position = Vector2(
		_celebrate_clip.global_position.x, _scroll.global_position.y
	)

	_celebrate_clip.offset_bottom = _celebrate_clip.offset_top + _scroll.size.y


func _set_fake_unclipped(on: bool) -> void:
	if _my_cell == null or not is_instance_valid(_my_cell):
		return
	var target: Control = _celebrate_layer if on else _celebrate_clip
	if _my_cell.get_parent() != target:
		var gp: Vector2 = _my_cell.global_position
		_mount(_my_cell, target)
		_my_cell.global_position = gp

		if _streak_fly_active:
			_redraw_reparented_particles(_my_cell)
	_my_cell.set_effect_z(_C_FLYER_Z if on else 0)


func _redraw_reparented_particles(root: Node) -> void:
	var particles: Array[Node] = root.find_children("*", "CPUParticles2D", true, false)
	for node in particles:
		var particle := node as CPUParticles2D
		if particle.emitting:
			particle.notification(Node.NOTIFICATION_INTERNAL_PROCESS)


func _prepare_flyout() -> Dictionary:
	var context: Dictionary = _list_state.prepare_flyout(
		_my_old_rank, domino_drop_ratio, flyout_dist_px
	)
	if context.is_empty():
		return {}
	_flyout_start_y = _list_state.player_local_y
	context.viewport_h = _scroll.size.y
	_follow_player()
	_virtual_list.refresh_presentation()
	_position_player_copy()
	return context


func _flyout_rise_dur(slots: int) -> float:
	return clampf(
		minf(flyout_rise_per_place * float(slots), rise_base_dur + rise_per_place * float(slots)),
		flyout_rise_min_dur,
		rise_max_dur
	)


func _flyout_speed(slots: int, row_h: float) -> float:
	var h: float = maxf(1.0, row_h)
	if slots <= 0:
		return h / maxf(0.01, flyout_rise_per_place)
	return (float(slots) * h) / maxf(0.01, _flyout_rise_dur(slots))


func _run_flyout_rise(ctx: Dictionary) -> void:
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = create_tween()
	_rise_tween.tween_method(_flyout_rise_tick, 0.0, 1.0, _flyout_rise_dur(int(ctx.slots)))
	await _rise_tween.finished


func _flyout_rise_tick(progress: float) -> void:
	var passed: int = _list_state.tick(progress)
	_follow_player()
	_virtual_list.refresh_presentation()
	_position_player_copy()
	_update_flyout_rank(_my_cell, passed)


func _run_flyout(ctx: Dictionary) -> void:
	var cell: Control = _my_cell
	var start_y: float = cell.global_position.y if is_instance_valid(cell) else 0.0
	var drive_domino: bool = int(ctx.get("slots", 0)) == 0
	var row_h: float = float(ctx.get("row_h", 0.0))
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = create_tween()
	var cb := func(progress: float) -> void:
		if is_instance_valid(cell):
			cell.global_position.y = start_y - flyout_dist_px * progress
		if drive_domino:
			_update_flyout_rank(cell, _list_state.tick(progress))
			_virtual_list.refresh_presentation()

	_rise_tween.tween_method(
		cb, 0.0, 1.0, flyout_dist_px / _flyout_speed(int(ctx.get("slots", 0)), row_h)
	)
	await _rise_tween.finished
	if drive_domino:
		_list_state.tick(1.0)
		_virtual_list.refresh_presentation()

	if is_instance_valid(cell):
		cell.hide_arrow()
		cell.visible = false


func _update_flyout_rank(cell: Control, passed: int) -> void:
	if _my_rank_info == null or not is_instance_valid(cell):
		return
	var shown: int = clampi(_my_old_rank - passed, _PODIUM_COUNT + 1, _my_old_rank)
	if _was_unranked and passed == 0:
		shown = 0
	if shown != _last_shown_rank:
		_last_shown_rank = shown
		cell.set_rank_number(shown)


func _scroll_top_floor() -> float:
	return _LIST_PAD_TOP - _virtual_list.spacing


func _center_scroll_on_player() -> void:
	var local_y: float = maxf(0.0, (_my_new_rank - 4) * 200.0) if not _my_on_podium else 0.0
	_virtual_list.scroll_to_offset(
		maxf(_scroll_top_floor(), local_y + _LIST_PAD_TOP + 90.0 - _scroll.size.y / 2.0)
	)
	_position_player_copy()


func _prepare_rise(advance: int) -> Dictionary:
	var context: Dictionary = _list_state.prepare_rise(advance, domino_drop_ratio)
	if context.is_empty():
		return {}
	context.viewport_h = _scroll.size.y
	_follow_player()
	_virtual_list.refresh_presentation()
	_position_player_copy()
	return context


func _run_rise(ctx: Dictionary) -> void:
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	var duration: float = clampf(
		rise_base_dur + rise_per_place * int(ctx.advance), rise_min_dur, rise_max_dur
	)
	_rise_tween = create_tween()
	(
		_rise_tween
		. tween_method(_on_rise_tick, 0.0, 1.0, duration)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_SINE)
	)

	var running: Tween = _rise_tween
	while running.is_running():
		await get_tree().process_frame


func _on_rise_tick(progress: float) -> void:
	var passed: int = _list_state.tick(progress)
	_follow_player()
	_virtual_list.refresh_presentation()
	_position_player_copy()
	if _my_rank_info != null and is_instance_valid(_my_cell):
		var effective: int = int(_rise_ctx.get("advance", 0))
		var shown_rank: int = clampi(
			_my_new_rank + effective - passed, _my_new_rank, _my_new_rank + effective
		)
		if _was_unranked and passed == 0:
			shown_rank = 0
		_my_cell.set_rank_number(shown_rank)


func _follow_player() -> void:
	_virtual_list.scroll_to_offset(
		maxf(
			_scroll_top_floor(),
			_list_state.player_local_y + _LIST_PAD_TOP + 90.0 - _scroll.size.y / 2.0
		)
	)


func _position_player_copy() -> void:
	if not is_instance_valid(_my_cell) or not _virtual_list.has_item(0):
		return
	var rect: Rect2 = _virtual_list.get_item_rect_in_viewport(0)
	_my_cell.global_position = rect.position + Vector2(0.0, _list_state.player_local_y)


func _swap_rise_rows_to_final(_ctx: Dictionary) -> void:
	if not is_showing():
		return
	_list_state.tick(1.0)
	_virtual_list.refresh_presentation()
	if _my_rank_info != null and is_instance_valid(_my_cell):
		_finalize_rise_row(_my_rank_info, _my_cell)


func _finalize_rise_row(info: RankInfo, cell: RankCell) -> void:
	var pinfo: PlayerInfo = info.player_info
	var shown_rank: int = 0 if (info.is_self() and info.score <= 0) else info.rank
	cell.set_entry(shown_rank, info.is_self(), _display_name(pinfo), info.score)


func _swap_all_rows_to_final() -> void:
	if not is_showing():
		return
	_list_state.tick(1.0)
	_virtual_list.refresh_presentation()
	if _my_rank_info != null and is_instance_valid(_my_cell):
		_update_row_cell(_my_rank_info, _my_cell)


static func _final_refresh_indices_for_rise(
	row_count: int, player_slot: int, advance: int
) -> Array[int]:
	var refresh_indices: Array[int] = []
	if row_count <= 0 or player_slot < 0 or player_slot >= row_count or advance <= 0:
		return refresh_indices
	var old_rank_slot: int = mini(row_count - 1, player_slot + advance)
	for row_index in range(player_slot, old_rank_slot + 1):
		refresh_indices.append(row_index)
	return refresh_indices


func _roll_score(cell: Control, from_v: int, to_v: int, duration: float = -1.0) -> void:
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	var roll_dur: float = score_roll_dur if duration < 0.0 else duration
	cell.set_score(from_v)
	if to_v <= from_v or roll_dur <= 0.0:
		cell.set_score(to_v)
		return
	_score_tween = create_tween()
	(
		_score_tween
		. tween_method(
			func(v: float) -> void: cell.set_score(int(roundf(v))),
			float(from_v),
			float(to_v),
			roll_dur
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	await _score_tween.finished


static func _bezier_ease(t: float, b: Vector4) -> float:
	var tc: float = clampf(t, 0.0, 1.0)
	var lo: float = 0.0
	var hi: float = 1.0
	var u: float = tc
	for _i in 20:
		u = (lo + hi) * 0.5
		var inv: float = 1.0 - u
		var bx: float = 3.0 * u * inv * inv * b.x + 3.0 * u * u * inv * b.z + u * u * u
		if bx < tc:
			lo = u
		else:
			hi = u
	var iv: float = 1.0 - u
	return 3.0 * u * iv * iv * b.y + 3.0 * u * u * iv * b.w + u * u * u


func _await_abs(target_sec: float) -> void:
	if _clock_tween == null or not _clock_tween.is_valid():
		return

	var left: float = target_sec - _clock_tween.get_total_elapsed_time()
	if left > 0.0:
		await get_tree().create_timer(left).timeout


func _play_podium_count(slot: int) -> void:
	if _my_rank_info == null or _podium == null:
		return
	var mount: Control = _podium.get_collection_mount(slot + 1)
	if mount == null:
		push_error("rank_activity_change_page_v2: 台位 %d 无计分挂点，前 3 名计分动画缺失" % [slot + 1])
		return
	var g1: bool = _is_settle_flight_active()
	if g1:
		var r: int = slot + 1

		if _is_heart_bg_flight():
			_podium.set_fish_icon_above_z(r, _SETTLE_FISH_Z)

		_play_settle_collect_flight(
			func() -> Vector2: return _podium.get_fish_icon_global(r),
			func() -> void: _spawn_settle_burst(_podium.get_fish_icon_global(r)),
			_SETTLE_TRAIL_Z,
			_COUNT_START
		)
	else:
		var inst: Control = _c_collections[slot] as Control
		if inst == null or not is_instance_valid(inst):
			inst = _COLLECTION_SCENE.instantiate()
			inst.z_index = 25
			inst.offset_left = _C_COLLECTION_OFFSET.x
			inst.offset_top = _C_COLLECTION_OFFSET.y
			inst.offset_right = _C_COLLECTION_OFFSET.x + _C_COLLECTION_SIZE
			inst.offset_bottom = _C_COLLECTION_OFFSET.y + _C_COLLECTION_SIZE

			for i in range(1, 7):
				var sp := inst.get_node_or_null("Collection%d" % i) as Node2D
				if sp != null:
					sp.scale = Vector2(0.3, 0.3)
			mount.add_child(inst)
			_c_collections[slot] = inst

		var fish_tex: Texture2D = RankCell.collect_fish_texture()
		if fish_tex != null:
			for i in range(1, 7):
				var sp := inst.get_node_or_null("Collection%d" % i) as Sprite2D
				if sp != null:
					sp.texture = fish_tex
		var ap := inst.get_node_or_null("CollectionAppear") as AnimationPlayer
		if ap == null or not ap.has_animation(&"Count2"):
			push_error("rank_activity_change_page_v2: rank_change_collection 缺 Count2 动画")
			return
		SoundManager.play(SoundManager.Kind.RANK_SCORE_COUNT)
		ap.play(&"Count2")
	if _win_increment > 0:
		var to_v: int = _my_rank_info.score
		var from_v: int = maxi(0, to_v - _win_increment)
		_podium.apply(slot + 1, _display_name(_my_rank_info.player_info), from_v)

		var gen_pc: int = _ff_gen

		var roll_delay: float = _C_ROLL_DELAY
		var roll_dur: float = score_roll_dur
		if _streak_fly_active:
			roll_delay = float(_streak_timeline.get("first_arrive", 0.0))
			roll_dur = _streak_roll_dur()
		elif g1:
			roll_delay = _COUNT_START + _SETTLE_FLY_DELAY + _SETTLE_FLY_DUR
		get_tree().create_timer(roll_delay).timeout.connect(
			func() -> void:
				if gen_pc != _ff_gen or not is_showing() or _podium == null:
					return
				_podium.roll_fish(slot + 1, from_v, to_v, roll_dur)
		)


func _play_settle_collect_flight(
	to_provider: Callable, arrive_cb: Callable, trail_z: int, start_delay: float = 0.0
) -> void:
	var gen: int = _ff_gen

	if _streak_fly_active:
		return
	var slots: Array = [_heart_slot1, _heart_slot2, _heart_slot3]
	var n: int = mini(_settle_lives, slots.size())
	for k in range(n):
		var slot: LifeSlot = slots[k] as LifeSlot
		if slot == null or not is_instance_valid(slot):
			continue
		var from: Vector2 = slot.get_global_rect().get_center()
		(
			get_tree()
			. create_timer(start_delay + _SETTLE_FLY_DELAY + _SETTLE_FLY_INTERVAL * k)
			. timeout
			. connect(
				_on_settle_fish_launch.bind(slot, from, to_provider, arrive_cb, trail_z, gen, k)
			)
		)


func _on_settle_fish_launch(
	slot: LifeSlot,
	from: Vector2,
	to_provider: Callable,
	arrive_cb: Callable,
	trail_z: int,
	gen: int,
	order: int = 0
) -> void:
	if not is_showing():
		return

	if gen != _ff_gen:
		return

	var fish_kinds: Array = [
		SoundManager.Kind.RANK_FISH_COLLECT_1,
		SoundManager.Kind.RANK_FISH_COLLECT_2,
		SoundManager.Kind.RANK_FISH_COLLECT_3,
	]
	SoundManager.play(fish_kinds[clampi(order, 0, fish_kinds.size() - 1)])
	if is_instance_valid(slot):
		slot.show_lost(false, true)
	_spawn_settle_flight_trail(from, to_provider.call() as Vector2, arrive_cb, trail_z, gen)


func _spawn_settle_flight_trail(
	from: Vector2, to: Vector2, arrive_cb: Callable, trail_z: int, gen: int
) -> void:
	var trail: Node = _SETTLE_TRAIL_SCENE.instantiate()
	_celebrate_layer.add_child(trail)

	(trail as CanvasItem).z_index = trail_z
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return
	sprite.global_position = from
	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false
	for child: Node in sprite.get_children():
		if child is CPUParticles2D:
			var p := child as CPUParticles2D
			sprite.remove_child(p)
			fly_target.add_child(p)
			p.visible = true
			p.emitting = true
	_settle_trails.append(trail)
	var tw: Tween = trail.create_tween()
	var mover := func(t: float) -> void:
		if not (is_instance_valid(fly_target) and is_instance_valid(sprite)):
			return
		var ex: float = ComboFeedbackView._cubic_bezier_ease(
			t, _SETTLE_BEZIER_X.x, _SETTLE_BEZIER_X.y, _SETTLE_BEZIER_X.z, _SETTLE_BEZIER_X.w
		)
		var ey: float = ComboFeedbackView._cubic_bezier_ease(
			t, _SETTLE_BEZIER_Y.x, _SETTLE_BEZIER_Y.y, _SETTLE_BEZIER_Y.z, _SETTLE_BEZIER_Y.w
		)
		var arc_x: float = _SETTLE_TRAIL_ARC_X * sin(PI * ex)
		fly_target.global_position = Vector2(
			lerpf(from.x, to.x, ex) + arc_x, lerpf(from.y, to.y, ey)
		)
		sprite.notify_target_moved()
	tw.tween_method(mover, 0.0, 1.0, _SETTLE_FLY_DUR)
	tw.tween_callback(_on_settle_trail_arrived.bind(trail, arrive_cb, gen))


func _on_settle_trail_arrived(trail: Node, arrive_cb: Callable, gen: int) -> void:
	if gen != _ff_gen:
		_settle_trails.erase(trail)
		if is_instance_valid(trail):
			trail.queue_free()
		return
	if arrive_cb.is_valid():
		arrive_cb.call()
	if not is_instance_valid(trail):
		return
	for p: Node in trail.find_children("*", "CPUParticles2D", true, false):
		var particle := p as CPUParticles2D
		if particle != null:
			particle.emitting = false
	var linger: Tween = trail.create_tween()
	linger.tween_interval(_SETTLE_TRAIL_FADE)
	linger.tween_callback(_free_settle_trail.bind(trail))


func _free_settle_trail(trail: Node) -> void:
	_settle_trails.erase(trail)
	if is_instance_valid(trail):
		trail.queue_free()


func _reset_settle_trails() -> void:
	for trail in _settle_trails:
		if is_instance_valid(trail):
			trail.queue_free()
	_settle_trails.clear()


func _abort_settle_flight() -> void:
	_reset_settle_trails()

	if _streak_bar != null and is_instance_valid(_streak_bar) and _streak_bar.visible:
		_streak_bar.snap_to(_streak_tier_index(_streak_multiplier))
	if _streak_fly_active:
		return
	var slots: Array = [_heart_slot1, _heart_slot2, _heart_slot3]
	var n: int = mini(_settle_lives, slots.size())
	for k in range(n):
		var slot: LifeSlot = slots[k] as LifeSlot
		if slot != null and is_instance_valid(slot):
			slot.show_lost(false, true)


func _spawn_settle_burst(pos: Vector2, before_start: Callable = Callable()) -> void:
	var burst: Node = _SETTLE_BURST_SCENE.instantiate()
	_celebrate_layer.add_child(burst)

	(burst as CanvasItem).z_index = _SETTLE_FISH_Z + 5
	if burst is Node2D:
		(burst as Node2D).global_position = pos
		(burst as Node2D).scale = Vector2(_SETTLE_BURST_PODIUM_SCALE, _SETTLE_BURST_PODIUM_SCALE)
	elif burst is Control:
		(burst as Control).global_position = pos
		(burst as Control).scale = Vector2(_SETTLE_BURST_PODIUM_SCALE, _SETTLE_BURST_PODIUM_SCALE)
	if before_start.is_valid():
		before_start.call(burst)
	_play_burst_then_free(burst)


func _spawn_podium_fish_burst(rank: int, before_start: Callable) -> void:
	var icon: Control = _podium.get_fish_icon(rank)
	if icon == null:
		return
	var burst := _SETTLE_BURST_SCENE.instantiate() as Control
	icon.add_child(burst)
	burst.show_behind_parent = true
	burst.position = icon.size * 0.5

	var icon_scale: float = maxf(icon.get_global_transform().get_scale().x, 0.001)
	burst.scale = Vector2.ONE * (_SETTLE_BURST_PODIUM_SCALE / icon_scale)
	if before_start.is_valid():
		before_start.call(burst)
	_play_burst_then_free(burst)


func _play_burst_then_free(burst: Node) -> void:
	var max_life: float = 0.0
	for p: Node in burst.find_children("*", "CPUParticles2D", true, false):
		var particle := p as CPUParticles2D
		if particle != null:
			particle.restart()
			particle.emitting = true
			max_life = maxf(max_life, particle.lifetime)
	var tw: Tween = burst.create_tween()
	tw.tween_interval(max_life + 0.3)
	tw.tween_callback(burst.queue_free)


func _visible_cell_indices() -> Array[int]:
	var result: Array[int] = []
	var current: Array = _list_adapter.bindings.values()
	var clip: Rect2 = _virtual_list.get_clip_rect_in_viewport()
	for binding: VirtualListBinding in current:
		if _virtual_list.is_binding_current(binding):
			var rect: Rect2 = _virtual_list.get_item_rect_in_viewport(binding.index)
			rect.position.y += _list_state.get_row_offset(binding.index)
			if rect.intersects(clip):
				result.append(binding.index)
	return result


func _display_name(pinfo: PlayerInfo) -> String:
	return pinfo.nickname if pinfo != null else ""


func _find_self(infos: Array) -> RankInfo:
	for info: RankInfo in infos:
		if info != null and info.is_self():
			return info
	return null


func _mount(cell: Control, parent: Control) -> void:
	var cur: Node = cell.get_parent()
	if cur == parent:
		return
	if cur != null:
		cur.remove_child(cell)
	parent.add_child(cell)


func _clear_cells() -> void:
	_cancel_row_intros()
	if is_instance_valid(_my_cell):
		destroy_child(_my_cell)
	_my_cell = null
	_fake_active = false
	for index in _podium_avatars.size():
		if is_instance_valid(_podium_avatars[index]):
			destroy_child(_podium_avatars[index])
		_podium_avatars[index] = null


func cancel_row_intro(binding: VirtualListBinding) -> void:
	var tween: Tween = _intro_tweens.get(binding)
	if tween != null and tween.is_valid():
		tween.kill()
	_intro_tweens.erase(binding)


func _cancel_row_intros() -> void:
	var tweens: Array = _intro_tweens.values()
	for tween: Tween in tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_intro_tweens.clear()


func _sync_fake_cell() -> void:
	if _fake_active:
		_position_player_copy()


## 销毁被飞出演出引用的行之前先停止 Tween，避免回调访问失效节点。
func _kill_flyout_tween_before_cell_destroy() -> void:
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = null


func _finish_and_enable_scroll() -> void:
	_cancel_row_intros()
	_list_adapter.intro_pending = false
	_list_state.finish()
	_virtual_list.refresh_presentation()
	var current: Array = _list_adapter.bindings.values()
	for binding: VirtualListBinding in current:
		if _virtual_list.is_binding_current(binding):
			binding.get_cell().show_static()
	if is_instance_valid(_my_cell):
		_kill_flyout_tween_before_cell_destroy()
		destroy_child(_my_cell)
	_my_cell = null
	_fake_active = false
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_reveal_tap_to_continue()


func _reveal_tap_to_continue() -> void:
	if not is_instance_valid(_tap) or _tap.visible:
		return
	_tap.visible = true
	_tap.modulate.a = 0.0
	create_tween().tween_property(_tap, "modulate:a", 1.0, _TAP_FADE_IN_DUR)


func _format_hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func on_escape() -> bool:
	_dismiss()
	return true


func _on_tap_pressed() -> void:
	_dismiss()


func _input(event: InputEvent) -> void:
	if not is_showing() or not _anim_active or _ff_done or not _ff_ready:
		return
	if not ABTestManager.leaderboard_anim.is_fast_forward_enabled():
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return
	get_viewport().set_input_as_handled()
	_fast_forward()


func _on_mask_input(event: InputEvent) -> void:
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if is_press:
		_dismiss()
		get_viewport().set_input_as_handled()


func get_dlg_name() -> String:
	return Tracker.Dlg.CHALLENGE_RANK


func _dismiss() -> void:
	if _anim_active:
		if _ff_ready and not _ff_done and ABTestManager.leaderboard_anim.is_fast_forward_enabled():
			_fast_forward()
		return
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)
	UIManager.hide_ui(UiName.RANK_ACTIVITY_CHANGE_V2)


## 跳过剩余演出并同步到最终视觉状态，使继续操作不依赖每条 Tween 自然结束。
func _fast_forward() -> void:
	if _ff_done:
		return
	_ff_done = true
	_trace_add("_fast_forward 改编号 %d→%d(玩家点了跳过)" % [_ff_gen, _ff_gen + 1])
	_ff_gen += 1

	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = null
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = null
	if _c_fly_tween != null and _c_fly_tween.is_valid():
		_c_fly_tween.kill()
	_c_fly_tween = null

	_abort_settle_flight()

	_kill_podium_tweens()

	_cancel_row_intros()
	var current: Array = _list_adapter.bindings.values()
	for binding: VirtualListBinding in current:
		if _virtual_list.is_binding_current(binding):
			binding.get_cell().snap_idle()
	_swap_all_rows_to_final()

	_center_scroll_on_player()

	if _my_on_podium:
		var slot_new: int = clampi(_my_new_rank - 1, 0, _PODIUM_COUNT - 1)
		var slot_old: int = clampi(_my_old_rank - 1, 0, _PODIUM_COUNT - 1)

		if (
			_podium_anim != null
			and _podium_anim.is_playing()
			and _podium_anim.current_animation == "Appear"
		):
			var appear_anim: Animation = _podium_anim.get_animation(&"Appear")
			if appear_anim != null:
				var remain_appear: float = (
					appear_anim.length - _podium_anim.current_animation_position
				)
				if remain_appear > 0.0:
					_podium_anim.advance(remain_appear + 0.001)

		for i in range(_PODIUM_COUNT):
			var mount: Control = _podium.get_avatar_mount(i + 1)
			if mount == null:
				continue
			mount.z_index = 0
			mount.visible = true
			mount.scale = Vector2.ONE

			if mount.has_meta(&"podium_rest_y"):
				mount.position.y = float(mount.get_meta(&"podium_rest_y"))

		if _c_flyer != null and is_instance_valid(_c_flyer):
			destroy_child(_c_flyer)
		_c_flyer = null

		for coll: Node in _c_collections:
			if coll == null or not is_instance_valid(coll):
				continue
			var cap: AnimationPlayer = coll.get_node_or_null("CollectionAppear") as AnimationPlayer
			if cap != null and cap.has_animation(&"RESET"):
				cap.play(&"RESET")
				cap.advance(0.0)
				cap.pause()

		if _podium != null:
			for r in range(_PODIUM_COUNT):
				_podium.finalize_fish_roll(r + 1)

		var branch_b: bool = (
			_my_on_podium
			and _advance > 0
			and not _my_old_on_podium
			and is_instance_valid(_my_cell)
			and not _rise_ctx.is_empty()
		)
		if not branch_b:
			if is_instance_valid(_my_cell):
				_kill_flyout_tween_before_cell_destroy()
				destroy_child(_my_cell)
				_my_cell = null
		else:
			_my_cell.finish_collection_now()
			_my_cell.hide_arrow()
			_my_cell.snap_idle()

			if _win_increment > 0 and _my_rank_info != null:
				_my_cell.set_score(_my_rank_info.score)

			_my_cell.set_rank_number(_PODIUM_COUNT + 1)
			_last_shown_rank = _PODIUM_COUNT + 1
		if _advance <= 0:
			if (
				_podium != null
				and _my_rank_info != null
				and _my_new_rank >= 1
				and _my_new_rank <= _PODIUM_COUNT
			):
				_podium.apply(
					_my_new_rank, _display_name(_my_rank_info.player_info), _my_rank_info.score
				)
		elif _my_old_on_podium:
			if (
				_podium != null
				and _my_rank_info != null
				and _my_old_rank >= 1
				and _my_old_rank <= _PODIUM_COUNT
			):
				_podium.apply(
					_my_old_rank, _display_name(_my_rank_info.player_info), _my_rank_info.score
				)
			await _ff_run_podium_swap_change(slot_old, slot_new)
		else:
			var flyout_valid: bool = is_instance_valid(_my_cell) and not _rise_ctx.is_empty()
			if flyout_valid:
				_virtual_list.scroll_to_offset(_scroll_top_floor())

				_my_cell.global_position.y = (
					_scroll.global_position.y + _LIST_PAD_TOP - float(_scroll.scroll_vertical)
				)
				var slots_ff: int = int(_rise_ctx.get("slots", 0))
				if slots_ff >= 1:
					_list_state.tick(1.0)
					_virtual_list.refresh_presentation()

			_ff_drop_and_snap_mount(slot_new)
			if flyout_valid:
				_set_fake_unclipped(false)
				_run_flyout(_rise_ctx)
			await _run_podium_swap_from_below_no_drop(slot_new)

			if _rise_tween != null and _rise_tween.is_running():
				await _rise_tween.finished
		if not is_showing():
			_anim_active = false
			return
	else:
		if is_instance_valid(_my_cell):
			_my_cell.finish_collection_now()
			_my_cell.hide_arrow()
			_my_cell.snap_rise_down_start()

			if _win_increment > 0 and _my_rank_info != null:
				_my_cell.set_score(_my_rank_info.score)

			_set_fake_unclipped(_my_new_rank == _PODIUM_COUNT + 1)
			await _my_cell.play_drop()
			VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)

			if finish_hold_dur > 0.0:
				await get_tree().create_timer(finish_hold_dur).timeout
		if not is_showing():
			_anim_active = false
			return

	_anim_active = false
	_reveal_encourage_bar()
	_finish_and_enable_scroll()
