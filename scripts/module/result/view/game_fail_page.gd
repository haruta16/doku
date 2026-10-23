## 主线失败页：展示失败进度和复活入口，校验页面状态后处理广告、重开或特殊关卡跳过。
class_name GameFailPage
extends UIFrameWindow

## 复活条件已就绪（免费名额或广告已发奖）时发出，GamePage 收到后真正复活
signal revive_requested

## 复活流程开始（免费或广告都已拉起）时发出，GamePage 先把棋盘上的猫复位
signal revive_ad_started

signal golden_fish_skipped

const _LEGACY_TITLE_STYLE: Dictionary = {
	"outline_thickness": 16,
	"outline_color": Color(0.16078432, 0.44705883, 0.7764706, 1),
}

var _title_style_cache: Dictionary = {}

const _INPUT_BLOCK_DURATION: float = 1.5

const _APPEAR_GROUP1_DURATION: float = 1.9

@onready var _title_label: SingleLineGlyphLabel = $Root/VBoxContainer/Title/AnimCtrl/TitleLabelUnder

@onready var _title_label_up: SingleLineGlyphLabel = $Root/VBoxContainer/Title/AnimCtrl/TitleLabelUp

@onready var _count_text: RichTextLabel = $Root/VBoxContainer/CatCountSlot/CatCountRow/CountText

@onready var _count_row: Control = $Root/VBoxContainer/CatCountSlot/CatCountRow

@onready var _cat_progress: CatProgressBar = $Root/VBoxContainer/CatCountSlot/CatProgressBar

var _cat_progress_fade_tween: Tween = null

@onready
var _encourage_label: RichTextLabel = $Root/VBoxContainer/VBoxContainer/MarginContainer/EncourageLabel
@onready var _revive_btn: Control = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn
@onready var _restart_btn: Control = $Root/VBoxContainer/VBoxContainer/RestartCtrl/RestartBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗动画（appear / idle / disappear）
@onready
var _revive_ad_icon: TextureRect = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/TextIconRow/Icon
@onready
var _revive_badge: GameAdBadge = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/Badge

@onready
var _revive_main_label: Label = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/TextIconRow/Label
@onready
var _revive_subtitle: Label = $Root/VBoxContainer/VBoxContainer/ReviveCtrl/ReviveBtn/Root/SubtitleLabel

@onready var _cat_face: TextureRect = $Root/VBoxContainer/CatCountSlot/CatCountRow/CatFace

@onready var _costume_slot: Control = $Root/VBoxContainer/CatCountSlot/CatCountRow/CostumeCatSlot

@onready
var _costume_cat: SpineSprite = $Root/VBoxContainer/CatCountSlot/CatCountRow/CostumeCatSlot/CostumeCat

const _COUNT_NUM_COLOR: String = "#d94848"

const _COSTUME_IDLE_ANIM: String = "idle"

const _COSTUME_ID_KEY: String = "costume_id"

const _CAT_PROGRESS_MAX_BAR_WIDTH: float = 760.0

const _CAT_COUNT_SLOT_DESIGN_HEIGHT: float = 100.0

const _CAT_PROGRESS_G2_GAP_ABOVE_BAR: float = 20.0

const _CAT_PROGRESS_FADE_FALLBACK: Vector2 = Vector2(0.6333333, 0.2666667)
const _CAT_PROGRESS_G2_BAR_SLOT_HEIGHT: float = 100.0
const _CAT_PROGRESS_G2_TEXT_BLOCK_HEIGHT: float = 140.0

const _GAP_COUNT_TEXT_DESIGN: float = 60.0
const _TEXT_BLOCK_DESIGN: float = 200.0

const _GAP_COUNT_TEXT_NODE: String = "GapCountText"
const _TEXT_BLOCK_NODE: String = "VBoxContainer/MarginContainer"

# ---- 复活主文案的自适应宽度参数（像素） ----
const _REVIVE_ROW_MAX_WIDTH: float = 705.0 # 可用最大宽度
const _REVIVE_ROW_ICON_WIDTH: float = 100.0 # 广告图标占位宽
const _REVIVE_ROW_SEPARATION: float = 24.0 # 图标与文字间距
const _REVIVE_MAIN_FONT_SIZE_BASE: int = 88 # 基准字号
const _REVIVE_MAIN_FONT_SIZE_MIN: int = 40 # 缩放下限字号

const _GF_SKIP_NODE_NAME: StringName = &"GoldenFishSkipLink"

const _GF_SKIP_DELAY: float = 0.4

var _gf_skip_link: Button = null

var _gf_skip_busy: bool = false
var _restart_committed: bool = false

var _gf_skip_timer: Timer = null

var _level_config: Dictionary = {} # 本局关卡参数（GamePage 传入）
var _retry_params: Dictionary = {} # 重开时原样回传给 GamePage 的参数

var _show_seq_id: int = 0

var _revive_ad_show_id: String = ""

var _revive_ad_check_pending: bool = false

var _encourage_fade_tween: Tween = null # 鼓励文案的淡入 tween，刷新时先 kill

var _cat_progress_added: bool = false


func _ready() -> void:
	_gf_skip_link = find_node_by_name(_GF_SKIP_NODE_NAME) as Button
	_refresh_dynamic_text()

	var slot: Control = _cat_progress.get_parent() as Control
	if slot != null:
		slot.resized.connect(_layout_cat_progress)


## 语言切换后重新取文案（多处按语言 / 分组分支）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


func _refresh_dynamic_text() -> void:
	var is_golden: bool = _is_golden_fish_level()

	var title_text: String = tr("FAIL_TITLE_GOLDEN_FISH") if is_golden else tr("FAIL_TITLE_FISH")
	_title_label.text = title_text
	_title_label_up.text = title_text

	var life_cap: int = int(_level_config.get("life_cap", 3))
	if is_golden:
		_revive_main_label.text = tr("FAIL_REVIVE_1FISH")
	elif life_cap == 3:
		_revive_main_label.text = tr("FAIL_REVIVE_3FISH")
	else:
		_revive_main_label.text = tr("FAIL_REVIVE_NFISH") % life_cap

	_revive_subtitle.visible = false
	_fit_main_label_width()


## 让主文案在可用宽度内不溢出：按测量结果等比缩字号，但不小于下限
func _fit_main_label_width() -> void:
	# 节点没准备好就跳过（编辑器预览 / 换皮）
	if _revive_main_label == null:
		return

	# 先按基准字号重置一遍
	_revive_main_label.add_theme_font_size_override("font_size", _REVIVE_MAIN_FONT_SIZE_BASE)
	var font: Font = _revive_main_label.get_theme_font("font")
	if font == null:
		return
	# 有广告图标时要扣掉图标宽与间距
	var icon_visible: bool = _revive_ad_icon != null and _revive_ad_icon.visible
	var avail: float = _REVIVE_ROW_MAX_WIDTH
	if icon_visible:
		avail -= _REVIVE_ROW_ICON_WIDTH + _REVIVE_ROW_SEPARATION
	# 量出基准字号下的文本宽度
	var measured: float = (
		font
		. get_string_size(
			_revive_main_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _REVIVE_MAIN_FONT_SIZE_BASE
		)
		. x
	)
	# 没溢出就不用动
	if measured <= avail:
		return
	# 等比缩放并夹到下限
	var new_size: int = maxi(
		_REVIVE_MAIN_FONT_SIZE_MIN, int(floor(_REVIVE_MAIN_FONT_SIZE_BASE * avail / measured))
	)
	_revive_main_label.add_theme_font_size_override("font_size", new_size)


const _LAYOUT_H_TALL: float = 2400.0
const _LAYOUT_H_SHORT: float = 1920.0

const _LAYOUT_FIXED_SUM: float = 1695.0

const _LAYOUT_GAPS: Dictionary = {
	"TopGap": [290.0, 50.0],
	"GapTitleCat": [155.0, 90.0],
	"VBoxContainer/GapAfterText": [60.0, 40.0],
	"GapBeforeTap": [80.0, 30.0],
}


func _apply_layout_gaps(height_override: float = -1.0) -> void:
	var vb: Control = get_node_or_null("Root/VBoxContainer") as Control
	if vb == null:
		return
	var h: float = (
		height_override if height_override > 0.0 else get_viewport().get_visible_rect().size.y
	)

	var avail: float = h + vb.offset_bottom - vb.offset_top
	if avail <= 0.0:
		avail = h
	var t: float = clampf((avail - _LAYOUT_H_SHORT) / (_LAYOUT_H_TALL - _LAYOUT_H_SHORT), 0.0, 1.0)
	var names: Array = _LAYOUT_GAPS.keys()
	var want: Dictionary = {}
	var gap_sum: float = 0.0
	for n: String in names:
		var node: Control = vb.get_node_or_null(n) as Control
		if node == null:
			push_error("GameFailPage: 缺间距槽 %s(布局适配失效)" % n)
			continue
		var pair: Array = _LAYOUT_GAPS[n]
		var v: float = lerpf(float(pair[1]), float(pair[0]), t)
		want[n] = v
		gap_sum += v
		node.custom_minimum_size.y = v
	if gap_sum <= 0.0:
		return

	var scale: float = clampf((avail - _LAYOUT_FIXED_SUM) / gap_sum, 0.0, 1.0)
	if scale >= 1.0:
		return
	var names2: Array = want.keys()
	for n2: String in names2:
		var node2: Control = vb.get_node_or_null(n2) as Control
		if node2 != null:
			node2.custom_minimum_size.y = float(want[n2]) * scale


func on_show(params: Dictionary = {}) -> void:
	_apply_layout_gaps()

	SoundManager.set_bgm_paused(true, BgmPauseReason.FAIL)

	var block_sec: float = _INPUT_BLOCK_DURATION
	if PurchaseManager.can_claim_vip_daily_gift():
		block_sec = _APPEAR_GROUP1_DURATION
	UIManager.block_input_briefly(self, block_sec)
	var lc: Dictionary = params.get("level_config", {})
	var rp: Dictionary = params.get("retry_params", {})
	var rc: int = params.get("remaining_cats", 0)

	var cp: Dictionary = params.get("cat_progress", {})

	EndTitleArtStyle.apply(_title_label, _title_label_up, _title_style_cache, _LEGACY_TITLE_STYLE)
	show_fail(lc, rp, rc, cp)

	_run_vip_daily_gift_async()


func _run_vip_daily_gift_async() -> void:
	await _anim.animation_finished
	if not is_showing():
		return
	await VipDailyGiftFlow.run()


func on_hide() -> void:
	_show_seq_id += 1
	var seq: int = _show_seq_id
	_revive_ad_show_id = ""
	_revive_ad_check_pending = false

	SoundManager.set_bgm_paused(false, BgmPauseReason.FAIL)
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


func _refresh_revive_btn_stock_async(pos: String) -> void:
	var seq: int = _show_seq_id
	var show_id: String = _revive_ad_show_id
	var ad_ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, pos, show_id)
	if seq != _show_seq_id or not _can_submit_fail_action():
		return
	_revive_btn.visible = ad_ready


func show_fail(
	level_config: Dictionary,
	retry_params: Dictionary = {},
	remaining_cats: int = 0,
	cat_progress: Dictionary = {}
) -> void:
	_show_seq_id += 1
	_gf_skip_busy = false
	_restart_committed = false
	_revive_ad_show_id = ""
	_revive_ad_check_pending = false
	_level_config = level_config
	_retry_params = retry_params
	_count_text.text = (
		"%s[b][color=%s]%d[/color][/b]"
		% [tr("FAIL_REMAINING_CAT"), _COUNT_NUM_COLOR, remaining_cats]
	)
	_apply_cat_progress(cat_progress)
	_refresh_dynamic_text()
	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)
	var _is_golden: bool = _is_golden_fish_level()

	var free: bool = _is_free_revive()
	_revive_btn.visible = free
	if not free:
		_revive_ad_show_id = UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, pos)
		_refresh_revive_btn_stock_async(pos)

	_revive_ad_icon.visible = false
	_revive_badge.visible = true
	if free:
		_revive_badge.show_free()
		_revive_badge.scale = Vector2.ONE * 1.4
	else:
		_revive_badge.show_icon_with_ad()
		_revive_badge.scale = Vector2.ONE
	_fit_main_label_width()
	_refresh_encourage_label(remaining_cats)
	_refresh_golden_fish_skip()
	visible = true
	_refresh_costume_cat()
	SoundManager.play(SoundManager.Kind.LEVEL_FAIL)

	_anim.stop()

	_anim.play("RESET")
	_anim.advance(0.0)

	_reset_fail_cat_spines()
	_resume_fail_cat_spines()

	_anim.play("appear_group1_glodenfish" if _is_golden else "appear_group1")

	_anim.advance(0.0)
	AnimUtil.commit_nested(_anim)

	_anim.queue("idle_group1_glodenfish" if _is_golden else "idle_group1")

	_play_cat_progress_fade_in("appear_group1_glodenfish" if _is_golden else "appear_group1")


func _fail_cat_spines() -> Array:
	var base: String = "Root/VBoxContainer/CenterContainer/Control/"
	var out: Array = []
	for n: String in ["SpineSprite", "SpineSprite2", "SpineSprite3"]:
		var sp := get_node_or_null(base + n) as SpineSprite
		if sp != null:
			out.append(sp)
	return out


func _reset_fail_cat_spines() -> void:
	for sp: SpineSprite in _fail_cat_spines():
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_animation("in", false, 0)
			st.set_time_scale(0.0)


func _resume_fail_cat_spines() -> void:
	for sp: SpineSprite in _fail_cat_spines():
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


func _refresh_costume_cat() -> void:
	var use_costume: bool = _uses_costume_cat()
	_cat_face.visible = not use_costume
	_costume_slot.visible = use_costume
	if not use_costume:
		return

	if _costume_cat.skeleton_data_res != CostumeSkin.SKELETON_RES:
		_costume_cat.skeleton_data_res = CostumeSkin.SKELETON_RES
	CostumeSkin.apply(_costume_cat, _in_game_costume_id())
	_freeze_costume_cat_idle()


func _in_game_costume_id() -> int:
	var snapshot: int = int(_level_config.get(_COSTUME_ID_KEY, 0))
	if CostumeCatalog.is_valid(snapshot):
		return snapshot
	return ProfileService.get_costume_id()


func _uses_costume_cat() -> bool:
	return (
		ABTestManager.dc_costume.has_costume()
		or int(_level_config.get("companion_costume_override", 0)) != 0
	)


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

	_apply_g2_flow_heights(_cat_progress_added)
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

	_cat_progress.set_cat_costume(_in_game_costume_id(), _uses_costume_cat())
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
	var slot: Control = _cat_progress.get_parent() as Control
	if slot == null:
		return
	var slot_w: float = slot.size.x
	if slot_w <= 0.0:
		return

	var slot_h: float = slot.size.y
	if slot_h <= 0.0:
		slot_h = _CAT_COUNT_SLOT_DESIGN_HEIGHT
	var bar_w: float = _cat_progress.size.x
	var bar_h: float = _cat_progress.size.y
	_cat_progress.offset_left = (slot_w - bar_w) * 0.5
	_cat_progress.offset_right = _cat_progress.offset_left + bar_w
	if _cat_progress_added:
		var lead: float = (_CAT_PROGRESS_G2_BAR_SLOT_HEIGHT - bar_h) * 0.5
		_cat_progress.offset_top = slot_h + _CAT_PROGRESS_G2_GAP_ABOVE_BAR + lead
		_cat_progress.offset_bottom = _cat_progress.offset_top + bar_h
		return
	_cat_progress.offset_top = (slot_h - bar_h) * 0.5
	_cat_progress.offset_bottom = _cat_progress.offset_top + bar_h


func _apply_g2_flow_heights(added: bool) -> void:
	var vb: Control = get_node_or_null("Root/VBoxContainer") as Control
	if vb == null:
		return
	var gap: Control = vb.get_node_or_null(_GAP_COUNT_TEXT_NODE) as Control
	var text_block: Control = vb.get_node_or_null(_TEXT_BLOCK_NODE) as Control
	if gap == null or text_block == null:
		push_error(
			"GameFailPage: 缺 %s / %s（「增加进度条」组的垂直分段失效）" % [_GAP_COUNT_TEXT_NODE, _TEXT_BLOCK_NODE]
		)
		return
	if added:
		gap.custom_minimum_size.y = (
			_CAT_PROGRESS_G2_GAP_ABOVE_BAR + _CAT_PROGRESS_G2_BAR_SLOT_HEIGHT
		)
		text_block.custom_minimum_size.y = _CAT_PROGRESS_G2_TEXT_BLOCK_HEIGHT
		return
	gap.custom_minimum_size.y = _GAP_COUNT_TEXT_DESIGN
	text_block.custom_minimum_size.y = _TEXT_BLOCK_DESIGN


func _is_free_revive() -> bool:
	if BaseGamePage.debug_force_free_tool == "all":
		return true
	return not ABTestManager.reward_unlock_level.is_reward_required_at(
		GameState.get_current_level()
	)


func _refresh_encourage_label(remaining_cats: int) -> void:
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	if not ABTestManager.fail_text.should_show_encourage():
		_encourage_label.visible = false
		return
	var level: int = int(_level_config.get("level", 1))
	var sz: int = int(_level_config.get("size", SizeModifier.get_size(level)))
	var delay: float
	var fade_dur: float
	if ABTestManager.fail_text.should_show_revive_promote() and _revive_btn.visible:
		var x: float = GameState.get_fail_text_revive_x(level)
		if x < 0.0:
			var is_daily: bool = _level_config.get("is_daily", false)
			x = FailTextStats.pick_revive_promote_x(level, sz, is_daily)
			GameState.set_fail_text_revive_x(level, x)
		_encourage_label.text = FailTextStats.format_revive_promote(x)
		delay = 0.8166
		fade_dur = 0.35
	else:
		var found_ratio: float = 0.0 if sz <= 0 else float(sz - remaining_cats) / float(sz)
		_encourage_label.text = FailTextStats.pick_encourage_text(found_ratio)
		delay = 0.9833
		fade_dur = 0.35

	_encourage_label.visible = true
	_encourage_label.modulate = Color(1, 1, 1, 0)
	_encourage_fade_tween = create_tween()
	_encourage_fade_tween.tween_interval(delay)
	_encourage_fade_tween.tween_property(_encourage_label, "modulate:a", 1.0, fade_dur)


## 先检查免费复活或查询激励库存，回调还需匹配展示序号和当前页面状态才发布复活请求。
func _on_revive_btn_pressed() -> void:
	if _revive_ad_check_pending or not _can_submit_fail_action() or not _revive_btn.visible:
		return
	Tracker.track_btn_click(Tracker.Btn.REVIVE, self)

	if _is_free_revive():
		revive_ad_started.emit()
		revive_requested.emit()
		return

	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)
	var seq: int = _show_seq_id
	var show_id: String = _revive_ad_show_id
	_revive_ad_check_pending = true
	var ad_ready: bool = await UniKitManager.is_reward_ready(AdPlacement.REWARD, pos, show_id)
	if seq != _show_seq_id or not _can_submit_fail_action():
		return
	_revive_ad_check_pending = false
	if not ad_ready:
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != AdPlacement.REWARD:
			return
		if seq != _show_seq_id or not _can_submit_fail_action():
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


## 只断开「回调对象是本页」的广告连接，不动其它页面的监听
func _disconnect_self_reward_callbacks() -> void:
	# 逐个查连接，比对自己挂上去的回调
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


## 只有页面仍显示且未提交重开、未进入跳关流程时，才接受新的失败页动作。
func _can_submit_fail_action() -> bool:
	return is_showing() and not _gf_skip_busy and not _restart_committed


func _on_restart_btn_pressed() -> void:
	if not _can_submit_fail_action():
		return
	_restart_committed = true
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)

	LevelOps.on_restart_click()
	if _level_config.get("is_daily", false):
		UIManager.show_ui(UiName.DAILY_GAME, {"_tracker_status": Tracker.GameStatus.RESTART})
		return

	var params: Dictionary = (
		_retry_params.duplicate()
		if not _retry_params.is_empty()
		else {"level_index": _level_config.get("level", 1)}
	)
	params["_tracker_status"] = Tracker.GameStatus.RESTART
	UIManager.show_ui(UiName.GAME, params)


func _is_golden_fish_level() -> bool:
	return LevelKind.is_golden_fish(int(_level_config.get("kind", LevelKind.default_kind())))


func _should_show_golden_fish_skip() -> bool:
	return _is_golden_fish_level() or _is_color_challenge_level()


func _is_color_challenge_level() -> bool:
	return LevelKind.is_color_challenge(int(_level_config.get("kind", LevelKind.default_kind())))


func _refresh_golden_fish_skip() -> void:
	if _gf_skip_timer != null and is_instance_valid(_gf_skip_timer):
		remove_timer(_gf_skip_timer)
	_gf_skip_timer = null
	if _gf_skip_link == null:
		return
	_gf_skip_link.visible = false
	if not _should_show_golden_fish_skip():
		return

	_gf_skip_link.text = (
		ColorChallengeBtnStyle.skip_text(GameState.get_current_level())
		if _is_color_challenge_level()
		else GoldenFishBtnStyle.skip_text(GameState.get_current_level())
	)
	_gf_skip_timer = create_countdown(_GF_SKIP_DELAY, _show_golden_fish_skip_link)


func _show_golden_fish_skip_link() -> void:
	_gf_skip_timer = null
	if (
		_gf_skip_link == null
		or not _can_submit_fail_action()
		or not _should_show_golden_fish_skip()
	):
		return
	_gf_skip_link.visible = true


func _on_golden_fish_skip_pressed() -> void:
	if not _can_submit_fail_action():
		return
	_gf_skip_busy = true

	if _is_color_challenge_level():
		Tracker.track_btn_click(Tracker.Btn.COLOR_CHALLENGE_SKIP, self)

		GameState.on_color_challenge_skipped(
			GameState.get_current_level(), ABTestManager.color_challenge_func.group_value(), true
		)
	else:
		Tracker.track_btn_click(Tracker.Btn.GOLDEN_FISH_SKIP, self)

		golden_fish_skipped.emit()
		GameState.on_golden_fish_skipped(GameState.get_current_level())

	UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})


func get_scr_name() -> String:
	if _is_golden_fish_level():
		return Tracker.Scr.GOLDEN_FISH_GAME_FAIL
	return Tracker.Scr.NORMAL_GAME_FAIL
