## 排行榜变动页的旧版展示路径；使用滚动列表演示收集、分数上涨、名次提升和点赞弹幕。

extends UIFrameWindow

const _RANK_CELL: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")
const _RANK_BULLET: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_bullet.tscn")

@onready var _scroll: ScrollContainer = $ListGroup/RankCellMask/ScrollList
@onready var _rank_margin: MarginContainer = $ListGroup/RankCellMask/ScrollList/RankMargin
@onready var _row_list: VBoxContainer = $ListGroup/RankCellMask/ScrollList/RankMargin/RowList
var _row_culler := ScrollRowCuller.new()

@onready var _celebrate_layer: Control = $PlayerCelebrate
@onready var _countdown_label: Label = $Countdown/CountdownText
@onready var _progress_label: RichTextLabel = $EncourageTopBar/ProgressLabel
@onready var _encourage_bar: Control = $EncourageTopBar
@onready var _encourage_anim: AnimationPlayer = $EncourageTopBar/AnimationPlayer
@onready var _mask: ColorRect = $Mask
@onready var _title_anim: AnimationPlayer = $AnimationPlayer
@onready var _tap: Button = $TapToContinue

@onready var _heart_bg: Control = $HeartBg

@onready var _heart_slot1: LifeSlot = $HeartBg/LifeSlot
@onready var _heart_slot2: LifeSlot = $HeartBg/LifeSlot2
@onready var _heart_slot3: LifeSlot = $HeartBg/LifeSlot3
@onready var _bullets_area: Control = $BulletsArea

const _APPEAR3_START: float = 0.2
const _APPEAR3_INTERVAL: float = 0.0667
const _COUNT_START: float = 0.7333
const _SCORE_ROLL_DELAY: float = 1.0
const _ARROW_HIDE_DELAY: float = 0.03

const _RISE_DOWN_SWAP_DELAY: float = 0.23
const _TAP_FADE_IN_DUR: float = 0.25

const _LIST_VPAD: float = 200.0

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

const _SETTLE_TRAIL_SCENE: PackedScene = preload("res://assets/prefab/effect_score_trail.tscn")
const _SETTLE_TRAIL_Z: int = 2
const _SETTLE_FISH_ICON_Z: int = 3
const _SETTLE_BEZIER_X: Vector4 = Vector4(0.125, 0.0, 0.875, 1.0)
const _SETTLE_BEZIER_Y: Vector4 = Vector4(0.0, 0.141343, 0.7, 1.0)
const _SETTLE_FLY_DELAY: float = 0.2
const _SETTLE_FLY_INTERVAL: float = 0.083
const _SETTLE_FLY_DUR: float = 0.4
const _SETTLE_TRAIL_FADE: float = 0.3
const _SETTLE_TRAIL_ARC_X: float = 50.0
var _settle_lives: int = 0

var _is_golden_fish: bool = false

var _suppress_settle_flight: bool = false
var _settle_trails: Array = []
var _barrage_bullets: Array[RankBullet] = []
var _barrage_generation: int = 0

var _list_cells: Array = []
var _row_infos: Array = []
var _my_rank_info: RankInfo = null
var _my_cell: Control = null
var _my_row_cell: Control = null

var _fake_active: bool = false
var _win_increment: int = 0
var _advance: int = 0
var _show_encourage: bool = false
var _anim_active: bool = false
var _rise_tween: Tween = null
var _score_tween: Tween = null
var _last_shown_rank: int = -1

var _was_unranked: bool = false

var _ff_gen: int = 0

var _ff_done: bool = false

var _ff_ready: bool = false

var _rise_ctx: Dictionary = {}


func on_create() -> void:
	add_update_listener(_sync_fake_cell)

	_rank_margin.add_theme_constant_override(&"margin_top", int(_LIST_VPAD))
	_rank_margin.add_theme_constant_override(&"margin_bottom", int(_LIST_VPAD))
	connect_managed(_bullets_area.resized, _align_barrage_lanes)
	_warm_first_cell()


func _warm_first_cell() -> void:
	var w: Control = _RANK_CELL.instantiate()
	add_child(w)

	w.set_collection_visual()
	remove_child(w)
	w.free()


func _is_settle_flight_active() -> bool:
	if _suppress_settle_flight:
		return false
	if _is_golden_fish:
		return false
	return ABTestManager.leaderboard_collection_levelwin.is_settle_page_flight()


## 读取本次增分和升名次信息，建立用于旧版滚动列表的演出状态。
func on_show(params: Dictionary = {}) -> void:
	_row_culler.attach(_scroll, _row_list)

	RankActivityManager.set_online_window_sec(RankOnlineHelper.window_sec_from_ab())

	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.scroll_vertical = 0
	_fake_active = false
	connect_managed(_mask.gui_input, _on_mask_input)

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
	var _is_g1: bool = _is_settle_flight_active()
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

	var advance: int = _advance

	if mock_infos.is_empty():
		_apply_encouragement(
			RankActivityManager.consume_progress_encouragement(_reach_rank_limit(), advance)
		)
	else:
		_apply_encouragement({"kind": "climb", "advance": advance})

	_encourage_bar.visible = false

	_tap.visible = false
	_play_barrages(params.get("rank_like_result", {}) as Dictionary)
	_play_win_anim(advance)


func on_hide() -> void:
	_row_culler.detach()
	_clear_barrages()
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = null
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = null
	_anim_active = false
	_reset_settle_trails()

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
	if _encourage_bar != null:
		_encourage_bar.visible = false
	if _title_anim != null and _title_anim.has_animation(&"Appear"):
		AnimUtil.play(_title_anim, &"Appear")
		_title_anim.pause()


func _rebuild(override_infos: Array = [], show_now: bool = true) -> void:
	_clear_cells()
	_my_cell = null
	_row_infos.clear()
	var is_mock: bool = not override_infos.is_empty()
	var infos: Array = override_infos if is_mock else RankActivityManager.get_rank_infos()
	_my_rank_info = _find_self(infos)

	_was_unranked = _my_rank_info != null and (_my_rank_info.score - _win_increment) <= 0
	for info: RankInfo in infos:
		var cell = create_child(_RANK_CELL, {})
		_mount(cell, _row_list)
		cell.connect(&"like_heart_pressed", _on_like_heart_pressed)
		cell.apply_score_icon()
		cell.set_show_chest(false)
		_update_row_cell(info, cell)
		var is_self: bool = info != null and info.is_self()
		var old_score: int = (
			maxi(0, info.score - _win_increment) if (is_self and _win_increment > 0) else info.score
		)

		var old_rank: int
		if is_self and not is_mock:
			var rank_from_score: int = RankActivityManager.get_rank_for_score(old_score)
			if rank_from_score >= 1:
				old_rank = clampi(rank_from_score, info.rank, infos.size())
				_advance = maxi(0, old_rank - info.rank)
			else:
				old_rank = info.rank
		elif is_self and _advance > 0:
			old_rank = mini(info.rank + _advance, infos.size())
		else:
			old_rank = info.rank
		var will_animate: bool = _advance > 0 or _win_increment > 0

		var start_rank_anim: int = 0 if _was_unranked else old_rank

		var start_rank_static: int = 0 if (is_self and info.score <= 0) else old_rank
		if is_self and not show_now and will_animate:
			_my_row_cell = cell
			cell.set_entry(start_rank_anim, true, _display_name(info.player_info), old_score)
			var fake = create_child(_RANK_CELL, {})
			_mount(fake, _celebrate_layer)
			fake.connect(&"like_heart_pressed", _on_like_heart_pressed)
			fake.apply_score_icon()
			fake.set_show_chest(false)
			_update_row_cell(info, fake)
			fake.set_collection_visual()
			fake.set_entry(start_rank_anim, true, _display_name(info.player_info), old_score)
			_my_cell = fake
			_fake_active = true
		else:
			if show_now:
				cell.show_static()
			if is_self:
				_my_cell = cell
				_my_row_cell = cell
				cell.set_collection_visual()
				cell.set_entry(start_rank_static, true, _display_name(info.player_info), old_score)
		_list_cells.append(cell)
		_row_infos.append(info)
	_update_countdown()


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
		var like_state: Dictionary = RankActivityManager.get_player_self_like_state()
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
	var like_state: Dictionary = RankActivityManager.get_robot_like_state(robot_id)
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
	var heart_count: int = int(like_state.get("heart_count", 0))
	var liked_by_player: bool = bool(like_state.get("liked_by_player", false))
	for cell in _list_cells:
		if str(cell.get_meta(&"rank_like_robot_id", "")) == target_id:
			cell.set_like_display(true, heart_count, liked_by_player, target_id, true)


func _on_ranking_changed() -> void:
	if _anim_active:
		return
	var infos: Array = RankActivityManager.get_rank_infos()
	_my_rank_info = _find_self(infos)
	if infos.size() != _list_cells.size():
		_rebuild()
		return
	for i in _list_cells.size():
		_update_row_cell(infos[i], _list_cells[i])


func _update_countdown() -> void:
	_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())


func _reveal_encourage_bar() -> void:
	if not _show_encourage:
		_encourage_bar.visible = false
		return
	_encourage_bar.visible = true
	if _encourage_anim != null and _encourage_anim.has_animation(&"Appear"):
		_encourage_anim.play(&"Appear")


const _PODIUM_TEXT_KEYS := {
	1: "RANK_PODIUM_1ST",
	2: "RANK_PODIUM_2ND",
	3: "RANK_PODIUM_3RD",
}


func _reach_rank_limit() -> int:
	return maxi(3, ABTestManager.podium_per_game.podium_rank_limit())


func _apply_encouragement(enc: Dictionary) -> void:
	var kind: String = str(enc.get("kind", "none"))
	if kind == "reach":
		var raw: int = int(enc.get("rank", 1))
		if ABTestManager.podium_per_game.has_per_game_podium():
			var r: int = clampi(raw, 1, _PODIUM_TEXT_KEYS.size())
			var key: String = _PODIUM_TEXT_KEYS.get(r, "RANK_PODIUM_3RD")
			_progress_label.text = tr(key).replace("{0}", str(r))
		else:
			var r3: int = clampi(raw, 1, 3)
			_progress_label.text = tr("RANK_ENCOURAGE_REACH_%d" % r3)
		_show_encourage = true
	elif kind == "climb":
		var n: int = int(enc.get("advance", 0))
		_progress_label.text = tr("RANK_ENCOURAGE_CLIMB_%d" % (randi() % 4 + 1)) % n
		_show_encourage = true
	else:
		_show_encourage = false


func _play_win_anim(advance: int) -> void:
	var gen: int = _ff_gen
	_ff_done = false

	_ff_ready = false
	_rise_ctx = {}

	if _title_anim != null and _title_anim.has_animation(&"Appear"):
		_title_anim.play(&"Appear")

		var appear_anim: Animation = _title_anim.get_animation(&"Appear")
		var appear_len: float = appear_anim.length if appear_anim != null else 0.0
		if appear_len > 0.0:
			get_tree().create_timer(appear_len).timeout.connect(
				func() -> void:
					if gen == _ff_gen:
						_ff_ready = true
			)
		else:
			_ff_ready = true
	else:
		_ff_ready = true
	if _win_increment <= 0 and advance <= 0:
		for c in _list_cells:
			if is_instance_valid(c):
				c.show_static()
		_finish_and_enable_scroll()
		_anim_active = false
		_reveal_encourage_bar()
		return
	_anim_active = true

	await get_tree().process_frame
	if gen != _ff_gen:
		return
	if not is_showing():
		_anim_active = false
		return

	_center_scroll_on_player()

	_rise_ctx = _prepare_rise(advance) if advance > 0 else {}

	if not _rise_ctx.is_empty() and _my_rank_info != null:
		var pn: int = _my_rank_info.rank
		var pold: int = mini(pn + _advance, _list_cells.size())
		for i in _list_cells.size():
			var bc: Control = _list_cells[i] as Control
			if bc == _my_row_cell or not is_instance_valid(bc):
				continue
			var inf: RankInfo = _row_infos[i]
			if inf.rank > pn and inf.rank <= pold:
				bc.set_entry(inf.rank - 1, false, _display_name(inf.player_info), inf.score)

	var visible_idx: Array[int] = _visible_cell_indices()
	for i in _list_cells.size():
		if _list_cells[i] == _my_row_cell:
			continue
		if not visible_idx.has(i) and is_instance_valid(_list_cells[i]):
			(_list_cells[i] as Control).show_static()

	for k in visible_idx.size():
		var idx: int = visible_idx[k]

		var c: Control = _my_cell if _list_cells[idx] == _my_row_cell else _list_cells[idx]
		var d: float = _APPEAR3_START + _APPEAR3_INTERVAL * k
		get_tree().create_timer(d).timeout.connect(
			func() -> void:
				if gen != _ff_gen:
					return
				if is_instance_valid(c):
					c.play_intro(&"Appear3")
		)

	await get_tree().create_timer(_COUNT_START).timeout
	if gen != _ff_gen:
		return
	if not is_showing():
		_anim_active = false
		return
	if _my_cell != null and is_instance_valid(_my_cell):
		if _is_settle_flight_active():
			_play_settle_collect_flight()
		else:
			_my_cell.play_count()

		if _win_increment > 0 and _my_rank_info != null:
			var roll_delay: float = _SCORE_ROLL_DELAY
			if _is_settle_flight_active():
				roll_delay = _SETTLE_FLY_DELAY + _SETTLE_FLY_DUR
			await get_tree().create_timer(roll_delay).timeout
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return
			var new_score: int = _my_rank_info.score
			await _roll_score(_my_cell, maxi(0, new_score - _win_increment), new_score)
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return

	if _rise_ctx.is_empty() and _my_cell != null and is_instance_valid(_my_cell):
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

	if not _rise_ctx.is_empty() and _my_cell != null and is_instance_valid(_my_cell):
		_my_cell.play_arrow(arrow_fade_dur)
		await _my_cell.play_lift()
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return
		_my_cell.play_rise_idle()
		await get_tree().create_timer(lift_hold_dur).timeout
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return

		await _run_rise(_rise_ctx)
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return
		await get_tree().create_timer(settle_hold_dur).timeout
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return

		get_tree().create_timer(_RISE_DOWN_SWAP_DELAY).timeout.connect(_swap_all_rows_to_final)

		_ff_ready = false
		await _my_cell.play_drop()
		VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)
		if gen != _ff_gen:
			return
		if not is_showing():
			_anim_active = false
			return
		await get_tree().create_timer(_ARROW_HIDE_DELAY).timeout
		if is_instance_valid(_my_cell):
			_my_cell.hide_arrow()

		if finish_hold_dur > 0.0:
			await get_tree().create_timer(finish_hold_dur).timeout
			if gen != _ff_gen:
				return
			if not is_showing():
				_anim_active = false
				return

	_anim_active = false
	_reveal_encourage_bar()
	_finish_and_enable_scroll()


func _swap_all_rows_to_final() -> void:
	if not is_showing():
		return
	for i in _list_cells.size():
		if not is_instance_valid(_list_cells[i]):
			continue
		_update_row_cell(_row_infos[i], _list_cells[i])

		if (
			_list_cells[i] == _my_row_cell
			and is_instance_valid(_my_cell)
			and _my_cell != _my_row_cell
		):
			_update_row_cell(_row_infos[i], _my_cell)


func _roll_score(cell: Control, from_v: int, to_v: int) -> void:
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	cell.set_score(from_v)
	if to_v <= from_v or score_roll_dur <= 0.0:
		cell.set_score(to_v)
		return
	_score_tween = create_tween()
	(
		_score_tween
		. tween_method(
			func(v: float) -> void: cell.set_score(int(roundf(v))),
			float(from_v),
			float(to_v),
			score_roll_dur
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	await _score_tween.finished


func _play_settle_collect_flight() -> void:
	if _my_cell == null or not is_instance_valid(_my_cell):
		return
	_my_cell.set_fish_icon_above_z(_SETTLE_FISH_ICON_Z)

	var gen: int = _ff_gen
	var slots: Array = [_heart_slot1, _heart_slot2, _heart_slot3]
	var n: int = mini(_settle_lives, slots.size())
	for k in range(n):
		var slot: LifeSlot = slots[k] as LifeSlot
		if slot == null or not is_instance_valid(slot):
			continue
		var from: Vector2 = slot.get_global_rect().get_center()
		get_tree().create_timer(_SETTLE_FLY_DELAY + _SETTLE_FLY_INTERVAL * k).timeout.connect(
			_on_settle_fish_launch.bind(slot, from, gen, k)
		)


func _on_settle_fish_launch(slot: LifeSlot, from: Vector2, gen: int, order: int = 0) -> void:
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
	if _my_cell == null or not is_instance_valid(_my_cell):
		return
	_spawn_settle_flight_trail(from, _my_cell.get_fish_icon_global(), gen)


func _spawn_settle_flight_trail(from: Vector2, to: Vector2, gen: int) -> void:
	var trail: Node = _SETTLE_TRAIL_SCENE.instantiate()
	_celebrate_layer.add_child(trail)

	(trail as CanvasItem).z_index = _SETTLE_TRAIL_Z
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
	tw.tween_callback(_on_settle_trail_arrived.bind(trail, gen))


func _on_settle_trail_arrived(trail: Node, gen: int) -> void:
	if gen != _ff_gen:
		_settle_trails.erase(trail)
		if is_instance_valid(trail):
			trail.queue_free()
		return
	if _my_cell != null and is_instance_valid(_my_cell):
		_my_cell.emit_fish_collect_burst()
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
	for trail: Node in _settle_trails:
		if is_instance_valid(trail):
			trail.queue_free()
	_settle_trails.clear()


func _abort_settle_flight() -> void:
	_reset_settle_trails()
	var slots: Array = [_heart_slot1, _heart_slot2, _heart_slot3]
	var n: int = mini(_settle_lives, slots.size())
	for k in range(n):
		var slot: LifeSlot = slots[k] as LifeSlot
		if slot != null and is_instance_valid(slot):
			slot.show_lost(false, true)


func _center_scroll_on_player() -> void:
	if _my_row_cell == null or not is_instance_valid(_my_row_cell):
		return
	var cell_h: float = (_my_row_cell as Control).size.y
	var viewport_h: float = _scroll.size.y

	var center_scroll: float = (
		(_my_row_cell as Control).position.y + _LIST_VPAD + cell_h / 2.0 - viewport_h / 2.0
	)
	_scroll.scroll_vertical = int(maxf(0.0, center_scroll))


func _prepare_rise(advance: int) -> Dictionary:
	if _my_rank_info == null or advance <= 0:
		return {}
	var new_rank: int = _my_rank_info.rank
	var list_children: Array[Node] = _row_list.get_children()
	if list_children.is_empty() or new_rank < 1 or new_rank > list_children.size():
		return {}

	var old_rank: int = mini(new_rank + advance, list_children.size())
	advance = old_rank - new_rank
	if advance <= 0:
		return {}

	var cell_h: float = (list_children[0] as Control).size.y
	var sep: float = float(_row_list.get_theme_constant("separation"))
	var row_h: float = cell_h + sep

	var p_slot: int = new_rank - 1
	var player_cell: Control = list_children[p_slot] as Control
	var player_base_y: float = player_cell.position.y

	var displaced: Array = []
	var item_p: float = 1.0 / float(advance)
	var drop_p: float = item_p * maxf(0.01, domino_drop_ratio)
	var p_cursor: float = 0.0
	for i in range(p_slot + advance, p_slot, -1):
		if i < 0 or i >= list_children.size():
			continue
		var c: Control = list_children[i] as Control
		var inf: RankInfo = _row_infos[i]

		displaced.append(
			{
				"cell": c,
				"base_y": c.position.y,
				"start_p": p_cursor,
				"end_p": minf(1.0, p_cursor + drop_p),
				"info": inf,
				"final_rank": inf.rank,
				"shown": inf.rank - 1
			}
		)
		c.position.y -= row_h
		p_cursor += item_p

	_last_shown_rank = new_rank + advance

	player_cell.position.y = player_base_y + advance * row_h
	player_cell.z_index = 1

	var viewport_h: float = _scroll.size.y
	_scroll.scroll_vertical = int(
		maxf(0.0, (player_base_y + advance * row_h) + _LIST_VPAD + cell_h / 2.0 - viewport_h / 2.0)
	)

	return {
		"player_cell": player_cell,
		"player_base_y": player_base_y,
		"advance": advance,
		"row_h": row_h,
		"cell_h": cell_h,
		"viewport_h": viewport_h,
		"displaced": displaced,
	}


func _run_rise(ctx: Dictionary) -> void:
	var player_cell: Control = ctx["player_cell"]
	var player_base_y: float = ctx["player_base_y"]
	var advance: int = ctx["advance"]
	var row_h: float = ctx["row_h"]
	var cell_h: float = ctx["cell_h"]
	var viewport_h: float = ctx["viewport_h"]
	var displaced: Array = ctx["displaced"]

	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()

	var rise_dur: float = clampf(
		rise_base_dur + rise_per_place * advance, rise_min_dur, rise_max_dur
	)
	_rise_tween = create_tween()

	var tick_cb := _on_rise_tick.bind(
		player_cell, player_base_y, advance, row_h, cell_h, viewport_h, displaced
	)
	_rise_tween.tween_method(tick_cb, 0.0, 1.0, rise_dur).set_ease(Tween.EASE_IN_OUT).set_trans(
		Tween.TRANS_SINE
	)
	await _rise_tween.finished

	if is_instance_valid(player_cell):
		player_cell.position.y = player_base_y
		player_cell.z_index = 0
	for d: Dictionary in displaced:
		if is_instance_valid(d.cell):
			d.cell.position.y = d.base_y
	_row_list.queue_sort()


func _on_rise_tick(
	p: float,
	player_cell: Control,
	player_base_y: float,
	advance: int,
	row_h: float,
	cell_h: float,
	viewport_h: float,
	displaced: Array
) -> void:
	var player_y: float = player_base_y + advance * row_h * (1.0 - p)
	player_cell.position.y = player_y

	_scroll.scroll_vertical = int(
		maxf(0.0, player_y + _LIST_VPAD + cell_h / 2.0 - viewport_h / 2.0)
	)

	var passed: int = 0
	for d: Dictionary in displaced:
		var crossed: bool = p >= d.end_p
		if crossed:
			passed += 1
			d.cell.position.y = d.base_y
		elif p < d.start_p:
			d.cell.position.y = d.base_y - row_h
		else:
			var lp: float = (p - d.start_p) / (d.end_p - d.start_p)
			d.cell.position.y = d.base_y - row_h * (1.0 - lp)
		var want_r: int = int(d.final_rank) if crossed else int(d.final_rank) - 1
		if int(d.shown) != want_r and is_instance_valid(d.cell):
			d.shown = want_r

			d.cell.set_rank_number(want_r)

	if _my_rank_info != null and is_instance_valid(_my_cell):
		var cur_rank: int = clampi(
			(_my_rank_info.rank + advance) - passed,
			_my_rank_info.rank,
			_my_rank_info.rank + advance
		)

		var shown_rank: int = 0 if (_was_unranked and passed == 0) else cur_rank
		if shown_rank != _last_shown_rank:
			_last_shown_rank = shown_rank

			_my_cell.set_rank_number(shown_rank)


func _visible_cell_indices() -> Array[int]:
	var result: Array[int] = []
	if _list_cells.is_empty():
		return result
	var cell_h: float = (_list_cells[0] as Control).size.y
	var top: float = float(_scroll.scroll_vertical)
	var bottom: float = top + _scroll.size.y
	for i in _list_cells.size():
		var c: Control = _list_cells[i] as Control
		if not is_instance_valid(c):
			continue
		var cy: float = c.position.y + _LIST_VPAD
		if cy + cell_h > top and cy < bottom:
			result.append(i)
	result.sort_custom(
		func(a: int, b: int) -> bool:
			return (_list_cells[a] as Control).position.y < (_list_cells[b] as Control).position.y
	)
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
	if is_instance_valid(_my_cell) and _my_cell != _my_row_cell:
		destroy_child(_my_cell)
	_my_cell = null
	_my_row_cell = null
	_fake_active = false
	for c in _list_cells:
		if is_instance_valid(c):
			destroy_child(c)
	_list_cells.clear()


func _sync_fake_cell() -> void:
	if not _fake_active:
		return
	if not (is_instance_valid(_my_cell) and is_instance_valid(_my_row_cell)):
		return
	var sx: float = _row_list.global_position.x

	var sy: float = (
		_scroll.global_position.y
		+ _my_row_cell.position.y
		+ _LIST_VPAD
		- float(_scroll.scroll_vertical)
	)
	_my_cell.global_position = Vector2(sx, sy)


func _finish_and_enable_scroll() -> void:
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	ScrollDragHelper.attach(_scroll, true).elastic_max_overscroll = 0.0
	if _fake_active:
		_fake_active = false

		if is_instance_valid(_my_row_cell) and _my_rank_info != null:
			_update_row_cell(_my_rank_info, _my_row_cell)
			_my_row_cell.show_static()
		if is_instance_valid(_my_cell) and _my_cell != _my_row_cell:
			destroy_child(_my_cell)
		_my_cell = _my_row_cell

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
	UIManager.hide_ui(UiName.RANK_ACTIVITY_CHANGE)


## 停止剩余动画并显示最终结果，随后恢复继续按钮和滚动交互。
func _fast_forward() -> void:
	if _ff_done:
		return
	_ff_done = true

	_ff_gen += 1

	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = null
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = null

	_abort_settle_flight()

	for c in _list_cells:
		if not is_instance_valid(c):
			continue
		if c == _my_row_cell and is_instance_valid(_my_cell) and _my_cell != _my_row_cell:
			continue
		c.snap_idle()

	_swap_all_rows_to_final()

	if not _rise_ctx.is_empty():
		var player_cell: Control = _rise_ctx.get("player_cell")
		var player_base_y: float = float(_rise_ctx.get("player_base_y", 0.0))
		var displaced: Array = _rise_ctx.get("displaced", [])
		if is_instance_valid(player_cell):
			player_cell.position.y = player_base_y
			player_cell.z_index = 0
		for d: Dictionary in displaced:
			if is_instance_valid(d.cell):
				d.cell.position.y = d.base_y
		_row_list.queue_sort()

	_center_scroll_on_player()

	if is_instance_valid(_my_cell):
		_my_cell.finish_collection_now()
		_my_cell.hide_arrow()
		_my_cell.snap_rise_down_start()

		if _win_increment > 0 and _my_rank_info != null:
			_my_cell.set_score(_my_rank_info.score)
		await _my_cell.play_drop()
		VibrateManager.play_at(VibrateManager.Pos.RANK_CHANGE_DROP)

		if finish_hold_dur > 0.0:
			await get_tree().create_timer(finish_hold_dur).timeout
		if not is_showing():
			_anim_active = false
			return

	if not is_showing():
		_anim_active = false
		return
	_anim_active = false
	_reveal_encourage_bar()
	_finish_and_enable_scroll()
