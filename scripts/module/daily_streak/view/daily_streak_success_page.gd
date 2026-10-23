## 打卡成功演出页：在基础签到页之上编排点亮、震动、加数和奖励展示的时间顺序。
extends StreakPage

const _PLAY_EFFECT_PARAM: String = "play_effect"
const _LIGHT_UP_START_DELAY_SEC: float = 1.0
const _LIGHT_UP_SLOT_DELAY_SEC: float = 1.1
const _MESSAGE_START_SEC: float = 1.0
const _MESSAGE_FADE_DURATION_SEC: float = 1.0 / 6.0
const _WOOL_SWING_ANIMATION: StringName = &"WoolSign_shake"

@onready
var _return_tomorrow_label: Label = $StreakContent/StreakPanel/ReturnTomorrowKeepYourStreakTxt
@onready var _streak_content: Control = $StreakContent

var _message_tween: Tween = null
var _effect_clock: Tween = null
var _effect_revive: Dictionary = {}
var _effect_pending_uid: int = -1
var _can_close: bool = false
var _effect_generation: int = 0
var _play_light_up: bool = false
var _waiting_for_first_click: bool = false


func on_show(params: Dictionary = {}) -> void:
	_effect_generation += 1
	_stop_effect_clock()
	_stop_message_fade()
	_return_tomorrow_label.modulate.a = 0.0
	_can_close = false

	var play_effect: bool = bool(params.get(_PLAY_EFFECT_PARAM, false))
	_effect_revive = StreakManager.get_revive_anim().duplicate(true) if play_effect else {}
	_effect_pending_uid = StreakManager.get_pending_show_uid() if play_effect else -1
	if _effect_pending_uid > 0:
		UIManager.warm_pool(UiName.AWARD)
	_play_light_up = (
		play_effect
		and (
			not _effect_revive.is_empty()
			or StreakManager.get_display_streak() == 1
			or _new_checkin_index() >= 0
		)
	)
	_waiting_for_first_click = (
		_play_light_up
		and _effect_revive.is_empty()
		and int(params.get(_PARAM_STATE, DisplayState.MAIN)) == DisplayState.LIT
	)
	var requested_state: int = DisplayState.MAIN
	if _play_light_up:
		requested_state = DisplayState.LIT
	_set_continue_enabled(false)
	super.on_show({"state": requested_state})

	if not _play_light_up:
		_play_message_fade()
		_unlock_after_enter(_effect_generation)


func on_hide() -> void:
	_effect_generation += 1
	_stop_effect_clock()
	_stop_message_fade()
	_set_continue_enabled(false)
	_play_light_up = false
	_waiting_for_first_click = false
	_day_icon.reset_icon()
	_anim.stop()
	super.on_hide()


func on_escape() -> bool:
	if _can_close:
		_on_back_pressed()
	return true


func get_scr_name() -> String:
	return "" if _waiting_for_first_click else Tracker.Scr.GAME_STREAK


func _input(event: InputEvent) -> void:
	if not _waiting_for_first_click or not _consume_lit_click(event):
		return
	_waiting_for_first_click = false
	_tap_hint_label.visible = false
	_return_tomorrow_label.visible = true
	_start_checkin_effect()
	Tracker.track_scr_show(Tracker.Scr.GAME_STREAK)


func _refresh_visibility() -> void:
	super._refresh_visibility()
	_back_btn.visible = true
	_claim_btn.visible = true
	_go_to_play_btn.visible = false
	_best_streak_group.visible = false
	_tap_hint_label.visible = _waiting_for_first_click
	_return_tomorrow_label.visible = not _waiting_for_first_click


func _refresh_data() -> void:
	super._refresh_data()
	_show_settled_number()


func _refresh_slots() -> void:
	super._refresh_slots()
	if _play_light_up and str(_effect_revive.get("kind", "")) == "backfill":
		_render_week_on(_slots, _week_pos(int(_effect_revive.get("pre_cycle", 0))))
		_render_week_on(_slots2, 0)


func _show_settled_number() -> void:
	var display: int = StreakManager.get_display_streak()
	var settled_number: String = str(display)
	var gained: int = int(_effect_revive.get("gained", 1)) if _play_light_up else 0
	_streak_num.text = settled_number
	_num_txt0.text = str(maxi(0, display - gained))
	_num_txt_new.text = settled_number


func _refresh_encourage() -> void:
	_apply_encourage_layout(false)
	_enc_slot.visible = false


func _play_enter_anim(requested_state: int) -> void:
	if _waiting_for_first_click:
		super._play_enter_anim(DisplayState.LIT)
		return
	if not _play_light_up:
		super._play_enter_anim(requested_state)
		return
	_start_checkin_effect()


func _start_checkin_effect() -> void:
	_anim.play(&"RESET")
	_anim.advance(0.0)

	_num_anim.stop(true)
	_day_icon.reset_icon()
	_day_icon.refresh_group(false)
	_lit_consumed = true
	_anim.stop()
	_anim.assigned_animation = &"LightUp_2" if _anim.has_animation(&"LightUp_2") else &"LightUp"
	_anim.seek(0.0, true)

	_streak_content.modulate.a = 1.0
	_effect_clock = create_tween()
	_effect_clock.tween_interval(3600.0)
	_icon_loop_allowed = true
	_day_icon.play_checkin_anim(0.0, _WOOL_SWING_ANIMATION)
	_day_icon.flush_pose()
	_play_swing_vibrate(_effect_generation)
	_light_up_after_delay(_effect_generation)


func _play_swing_vibrate(generation: int) -> void:
	var swing_times: Array[float] = _day_icon.get_checkin_swing_times(_WOOL_SWING_ANIMATION)
	for swing_time: float in swing_times:
		while _is_effect_current(generation):
			var position_sec: float = _day_icon.get_checkin_animation_position(
				_WOOL_SWING_ANIMATION
			)
			if position_sec < 0.0:
				return
			if position_sec >= swing_time:
				break
			await get_tree().process_frame
		if not _is_effect_current(generation):
			return
		VibrateManager.play_at(VibrateManager.Pos.STREAK_SWING)


func _light_up_after_delay(generation: int) -> void:
	await _await_effect_time(_LIGHT_UP_START_DELAY_SEC, generation)
	if _is_effect_current(generation):
		_light_up_to_settle()


func _light_up_to_settle() -> void:
	var animation_name: StringName = (
		&"LightUp_2" if _anim.has_animation(&"LightUp_2") else &"LightUp"
	)
	if animation_name == &"LightUp":
		push_error("DailyStreakSuccessPage: LightUp_2 动画缺失，回落旧 LightUp")
	var light_up_start: float = _effect_clock.get_total_elapsed_time()
	_anim.play(animation_name)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_CHECK_IN)
	_icon_loop_allowed = true
	_apply_state(DisplayState.SETTLE)

	_anim.advance(0.0)
	_day_icon.flush_pose()
	_run_settle_flow(light_up_start + _LIGHT_UP_SLOT_DELAY_SEC)
	_fade_message_at(light_up_start + _MESSAGE_START_SEC, _effect_generation)


## 用演出代际号隔离异步流程，按奖励优先条件编排宝箱与格子点亮，完成后才放开继续。
func _run_settle_flow(slot_delay: float = _SETTLE_SLOT_DELAY) -> void:
	var generation: int = _effect_generation
	var revive: Dictionary = _effect_revive
	var pending_uid: int = _effect_pending_uid
	var checkin_slots: Array[Control] = []

	var checkin_index: int = _new_checkin_index()
	var normal_slot: Control = _slots[checkin_index] if checkin_index >= 0 else null
	var reward_first: bool = pending_uid > 0 and StreakManager.get_pending_show_uid() == pending_uid
	if reward_first:
		await _await_effect_time(slot_delay, generation)
		if not await _await_enter_finished(generation):
			return
		while (
			_is_effect_current(generation)
			and _day_icon.get_checkin_animation_position(_WOOL_SWING_ANIMATION) >= 0.0
		):
			await get_tree().process_frame
		if not await _present_effect_reward(pending_uid, generation):
			return
		slot_delay = _effect_clock.get_total_elapsed_time()
	if str(revive.get("kind", "")) == "backfill":
		await _run_backfill_settle_guarded(revive, slot_delay, generation, checkin_slots)
	else:
		await _run_normal_settle_guarded(normal_slot, slot_delay, generation, checkin_slots)
	await _await_checkins_finished(checkin_slots, generation)
	if not await _await_enter_finished(generation):
		return
	if not reward_first and not await _present_effect_reward(pending_uid, generation):
		return
	_set_continue_enabled(true)
	_stop_effect_clock()


func _present_effect_reward(pending_uid: int, generation: int) -> bool:
	if not _is_effect_current(generation):
		return false
	if pending_uid > 0 and StreakManager.get_pending_show_uid() == pending_uid:
		StreakManager.claim_reward(false)
		if not _is_effect_current(generation):
			return false
		_consume_effect_pending(pending_uid, generation)
		await _await_reward_closed()
		if not _is_effect_current(generation):
			return false
	else:
		_consume_effect_pending(pending_uid, generation)
	return true


func _is_effect_current(generation: int) -> bool:
	return generation == _effect_generation and is_showing()


func _run_normal_settle_guarded(
	slot: Control, slot_delay: float, generation: int, checkin_slots: Array[Control]
) -> void:
	if slot == null:
		return
	await _await_effect_time(slot_delay, generation)
	if not _is_effect_current(generation):
		return
	_start_checkin(slot, checkin_slots)


func _run_backfill_settle_guarded(
	revive: Dictionary, slot_delay: float, generation: int, checkin_slots: Array[Control]
) -> void:
	var pre_cycle: int = int(revive.get("pre_cycle", 0))
	var gained: int = int(revive.get("gained", 1))
	var base_week: int = floori(float(pre_cycle) / float(CYCLE_LENGTH))
	var this_week: Array[int] = []
	var chest_day: int = -1
	var next_week: Array[int] = []
	for day: int in range(pre_cycle + 1, pre_cycle + gained + 1):
		if day % CYCLE_LENGTH == 0:
			chest_day = day
		elif floori(float(day - 1) / float(CYCLE_LENGTH)) == base_week:
			this_week.append(day)
		else:
			next_week.append(day)
	await _await_effect_time(slot_delay, generation)
	if not _is_effect_current(generation):
		return
	for day: int in this_week:
		_start_checkin(_slots[(day - 1) % CYCLE_LENGTH], checkin_slots)

	if chest_day > 0:
		if not this_week.is_empty():
			await _await_effect_time(slot_delay + _CHECKIN_TO_CHEST, generation)
			if not _is_effect_current(generation):
				return
		var chest_index: int = (chest_day - 1) % CYCLE_LENGTH
		_start_checkin(_slots[chest_index], checkin_slots)

	if not next_week.is_empty():
		await _await_checkins_finished(checkin_slots, generation)
		if not await _await_enter_finished(generation):
			return
		var new_week_start: float = (
			_effect_clock.get_total_elapsed_time() + _CHEST_CHECKIN_TO_NEWWEEK
		)
		await _await_effect_time(new_week_start, generation)
		if not _is_effect_current(generation):
			return
		_render_week_on(_slots2, 0)
		if _anim.has_animation(&"NewWeek"):
			_anim.play(&"NewWeek")
		await _await_effect_time(new_week_start + _NEWWEEK_TO_CHECKIN, generation)
		if not _is_effect_current(generation):
			return
		for day: int in next_week:
			_start_checkin(_slots2[(day - 1) % CYCLE_LENGTH], checkin_slots)


func _start_checkin(slot: Control, checkin_slots: Array[Control]) -> void:
	checkin_slots.append(slot)
	slot.play_checkin(false, true)


func _await_checkins_finished(checkin_slots: Array[Control], generation: int) -> void:
	while _is_effect_current(generation):
		var any_playing: bool = false
		for slot: Control in checkin_slots:
			var player: AnimationPlayer = slot.get_node("AnimationPlayer") as AnimationPlayer
			if player.is_playing() and player.current_animation == &"CheckIn":
				any_playing = true
		if not any_playing:
			return
		await get_tree().process_frame


func _await_effect_time(target_sec: float, generation: int) -> void:
	while (
		_is_effect_current(generation)
		and _effect_clock != null
		and _effect_clock.get_total_elapsed_time() < target_sec
	):
		await get_tree().process_frame


func _consume_effect_pending(pending_uid: int, generation: int) -> void:
	if (
		_is_effect_current(generation)
		and pending_uid >= 0
		and StreakManager.get_pending_show_uid() == pending_uid
	):
		StreakManager.consume_pending_show()


func _unlock_after_enter(generation: int) -> void:
	if await _await_enter_finished(generation):
		_set_continue_enabled(true)


func _await_enter_finished(generation: int) -> bool:
	while _is_effect_current(generation) and _anim.is_playing():
		await get_tree().process_frame
	if not _is_effect_current(generation):
		return false
	if _claim_btn.modulate.a < 0.99:
		push_error("DailyStreakSuccessPage: 入场结束后 Continue 未完成淡入")
		return false
	return true


func _set_continue_enabled(enabled: bool) -> void:
	super._set_continue_enabled(enabled)
	_can_close = enabled
	if _back_btn != null:
		_back_btn.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func _on_back_pressed() -> void:
	if not _can_close or not is_showing():
		return
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(get_ui_name())


func _on_continue_pressed() -> void:
	if not _can_close or not is_showing():
		return
	super._on_continue_pressed()


func _fade_message_at(target_sec: float, generation: int) -> void:
	await _await_effect_time(target_sec, generation)
	if _is_effect_current(generation):
		_play_message_fade()


func _play_message_fade() -> void:
	if not is_showing():
		return
	_message_tween = create_tween()
	_message_tween.tween_property(
		_return_tomorrow_label, "modulate:a", 1.0, _MESSAGE_FADE_DURATION_SEC
	)


func _stop_message_fade() -> void:
	if _message_tween != null and _message_tween.is_running():
		_message_tween.kill()
	_message_tween = null


func _stop_effect_clock() -> void:
	if _effect_clock != null and _effect_clock.is_running():
		_effect_clock.kill()
	_effect_clock = null
