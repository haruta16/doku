## 每日挑战失败页：展示剩余猫与鼓励文案，协调复活广告和重新挑战请求。
class_name DailyFailPage
extends UIFrameWindow

# ---- 信号（由 DailyGamePage 连接） ----
signal revive_requested # 复活已生效，请游戏页把棋盘恢复正常

signal revive_ad_started # 广告即将播放，先让棋盘上的猫回位

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _root: Control = $Root # 整页根节点，用于复位整体透明度

@onready
var _count_text: RichTextLabel = $Root/VBoxContainer/CenterContainer/Control/CatCountRow/CountText

@onready var _count_row: Control = $Root/VBoxContainer/CenterContainer/Control/CatCountRow

@onready
var _cat_progress: CatProgressBar = $Root/VBoxContainer/CenterContainer/Control/CatProgressBar

var _cat_progress_fade_tween: Tween = null

@onready var _encourage_slot: Control = $Root/VBoxContainer/VBoxContainer/EncourageSlot
@onready
var _encourage_label: RichTextLabel = $Root/VBoxContainer/VBoxContainer/EncourageSlot/EncourageLabel
@onready var _revive_btn: Control = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn
@onready var _try_again_btn: Control = $Root/VBoxContainer/VBoxContainer/TryAgainCtrl/TryAgainBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面进出场动画
@onready var _title_under: SingleLineGlyphLabel = $Root/VBoxContainer/Title/TitleLabelUnder
@onready var _title_up: SingleLineGlyphLabel = $Root/VBoxContainer/Title/TitleLabelUp
@onready
var _revive_ad_icon: TextureRect = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/TextIconRow/Icon
@onready
var _revive_badge: GameAdBadge = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/Badge

@onready
var _revive_main_label: Label = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/TextIconRow/Label
@onready
var _revive_subtitle: Label = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/SubtitleLabel

@onready var _cat_face: TextureRect = $Root/VBoxContainer/CenterContainer/Control/CatCountRow/CatFace

@onready
var _costume_slot: Control = $Root/VBoxContainer/CenterContainer/Control/CatCountRow/CostumeCatSlot

@onready
var _costume_cat: SpineSprite = $Root/VBoxContainer/CenterContainer/Control/CatCountRow/CostumeCatSlot/CostumeCat

const _COSTUME_IDLE_ANIM: String = "idle"

const _LEGACY_TITLE_STYLE: Dictionary = {
	"outline_thickness": 16,
	"outline_color": Color(0.16078432, 0.44705883, 0.7764706, 1),
}

var _title_style_cache: Dictionary = {}

const _COUNT_NUM_COLOR: String = "#d94848"

const _CAT_PROGRESS_MAX_BAR_WIDTH: float = 760.0

const _CAT_PROGRESS_BAND_CENTER_Y: float = 460.0

const _CAT_COUNT_ROW_DESIGN_HEIGHT: float = 120.0

const _CAT_PROGRESS_G2_GAP_BELOW_ROW: float = 20.0

const _CAT_PROGRESS_FADE_FALLBACK: Vector2 = Vector2(0.6333333, 0.2666667)

const _REVIVE_ROW_MAX_WIDTH: float = 705.0 # 图标行可用最大宽度
const _REVIVE_ROW_ICON_WIDTH: float = 100.0 # 广告图标占用的宽度
const _REVIVE_ROW_SEPARATION: float = 24.0 # 图标与文字之间的间距
const _REVIVE_MAIN_FONT_SIZE_BASE: int = 88 # 主文案基准字号
const _REVIVE_MAIN_FONT_SIZE_MIN: int = 40 # 缩放后允许的最小字号

var _encourage_fade_tween: Tween = null # 鼓励文案淡入用的 Tween

var _show_seq_id: int = 0

var _revive_ad_show_id: String = ""

var _revive_ad_check_pending: bool = false

var _cat_progress_added: bool = false


func _ready() -> void:
	_refresh_dynamic_text()


## 切换语言后要重新排版（按钮字号是量出来的）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


func _refresh_dynamic_text() -> void:
	_revive_main_label.text = tr("FAIL_REVIVE_3FISH")

	_revive_subtitle.visible = false
	_fit_main_label_width()


## 主文案超宽就按可用宽度等比缩小字号（用同一个字体量宽度）
func _fit_main_label_width() -> void:
	if _revive_main_label == null:
		return

	_revive_main_label.add_theme_font_size_override("font_size", _REVIVE_MAIN_FONT_SIZE_BASE)
	var font: Font = _revive_main_label.get_theme_font("font")
	if font == null:
		return
	var icon_visible: bool = _revive_ad_icon != null and _revive_ad_icon.visible
	var avail: float = _REVIVE_ROW_MAX_WIDTH
	if icon_visible:
		avail -= _REVIVE_ROW_ICON_WIDTH + _REVIVE_ROW_SEPARATION
	var measured: float = (
		font
		. get_string_size(
			_revive_main_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _REVIVE_MAIN_FONT_SIZE_BASE
		)
		. x
	)
	if measured <= avail:
		return
	var new_size: int = maxi(
		_REVIVE_MAIN_FONT_SIZE_MIN, int(floor(_REVIVE_MAIN_FONT_SIZE_BASE * avail / measured))
	)
	_revive_main_label.add_theme_font_size_override("font_size", new_size)


func on_show(params: Dictionary = {}) -> void:
	SoundManager.set_bgm_paused(true, BgmPauseReason.DAILY_FAIL)
	var lc: Dictionary = params.get("level_config", {})
	var rc: int = params.get("remaining_cats", 0)

	var cp: Dictionary = params.get("cat_progress", {})

	EndTitleArtStyle.apply(_title_under, _title_up, _title_style_cache, _LEGACY_TITLE_STYLE)
	show_fail(lc, rc, cp)


func _refresh_revive_btn_stock_async() -> void:
	var seq: int = _show_seq_id
	var show_id: String = _revive_ad_show_id
	var ad_ready: bool = await UniKitManager.is_reward_ready(
		AdPlacement.REWARD, Tracker.AdPos.DAILY_GAME_FAIL, show_id
	)
	if seq != _show_seq_id or not is_showing():
		return
	_revive_btn.visible = ad_ready


func show_fail(
	level_config: Dictionary, remaining_cats: int = 0, cat_progress: Dictionary = {}
) -> void:
	_show_seq_id += 1
	_revive_ad_show_id = ""
	_revive_ad_check_pending = false
	visible = true
	_root.modulate = Color(1, 1, 1, 1)
	_layout_title_for_height()
	_layout_buttons_for_height()
	_count_text.text = (
		"%s[b][color=%s]%d[/color][/b]"
		% [tr("FAIL_REMAINING_CAT"), _COUNT_NUM_COLOR, remaining_cats]
	)

	_companion_override_snapshot = int(level_config.get("companion_costume_override", -1))
	_refresh_costume_cat()
	_apply_cat_progress(cat_progress)

	_refresh_dynamic_text()

	var free: bool = _is_free_revive()

	_revive_btn.visible = free
	if not free:
		_revive_ad_show_id = UniKitManager.stats_ad_show_timing(
			AdPlacement.REWARD, Tracker.AdPos.DAILY_GAME_FAIL
		)
		_refresh_revive_btn_stock_async()

	_revive_ad_icon.visible = false
	_revive_badge.visible = not free
	_revive_badge.show_icon_with_ad()
	_revive_badge.scale = Vector2.ONE

	_fit_main_label_width()
	_refresh_encourage_label(level_config, remaining_cats)
	SoundManager.play(SoundManager.Kind.LEVEL_FAIL)

	_anim.stop()

	_anim.play("RESET")
	_anim.advance(0.0)

	_reset_fail_cat_spines()
	_resume_fail_cat_spines()
	_anim.play("appear_group1")

	_anim.advance(0.0)
	AnimUtil.commit_nested(_anim)
	_anim.queue("idle_group1")

	_play_cat_progress_fade_in("appear_group1")


func _layout_buttons_for_height(height_override: float = -1.0) -> void:
	var h: float = (
		height_override if height_override > 0.0 else get_viewport().get_visible_rect().size.y
	)
	var t: float = clampf((h - 1920.0) / 480.0, 0.0, 1.0)
	_encourage_slot.custom_minimum_size.y = lerpf(365.0, 210.0, t)


func _layout_title_for_height(height_override: float = -1.0) -> void:
	var h: float = (
		height_override if height_override > 0.0 else get_viewport().get_visible_rect().size.y
	)
	var t: float = clampf((h - 1920.0) / 480.0, 0.0, 1.0)
	_title_under.position.y = lerpf(55.0, 295.0, t)
	_title_up.position.y = lerpf(53.0, 293.0, t)


func _reset_fail_cat_spines() -> void:
	for sp: SpineSprite in [
		$Root/VBoxContainer/CenterContainer/Control/SpineSprite,
		$Root/VBoxContainer/CenterContainer/Control/SpineSprite2
	]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_animation("in", false, 0)
			st.set_time_scale(0.0)


func _resume_fail_cat_spines() -> void:
	for sp: SpineSprite in [
		$Root/VBoxContainer/CenterContainer/Control/SpineSprite,
		$Root/VBoxContainer/CenterContainer/Control/SpineSprite2
	]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


func _refresh_costume_cat() -> void:
	var use_costume: bool = ABTestManager.dc_costume.has_costume() or _companion_override() != 0
	_cat_face.visible = not use_costume
	_costume_slot.visible = use_costume
	if not use_costume:
		return

	if _costume_cat.skeleton_data_res != CostumeSkin.SKELETON_RES:
		_costume_cat.skeleton_data_res = CostumeSkin.SKELETON_RES
	CostumeSkin.apply(_costume_cat, _dc_costume_id())
	_freeze_costume_cat_idle()


func _dc_costume_id() -> int:
	var override_id: int = _companion_override()
	if override_id != 0:
		return override_id
	return ProfileService.get_today_costume()


func _companion_override() -> int:
	if _companion_override_snapshot >= 0:
		return _companion_override_snapshot
	return _COMPANION_SERVICE.new().in_game_costume_override()


var _companion_override_snapshot: int = -1
const _COMPANION_SERVICE: GDScript = preload("res://scripts/module/home/home_companion_service.gd")


func _freeze_costume_cat_idle() -> void:
	var data: SpineSkeletonDataResource = _costume_cat.get_skeleton_data_res()
	if data == null or data.find_animation(_COSTUME_IDLE_ANIM) == null:
		return
	var st := _costume_cat.get_animation_state()
	if st == null:
		return
	st.set_animation(_COSTUME_IDLE_ANIM, false, 0)
	st.set_time_scale(0.0)


func _apply_cat_progress(snapshot: Dictionary) -> void:
	var shows_bar: bool = ABTestManager.fail_ui.shows_progress_bar()
	var hides_count: bool = ABTestManager.fail_ui.hides_count_text()
	var wants_replace: bool = shows_bar and hides_count
	var wants_add: bool = shows_bar and not hides_count
	var plan: Dictionary = FailCatProgressPlan.resolve(wants_replace, wants_add, snapshot)
	_cat_progress_added = bool(plan["bar_added"])
	_count_row.visible = bool(plan["show_count"])
	_cat_progress.visible = bool(plan["show_bar"])

	_cat_progress.modulate.a = 1.0
	if not bool(plan["show_bar"]):
		return
	var total: int = int(plan["total"])
	var metrics: Dictionary = CatProgressBar.solve_metrics(total, _CAT_PROGRESS_MAX_BAR_WIDTH)
	if snapshot.has("compact_order") and bool(plan["colored"]):
		_cat_progress.setup_compact(
			total,
			metrics["slot"],
			metrics["pitch"],
			metrics["padding"],
			snapshot.get("tints", PackedColorArray())
		)
		_cat_progress.restore_compact(plan["revealed"], snapshot["compact_order"])
	else:
		_cat_progress.setup(total, metrics["slot"], metrics["pitch"], metrics["padding"])

	_cat_progress.use_soft_shadow()
	_cat_progress.set_colored_mode(bool(plan["colored"]))
	_cat_progress.set_tints(snapshot.get("tints", PackedColorArray()))
	_cat_progress.set_revealed(plan["revealed"])

	_cat_progress.set_cat_costume(
		_dc_costume_id(), ABTestManager.dc_costume.has_costume() or _companion_override() != 0
	)
	_layout_cat_progress()


func _play_cat_progress_fade_in(anim_name: String) -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return
	var window: Vector2 = _count_row_fade_window(anim_name)
	if _cat_progress_fade_tween != null and _cat_progress_fade_tween.is_valid():
		_cat_progress_fade_tween.kill()
	_cat_progress.modulate.a = 0.0
	_cat_progress_fade_tween = create_tween()
	_cat_progress_fade_tween.tween_interval(window.x)
	_cat_progress_fade_tween.tween_property(_cat_progress, "modulate:a", 1.0, window.y)


func _count_row_fade_window(anim_name: String) -> Vector2:
	if _anim == null or not _anim.has_animation(anim_name):
		return _CAT_PROGRESS_FADE_FALLBACK
	var anim: Animation = _anim.get_animation(anim_name)
	if anim == null:
		return _CAT_PROGRESS_FADE_FALLBACK
	var want: NodePath = _track_path_of(_count_row, "modulate")
	for t: int in anim.get_track_count():
		if anim.track_get_path(t) != want:
			continue
		for k: int in anim.track_get_key_count(t):
			var value: Variant = anim.track_get_key_value(t, k)
			if not (value is Color) or (value as Color).a <= 0.0:
				continue
			var fade_end: float = anim.track_get_key_time(t, k)
			var fade_start: float = 0.0 if k == 0 else anim.track_get_key_time(t, k - 1)
			var duration: float = maxf(fade_end - fade_start, 0.0)
			if duration <= 0.0:
				return _CAT_PROGRESS_FADE_FALLBACK
			return Vector2(fade_start, duration)
		break
	return _CAT_PROGRESS_FADE_FALLBACK


func _track_path_of(node: Node, property: String) -> NodePath:
	if _anim == null or node == null:
		return NodePath()
	var base: Node = _anim.get_node_or_null(_anim.root_node)
	if base == null:
		base = self
	return NodePath("%s:%s" % [str(base.get_path_to(node)), property])


func _layout_cat_progress() -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return
	var half_w: float = _cat_progress.size.x * 0.5
	var bar_h: float = _cat_progress.size.y
	_cat_progress.offset_left = -half_w
	_cat_progress.offset_right = half_w
	if _cat_progress_added:
		var row_bottom: float = _CAT_PROGRESS_BAND_CENTER_Y + _CAT_COUNT_ROW_DESIGN_HEIGHT * 0.5
		_cat_progress.offset_top = row_bottom + _CAT_PROGRESS_G2_GAP_BELOW_ROW
		_cat_progress.offset_bottom = _cat_progress.offset_top + bar_h
		return
	_cat_progress.offset_top = _CAT_PROGRESS_BAND_CENTER_Y - bar_h * 0.5
	_cat_progress.offset_bottom = _CAT_PROGRESS_BAND_CENTER_Y + bar_h * 0.5


# ================= 鼓励文案 =================
## 先杀掉上一次的淡入 Tween，再按实验选复活推广或普通鼓励
func _refresh_encourage_label(level_config: Dictionary, remaining_cats: int) -> void:
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	if not ABTestManager.fail_text.should_show_encourage():
		_encourage_label.visible = false
		return
	var level: int = int(level_config.get("level", GameState.get_current_level()))
	var sz: int = int(level_config.get("size", 12))
	# 两种文案各自的出现延迟与淡入时长（秒），和出场动画对齐
	var delay: float
	var fade_dur: float
	# 推广用的 x 值按等级缓存：没有就抽一个并存档
	if ABTestManager.fail_text.should_show_revive_promote() and _revive_btn.visible:
		var x: float = GameState.get_fail_text_revive_x(level)
		if x < 0.0:
			x = FailTextStats.pick_revive_promote_x(level, sz, true)
			GameState.set_fail_text_revive_x(level, x)
		_encourage_label.text = FailTextStats.format_revive_promote(x)
		delay = 0.8166
		fade_dur = 0.35
	else:
		# 普通鼓励按「已找到的猫占比」挑句子
		var found_ratio: float = 0.0 if sz <= 0 else float(sz - remaining_cats) / float(sz)
		_encourage_label.text = FailTextStats.pick_encourage_text(found_ratio)
		delay = 0.9833
		fade_dur = 0.35
	# 从全透明淡入到不透明，延迟跟出场动画对齐
	_encourage_label.visible = true
	_encourage_label.modulate = Color(1, 1, 1, 0)

	_encourage_fade_tween = create_tween()
	_encourage_fade_tween.tween_interval(delay)
	_encourage_fade_tween.tween_property(_encourage_label, "modulate:a", 1.0, fade_dur)


func on_hide() -> void:
	_show_seq_id += 1
	var seq: int = _show_seq_id
	_revive_ad_show_id = ""
	_revive_ad_check_pending = false

	SoundManager.set_bgm_paused(false, BgmPauseReason.DAILY_FAIL)
	_disconnect_self_reward_callbacks()
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	_anim.stop()
	_anim.play("disappear")
	await _anim.animation_finished
	if seq != _show_seq_id:
		return

	_reset_fail_cat_spines()
	visible = false


func _is_free_revive() -> bool:
	if BaseGamePage.debug_force_free_tool == "all":
		return true
	return not ABTestManager.reward_unlock_level.is_reward_required_at(
		GameState.get_current_level()
	)


func _on_revive_btn_pressed() -> void:
	if _revive_ad_check_pending or not is_showing() or not _revive_btn.visible:
		return
	Tracker.track_btn_click(Tracker.Btn.REVIVE, self)

	if _is_free_revive():
		revive_ad_started.emit()
		revive_requested.emit()
		return
	var pos: String = Tracker.AdPos.DAILY_GAME_FAIL
	var seq: int = _show_seq_id
	var show_id: String = _revive_ad_show_id
	_revive_ad_check_pending = true
	var ad_ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, pos, show_id)
	if seq != _show_seq_id or not is_showing():
		return
	_revive_ad_check_pending = false
	if not ad_ready:
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != AdPlacement.REWARD:
			return
		revive_requested.emit()
	var on_closed := func(placement_id: String) -> void:
		if placement_id != AdPlacement.REWARD:
			return

	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)

	revive_ad_started.emit()
	UniKitManager.show_reward(AdPlacement.REWARD, pos, show_id)


## 遍历两个广告信号，只断开 callable 属于本节点的连接
func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


## 重开：走 LevelOps 的重开流程，并以 RESTART 状态重进每日页
func _on_try_again_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)

	LevelOps.on_restart_click()
	UIManager.show_ui(UiName.DAILY_GAME, {"_tracker_status": Tracker.GameStatus.RESTART})


## 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME_FAIL
