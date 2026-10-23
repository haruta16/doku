## 打卡表现基页：组织未点亮、已点亮和结算状态，按周期串行演出加数与宝箱。
class_name StreakPage
extends UIFrameWindow

signal closed

enum DisplayState { MAIN, LIT, SETTLE } # 展示状态：MAIN 常规 / LIT 首次点亮 / SETTLE 打卡结算

## 星期文案 key，下标 0 = 周日 … 6 = 周六（与 Time.weekday 对齐）
const _WEEKDAY_LABELS: Array[String] = [
	"WEEKDAY_SUN",
	"WEEKDAY_MON",
	"WEEKDAY_TUE",
	"WEEKDAY_WED",
	"WEEKDAY_THU",
	"WEEKDAY_FRI",
	"WEEKDAY_SAT"
]
const _PARAM_STATE: String = "state" # on_show 的参数名：指定要展示的状态
const _SETTLE_SLOT_DELAY: float = 20.0 / 60.0 # 直接以结算态打开时，等多久开始播格子动画（秒）
const _LIT_SLOT_DELAY: float = 62.0 / 60.0 # 从点亮态切结算态时，等多久开始播格子动画（秒，要等 LightUp 播完）
const CYCLE_LENGTH: int = 7

const _PANEL_BASE_TOP: float = -1200.0
const _LAYOUT_PLAIN: Dictionary = {
	"panel_dy": 0.0,
	"icon_top": 450.0,
	"num_center": 1155.0,
	"cur_center": 1304.0,
	"best_top": 1370.0,
}
const _LAYOUT_ENC: Dictionary = {
	"panel_dy": 70.0,
	"icon_top": 274.0,
	"num_center": 972.0,
	"cur_center": 1116.0,
	"best_top": 1182.0,
}
const _ENC_CELL_SCENE: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_encourage_cell.tscn"
)

const _ADD_AFTER_CHECKIN: float = 0.9
const _RECOVER_TO_CHECKIN: float = 1.1167
const _CHECKIN_TO_CHEST: float = 2.0836 - 1.1167
const _CHEST_CHECKIN_TO_NEWWEEK: float = 1.0
const _NEWWEEK_TO_CHECKIN: float = 0.75

const _RECOVER_ICON_START_DELAY: float = 0.5


static func open_main() -> UIFrameWindow:
	var ui_name: StringName = UiName.STREAK
	if ABTestManager.daily_streak_page.is_history_page_enabled():
		ui_name = UiName.STREAK_HOME
	return UIManager.show_ui(ui_name, {_PARAM_STATE: DisplayState.MAIN})


static func open_lit() -> StreakPage:
	return _open_success(DisplayState.LIT)


static func open_settle() -> StreakPage:
	return _open_success(DisplayState.SETTLE)


static func open_after_win() -> void:
	var page: StreakPage = (
		open_lit() if StreakManager.get_data().current_streak == 1 else open_settle()
	)
	if page != null:
		await UIManager.await_hidden(page.get_ui_name())


static func _open_success(state: DisplayState) -> StreakPage:
	var ui_name: StringName = UiName.STREAK
	var params: Dictionary = {_PARAM_STATE: state}
	if ABTestManager.daily_streak_success_page.is_separate_success_page_enabled():
		ui_name = UiName.DAILY_STREAK_SUCCESS
		params["play_effect"] = true
	return UIManager.show_ui(ui_name, params) as StreakPage


const _ICON_BASE_HEIGHT: float = 512.0
const _ICON_CENTER := Vector2(256.0, 256.0)

const _TITLE_ICON_GAP: float = 12.0

const _ICON_MIN_HEIGHT: float = 200.0

const _FIT_EPS: float = 0.5

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _slots: Array[Control] = [
	$StreakContent/StreakPanel/SlotWed,
	$StreakContent/StreakPanel/SlotThu,
	$StreakContent/StreakPanel/SlotFri,
	$StreakContent/StreakPanel/SlotSat,
	$StreakContent/StreakPanel/SlotSun,
	$StreakContent/StreakPanel/SlotMon,
	$StreakContent/StreakPanel/SlotTue,
]

@onready var _slots2: Array[Control] = [
	$StreakContent/StreakPanel2/SlotWed,
	$StreakContent/StreakPanel2/SlotThu,
	$StreakContent/StreakPanel2/SlotFri,
	$StreakContent/StreakPanel2/SlotSat,
	$StreakContent/StreakPanel2/SlotSun,
	$StreakContent/StreakPanel2/SlotMon,
	$StreakContent/StreakPanel2/SlotTue,
]

@onready var _streak_num: Label = $"StreakContent/StreakPanel/Num/2Txt"
@onready var _num_txt0: Label = $"StreakContent/StreakPanel/Num/2Txt0"
@onready var _num_txt_new: Label = $"StreakContent/StreakPanel/Num/2TxtNew"
@onready var _num_anim: AnimationPlayer = $StreakContent/StreakPanel/Num/AnimationPlayer
@onready var _best_streak_group: Control = $StreakContent/StreakPanel/Group5 # 最佳记录整块（常规态与结算态显示）

@onready var _streak_panel: Control = $StreakContent/StreakPanel
@onready var _streak_panel2: Control = $StreakContent/StreakPanel2
@onready var _icon_slot: Control = $StreakContent/StreakPanel/IconSlot
@onready var _num_group: Control = $StreakContent/StreakPanel/Num
@onready var _cur_streak_txt: Label = $StreakContent/StreakPanel/CurrentStreakTxt

@onready var _enc_slot: Control = $StreakContent/EncourageSlot
@onready var _best_label: Label = $StreakContent/StreakPanel/Group5/BestStreak99Txt # 最佳记录文字
@onready var _claim_btn: Button = $StreakContent/ClaimBtn # 结算态的「继续」按钮
@onready var _back_btn: Button = $StreakContent/Top/BackBtnGroup # 常规态的返回按钮

@onready var _top_bar: Control = $StreakContent/Top
@onready var _title_label: Label = $StreakContent/Top/Level/LevelTxt
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面动画播放器

@onready var _day_icon: StreakDayIcon = $StreakContent/StreakPanel/IconSlot/Icon/StreakDayIcon

@onready var _icon_holder: Control = $StreakContent/StreakPanel/IconSlot/Icon

@onready var _tap_hint_label: Label = $StreakContent/StreakPanel/IconSlot/LevelTxt

@onready var _go_to_play_btn: Button = $StreakContent/GoToPlayBtn

# ---- 运行时状态 ----
var _state: DisplayState = DisplayState.MAIN # 当前展示状态
var _lit_consumed: bool = false # 点亮态是否已被点击消费（防重复触发）
var _lit_enter_done: bool = false # 入场动画是否播完（播完之前的点击不算）

var _enc_cell = null

var _icon_loop_allowed: bool = true


func on_create() -> void:
	bind_press_release_scale(_claim_btn)
	bind_press_release_scale(_back_btn)
	bind_press_release_scale(_go_to_play_btn)


func on_show(params: Dictionary = {}) -> void:
	var requested: int = params.get(_PARAM_STATE, DisplayState.MAIN)

	if not visible:
		push_error(
			"[STREAK-DESYNC] on_show visible=false state=%d req=%d" % [_window_state, requested]
		)

	var _win_p: UIFrameWindow = UIManager.get_ui(UiName.WIN)
	var _dwin_p: UIFrameWindow = UIManager.get_ui(UiName.DAILY_WIN)

	if (
		((_win_p != null and _win_p.visible) or (_dwin_p != null and _dwin_p.visible))
		and not ABTestManager.daily_streak.is_settle_reorder()
	):
		push_error(
			"[STREAK-OVER-WIN] streak on_show 时胜利页仍可见 state=%d req=%d" % [_window_state, requested]
		)

	visible = true
	_lit_consumed = false
	_lit_enter_done = false

	_icon_loop_allowed = requested != DisplayState.SETTLE
	_set_go_to_play_enabled(false)
	_reset_num()

	_tap_hint_label.text = ABTestManager.dailystreak_icon.tap_hint_key(
		StreakManager.get_effective_icon_group()
	)
	_apply_state(requested)
	_play_enter_anim(requested)
	if requested == DisplayState.SETTLE:
		_run_settle_flow()


func on_hide() -> void:
	_reset_num()
	closed.emit()


## 返回键：只有常规态才自己处理，其余状态交回给系统
func on_escape() -> bool:
	if _state != DisplayState.MAIN:
		return false
	_on_back_pressed()
	return true


## 埋点页面名：常规态算打卡页，结算态算游戏内打卡
func get_scr_name() -> String:
	match _state:
		DisplayState.MAIN:
			return Tracker.Scr.STREAK
		DisplayState.SETTLE:
			return Tracker.Scr.GAME_STREAK
		_:
			return ""


func _play_enter_anim(s: int) -> void:
	var anim_name: StringName
	match s:
		DisplayState.LIT:
			anim_name = &"Appear"
		DisplayState.SETTLE:
			if _is_revive_settle():
				_prime_recover_enter()
				anim_name = &"Recover"
			else:
				anim_name = &"Appear3"
		_:
			anim_name = &"Appear2" if StreakManager.can_checkin_today() else &"Appear3"
	if _anim.has_animation(anim_name):
		if _anim.has_animation(&"RESET"):
			_anim.play(&"RESET")
			_anim.advance(0.0)

			_day_icon.reset_icon()
			_day_icon.refresh_group(_resolve_icon_lit())

		_sync_unlit_icon_alpha(anim_name)
		_anim.play(anim_name)

		if s == DisplayState.SETTLE:
			if (
				anim_name == &"Recover"
				and ABTestManager.dailystreak_icon.plays_on_every_checkin(
					StreakManager.get_effective_icon_group()
				)
			):
				create_countdown(_RECOVER_ICON_START_DELAY, _on_lit_icon_anim_finished)
			else:
				connect_managed_once(_anim.animation_finished, _on_lit_icon_anim_finished)
		if s == DisplayState.LIT:
			connect_managed_once(_anim.animation_finished, _on_lit_enter_anim_finished)
		elif s == DisplayState.MAIN and ABTestManager.daily_streak.has_play_entry():
			connect_managed_once(_anim.animation_finished, _on_main_enter_anim_finished)
	elif s == DisplayState.MAIN and ABTestManager.daily_streak.has_play_entry():
		_set_go_to_play_enabled(true)


const _ICON_MODULATE_PATH := NodePath("StreakContent/StreakPanel/IconSlot/Icon:modulate")


func _sync_unlit_icon_alpha(anim_name: StringName) -> void:
	if anim_name != &"Appear" and anim_name != &"Appear2":
		return
	var keep_dim: bool = not ABTestManager.dailystreak_icon.has_unchecked_art(
		StreakManager.get_effective_icon_group()
	)
	var anim: Animation = _anim.get_animation(anim_name)
	if anim != null:
		var idx: int = anim.find_track(_ICON_MODULATE_PATH, Animation.TYPE_VALUE)
		if idx >= 0:
			anim.track_set_enabled(idx, keep_dim)
	if not keep_dim:
		_icon_holder.modulate.a = 1.0


func _resolve_icon_lit() -> bool:
	var lit: bool = (
		_state == DisplayState.SETTLE
		or (_state == DisplayState.MAIN and not StreakManager.can_checkin_today())
	)
	return lit and _icon_loop_allowed


func _on_lit_icon_anim_finished(_finished_anim: StringName = &"") -> void:
	_icon_loop_allowed = true

	if (
		_state == DisplayState.SETTLE
		and ABTestManager.dailystreak_icon.plays_on_every_checkin(
			StreakManager.get_effective_icon_group()
		)
	):
		_day_icon.play_checkin_anim()
		return
	_day_icon.refresh_group(_resolve_icon_lit())


## 入场动画播完，点亮态开始接受点击
func _on_lit_enter_anim_finished(_finished_anim: StringName) -> void:
	_lit_enter_done = true


func _on_main_enter_anim_finished(_finished_anim: StringName) -> void:
	_set_go_to_play_enabled(true)


func _is_revive_settle() -> bool:
	return str(StreakManager.get_revive_anim().get("kind", "")) == "backfill"


func _prime_recover_enter() -> void:
	var revive: Dictionary = StreakManager.get_revive_anim()
	var final_streak: int = StreakManager.get_data().current_streak
	var gained: int = int(revive.get("gained", 1))
	var pre_streak: int = final_streak - gained
	if _streak_num:
		_streak_num.text = str(pre_streak)
	if _num_txt0:
		_num_txt0.text = "0"
	_render_week_on(_slots, _week_pos(int(revive.get("pre_cycle", 0))))


## 切状态并整页刷新
func _apply_state(s: int) -> void:
	_state = s
	_refresh()


func _refresh() -> void:
	_refresh_visibility()
	_refresh_data()

	_refresh_encourage()

	_apply_icon_fit()


func _refresh_visibility() -> void:
	var is_main: bool = _state == DisplayState.MAIN
	var is_settle: bool = _state == DisplayState.SETTLE

	_back_btn.visible = is_main

	_best_streak_group.visible = is_main or is_settle
	_claim_btn.visible = is_settle

	_go_to_play_btn.visible = is_main and ABTestManager.daily_streak.has_play_entry()

	_day_icon.refresh_group(_resolve_icon_lit())


func _apply_icon_fit() -> void:
	var fit: Vector2 = _resolve_icon_fit()
	var h: float = fit.x
	var center := Vector2(_ICON_CENTER.x, fit.y)

	if ABTestManager.dailystreak_icon.is_canvas_calibrated(
		StreakManager.get_effective_icon_group()
	):
		_day_icon.fit_canvas(h, center)
	else:
		_day_icon.fit_uniform_height(h, center)


func _resolve_icon_fit() -> Vector2:
	var slot_top: float = _icon_slot.global_position.y
	var top_limit: float = _title_visual_bottom() + _TITLE_ICON_GAP
	var bottom_limit: float = _num_group.global_position.y - _TITLE_ICON_GAP
	var avail: float = bottom_limit - top_limit

	var h: float = minf(_ICON_BASE_HEIGHT, maxf(avail, _ICON_MIN_HEIGHT))

	var content_top: float = slot_top + _ICON_CENTER.y - h * 0.5
	if content_top >= top_limit - _FIT_EPS and content_top + h <= bottom_limit + _FIT_EPS:
		return Vector2(h, _ICON_CENTER.y)
	return Vector2(h, (top_limit + bottom_limit) * 0.5 - slot_top)


func _title_visual_bottom() -> float:
	var top_center: float = _top_bar.global_position.y + _top_bar.size.y * 0.5
	var title_center: float = _title_label.global_position.y + _title_label.size.y * 0.5
	if HomeSettingAnchor.has_value():
		title_center += HomeSettingAnchor.get_settingbtn_y() - top_center
	var font: Font = _title_label.get_theme_font(&"font")
	var text_h: float = _title_label.size.y
	if font != null:
		text_h = font.get_height(_title_label.get_theme_font_size(&"font_size"))
	return title_center + text_h * 0.5


func _refresh_data() -> void:
	var data: StreakData = StreakManager.get_data()

	var display: int = StreakManager.get_display_streak()

	if _state == DisplayState.SETTLE and not _is_revive_settle() and display >= 2:
		_streak_num.text = str(display - 1)
	else:
		_streak_num.text = str(display)
	_best_label.text = tr("DAILY_STREAK_BEST_FORMAT") % data.best_streak
	_refresh_slots()


func _refresh_slots() -> void:
	var slots: Array[Dictionary] = StreakManager.get_week_slots()

	var anim_idx: int = _new_checkin_index() if _state == DisplayState.SETTLE else -1
	for i: int in range(_slots.size()):
		var s: Dictionary = slots[i]
		var slot: Control = _slots[i]
		var slot_is_chest: bool = i == _slots.size() - 1
		slot.weekday = _WEEKDAY_LABELS[int(s.weekday)]
		if i == anim_idx:
			slot.apply_static(false, slot_is_chest)
		else:
			slot.apply_static(bool(s.checked), slot_is_chest)


## 找出这一轮里最后一个已点亮的格子下标（没有则 -1），就是今天刚打的那格
func _new_checkin_index() -> int:
	var slots: Array[Dictionary] = StreakManager.get_week_slots()
	var idx: int = -1
	for i: int in range(slots.size()):
		if bool(slots[i].checked):
			idx = i
	return idx


func _refresh_encourage() -> void:
	var info: Dictionary = _resolve_encourage()
	var active: bool = not info.is_empty()
	_apply_encourage_layout(active)
	_enc_slot.visible = active
	if not active:
		return
	if _enc_cell == null:
		_enc_cell = create_child(_ENC_CELL_SCENE)
		if _enc_cell == null:
			push_error("StreakPage: 鼓励条 cell 创建失败,回落对照组布局")
			_apply_encourage_layout(false)
			_enc_slot.visible = false
			return
		var prev_parent: Node = _enc_cell.get_parent()
		if prev_parent != null:
			prev_parent.remove_child(_enc_cell)
		_enc_slot.add_child(_enc_cell)
		_enc_cell.position = Vector2.ZERO
	_enc_cell.set_slot(int(info["slot"]), ABTestManager.daily_streak_encourage.has_cat())
	_enc_cell.set_text(tr(String(info["name_key"])), tr(String(info["body_key"])))


func _resolve_encourage() -> Dictionary:
	var cfg: DailyStreakEncourageConfig = ABTestManager.daily_streak_encourage
	if not cfg.is_enabled():
		return {}

	if _state == DisplayState.MAIN and StreakManager.can_checkin_today():
		return {}

	var minute: int = StreakManager.get_last_checkin_minute()
	if minute < 0:
		return {}
	var info: Dictionary = StreakEncourageData.resolve(
		minute / 60, minute % 60, cfg.uses_top_percent()
	)

	if not bool(info.get("visible", false)):
		return {}
	return info


func _apply_encourage_layout(active: bool) -> void:
	var lay: Dictionary = _LAYOUT_ENC if active else _LAYOUT_PLAIN
	var dy: float = float(lay["panel_dy"])

	for p: Control in [_streak_panel, _streak_panel2]:
		p.offset_top = _PANEL_BASE_TOP + dy
		p.offset_bottom = -_PANEL_BASE_TOP + dy

	_set_top_keep_height(_icon_slot, float(lay["icon_top"]) - dy)
	_set_center_keep_height(_num_group, float(lay["num_center"]) - dy)
	_set_center_keep_height(_cur_streak_txt, float(lay["cur_center"]) - dy)
	_set_top_keep_height(_best_streak_group, float(lay["best_top"]) - dy)


func _set_top_keep_height(node: Control, top: float) -> void:
	var h: float = node.offset_bottom - node.offset_top
	node.offset_top = top
	node.offset_bottom = top + h


func _set_center_keep_height(node: Control, center: float) -> void:
	var h: float = node.offset_bottom - node.offset_top
	node.offset_top = center - h * 0.5
	node.offset_bottom = node.offset_top + h


## 读取管理器保存的补签表现信息，选择普通签到或跨天补签演出。
func _run_settle_flow(slot_delay: float = _SETTLE_SLOT_DELAY) -> void:
	var revive: Dictionary = StreakManager.get_revive_anim()
	match str(revive.get("kind", "")):
		"backfill":
			await _run_backfill_settle(revive, slot_delay)
		_:
			await _run_normal_settle(slot_delay)


func _run_normal_settle(slot_delay: float) -> void:
	var idx: int = _new_checkin_index()
	if idx < 0:
		return
	var slot: Control = _slots[idx]
	var has_award: bool = StreakManager.get_pending_show_uid() > 0
	_set_continue_enabled(false)

	await get_tree().create_timer(slot_delay).timeout
	if not is_showing():
		return

	if not has_award:
		slot.play_checkin(false)
		_maybe_play_add()
		StreakManager.consume_pending_show()
		_set_continue_enabled(true)
		return

	var dur: float = slot.play_checkin(true)
	await get_tree().create_timer(dur).timeout
	if not is_showing():
		return
	StreakManager.claim_reward(false)
	StreakManager.consume_pending_show()
	slot.hide_chest()
	slot.show_unchecked_dot()
	await _await_reward_closed()
	if not is_showing():
		return
	slot.play_checkin(false)
	_maybe_play_add()
	_set_continue_enabled(true)


## 把补签拆成当前周、宝箱日和下一周，逐段演出后消费待展示状态并解锁继续。
func _run_backfill_settle(anim: Dictionary, _slot_delay: float) -> void:
	_set_continue_enabled(false)
	var pre_cycle: int = int(anim.get("pre_cycle", 0))
	var gained: int = int(anim.get("gained", 1))
	var base_week: int = pre_cycle / CYCLE_LENGTH

	var this_week: Array[int] = []
	var chest_day: int = -1
	var next_week: Array[int] = []
	for d: int in range(pre_cycle + 1, pre_cycle + gained + 1):
		if d % CYCLE_LENGTH == 0:
			chest_day = d
		elif (d - 1) / CYCLE_LENGTH == base_week:
			this_week.append(d)
		else:
			next_week.append(d)

	var final_streak: int = StreakManager.get_data().current_streak
	var pre_streak: int = final_streak - gained

	await get_tree().create_timer(_RECOVER_TO_CHECKIN).timeout
	if not is_showing():
		return
	for d: int in this_week:
		_slots[(d - 1) % CYCLE_LENGTH].play_checkin(false)

	if chest_day > 0:
		if not this_week.is_empty():
			await get_tree().create_timer(_CHECKIN_TO_CHEST).timeout
			if not is_showing():
				return
		var ci: int = (chest_day - 1) % CYCLE_LENGTH
		var dur: float = _slots[ci].play_checkin(true)
		await get_tree().create_timer(dur).timeout
		if not is_showing():
			return
		if StreakManager.get_pending_show_uid() > 0:
			StreakManager.claim_reward(false)
			_slots[ci].hide_chest()
			_slots[ci].show_unchecked_dot()
			await _await_reward_closed()
			if not is_showing():
				return
			_slots[ci].play_checkin(false)

	if not next_week.is_empty():
		await get_tree().create_timer(_CHEST_CHECKIN_TO_NEWWEEK).timeout
		if not is_showing():
			return
		_render_week_on(_slots2, 0)
		if _anim.has_animation(&"NewWeek"):
			_anim.play(&"NewWeek")
		await get_tree().create_timer(_NEWWEEK_TO_CHECKIN).timeout
		if not is_showing():
			return
		for d: int in next_week:
			_slots2[(d - 1) % CYCLE_LENGTH].play_checkin(false)

	_play_num_add_after(_ADD_AFTER_CHECKIN, pre_streak, final_streak)
	StreakManager.consume_pending_show()
	_set_continue_enabled(true)


func _maybe_play_add() -> void:
	var to_val: int = StreakManager.get_data().current_streak
	_play_num_add_after(_ADD_AFTER_CHECKIN, to_val - 1, to_val)


func _play_num_add_after(delay: float, from_val: int, to_val: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_showing():
		return
	_play_num_add(from_val, to_val)


func _play_num_add(from_val: int, to_val: int) -> void:
	if from_val <= 0 or _num_anim == null or not _num_anim.has_animation(&"Add"):
		if _streak_num:
			_streak_num.text = str(to_val)
		return
	_streak_num.text = str(from_val)
	_num_txt_new.text = str(to_val)
	_num_anim.play(&"Add")
	await _num_anim.animation_finished
	if not is_instance_valid(_num_anim):
		return
	_streak_num.text = str(to_val)
	_reset_num()


func _reset_num() -> void:
	if _num_anim != null and _num_anim.has_animation(&"RESET"):
		_num_anim.play(&"RESET")
		_num_anim.advance(0.0)


func _week_pos(cycle: int) -> int:
	return posmod(cycle, CYCLE_LENGTH)


func _render_week_on(target: Array, filled: int, start_wd: int = -1) -> void:
	var slots: Array[Dictionary] = StreakManager.get_week_slots()
	for i: int in range(target.size()):
		var is_chest_slot: bool = i == target.size() - 1
		var wd: int = (start_wd + i) % 7 if start_wd >= 0 else int(slots[i].weekday)
		target[i].weekday = _WEEKDAY_LABELS[wd]
		target[i].apply_static(i < filled, is_chest_slot)


func _await_reward_closed() -> void:
	await UIManager.await_hidden(UiName.AWARD)


func _set_continue_enabled(enabled: bool) -> void:
	if _claim_btn:
		_claim_btn.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func _set_go_to_play_enabled(enabled: bool) -> void:
	if _go_to_play_btn:
		_go_to_play_btn.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func _input(event: InputEvent) -> void:
	if _consume_lit_click(event):
		_light_up_to_settle()


func _consume_lit_click(event: InputEvent) -> bool:
	if (
		not is_showing()
		or not is_visible_in_tree()
		or _state != DisplayState.LIT
		or _lit_consumed
		or not _lit_enter_done
	):
		return false
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return false
	_lit_consumed = true
	get_viewport().set_input_as_handled()
	if ABTestManager.daily_streak_success_page.is_separate_success_page_enabled():
		VibrateManager.play_at(VibrateManager.Pos.STREAK_FIRST_CLICK)
	return true


func _light_up_to_settle() -> void:
	var icon_group: int = StreakManager.get_effective_icon_group()
	var page_anim: StringName = ABTestManager.dailystreak_icon.page_lit_anim(icon_group)

	if page_anim == &"" or not _anim.has_animation(page_anim):
		page_anim = &"LightUp"
	var slot_delay: float = ABTestManager.dailystreak_icon.page_lit_slot_delay(icon_group)
	if page_anim == &"LightUp" or slot_delay < 0.0:
		slot_delay = _LIT_SLOT_DELAY
	if _anim.has_animation(page_anim):
		_anim.play(page_anim)

	_icon_loop_allowed = true

	_day_icon.play_checkin_anim()
	_apply_state(DisplayState.SETTLE)
	_run_settle_flow(slot_delay)

	Tracker.track_scr_show(Tracker.Scr.GAME_STREAK)


func _on_back_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(get_ui_name())


func _on_continue_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_CONTINUE)
	UIManager.hide_ui(get_ui_name())


func _on_go_to_play_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.GOTOPLAY, self)
	VibrateManager.play_at(VibrateManager.Pos.STREAK_GO_PLAY)
	UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
	var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
	if home != null and home.is_showing():
		UIManager.hide_ui(UiName.HOME)
	UIManager.hide_ui(get_ui_name())
