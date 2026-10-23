## 通关结算协调页：展示成绩与猫动画，按序处理陪伴奖励、会员礼、评分和下一关流程。
@tool
class_name GameWinPage
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _overlay: ColorRect = $Root/Overlay # 全屏半透明遮罩
@onready var _ray_light: TextureRect = $Root/Ctrl/RayLight # 光芒
@onready var _cat: SpineSprite = $Root/Ctrl/VictoryCat # 胜利猫（Spine 骨骼动画）

@onready var _cat_gf: SpineSprite = $Root/Ctrl/VictoryCatGlodenFish

@onready var _title: SingleLineGlyphLabel = $Root/Ctrl/TitleLabelUnder

@onready var _title_up: SingleLineGlyphLabel = $Root/Ctrl/TitleLabelUp

@onready var _next_btn: Control = $Root/Ctrl/VBoxContainer/NextBtn # 「下一关」按钮（Control，带 btn_text / show_difficult 属性）
@onready
var _beat_percent_label: RichTextLabel = $Root/Ctrl/VBoxContainer/MarginContainer/BeatPercentLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗本体动画（Appear / Loop / Disappear）

@onready var _g4_info: Control = $Root/Ctrl/VBoxContainer/InfoGroup
@onready var _g4_time: Label = $Root/Ctrl/VBoxContainer/InfoGroup/TimeItem/ValueLabel
@onready var _g4_score: Label = $Root/Ctrl/VBoxContainer/InfoGroup/ScoreItem/ValueLabel
@onready var _g4_combo: Label = $Root/Ctrl/VBoxContainer/InfoGroup/ComboItem/ValueLabel
@onready var _g4_time_key: Label = $Root/Ctrl/VBoxContainer/InfoGroup/TimeItem/KeyLabel
@onready var _g4_score_key: Label = $Root/Ctrl/VBoxContainer/InfoGroup/ScoreItem/KeyLabel
@onready var _g4_combo_key: Label = $Root/Ctrl/VBoxContainer/InfoGroup/ComboItem/KeyLabel

const _PASS_PAGE_G1_BOARD: PackedScene = preload(
	"res://scripts/module/result/ui/pass_page_g1_board.tscn"
)
const _PASS_PAGE_G2_BOARD: PackedScene = preload(
	"res://scripts/module/result/ui/pass_page_g2_board.tscn"
)
const _COMPANION_SERVICE: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
const _COMPANION_STRIP: PackedScene = preload(
	"res://scripts/module/home/ui/home_companion_settle_strip.tscn"
)

const _COMPANION_STRIP_SCRIPT: GDScript = preload(
	"res://scripts/module/home/view/home_companion_settle_strip.gd"
)

var _companion_service: RefCounted = _COMPANION_SERVICE.new()

var _companion_reward_sequence: int = -1

var _companion_strip: Control = null
var _pass_board: PassPageG1Board = null
var _g4_roll_tween: Tween = null

const NEXT_LOGIC_COOLDOWN_MS: int = 1000

var _next_logic_allowed_at_ms: int = 0

const _LEGACY_TITLE_STYLE: Dictionary = {
	"outline_thickness": 12,
	"outline_color": Color(0.8, 0.34901962, 0, 1),
}

var _title_style_cache: Dictionary = {}

# ---- 动画时序（秒） ----
const APPEAR_DELAY: float = 1.2 # 出现前的等待：先让棋盘把自己的动画播完

const APPEAR_DURATION: float = 2.467 # Appear 动画时长，用于算遮输入时长与评星延迟

const _COMPANION_GAIN_AT: float = 1.05

## 普通关标题候选池：随机取，且避开上一次用过的那条
const WIN_TITLES_NORMAL: Array[StringName] = [
	&"WIN_TITLE", &"WIN_TITLE_1", &"WIN_TITLE_2", &"WIN_TITLE_3", &"WIN_TITLE_4"
]

const _GF_SKIP_NODE_NAME: StringName = &"GoldenFishSkipLink"

const _GF_SKIP_DELAY: float = 0.4

const _GF_SKIP_READY_ALPHA: float = 0.99

var _gf_skip_link: Button = null

var _gf_skip_busy: bool = false

var _gf_skip_timer: Timer = null

var _gf_skip_target: int = 0

const _GF_GAP_BASE: float = 112.0
const _GF_PAD_AT_SHORT: float = 203.0
const _GF_PAD_AT_TALL: float = 212.0
const _GF_H_SHORT: float = 1920.0
const _GF_H_TALL: float = 2400.0

var _gf_top_pad_base: float = -1.0

const _ADAPT_H_SHORT: float = 1920.0
const _ADAPT_H_TALL: float = 2400.0

const _ADAPT_RISE_SHORT: float = 85.0

const _ADAPT_VBOX_SEP_SHORT: int = 2

const _ADAPT_BUDGET_NODE: StringName = &"ShortScreenBudget"

const _ADAPT_SEP_UNREAD: int = -9999

const _ADAPT_SKIN_V2_PATH: String = "res://scripts/module/result/ui/game_win_page_v2.tscn"

const _ADAPT_CAT_NODES: Array[StringName] = [
	&"VictoryCat",
	&"Pass_anim_cat1",
	&"Pass_anim_cat2",
	&"Pass_anim_cat3",
	&"VictoryCatGlodenFish",
	&"VictoryCatGlow",
]

const _ADAPT_RAY_NODES: Array[StringName] = [
	&"EffectRayLight",
	&"EffectRayLight2",
	&"EffectRayLightcat1",
	&"EffectRayLightcat3",
]

var _adapt_cat_base_y: Dictionary = {}
var _adapt_vbox_base_sep: int = _ADAPT_SEP_UNREAD

# ---- 运行时状态 ----
var _level_config: Dictionary = {} # 本局关卡参数（GamePage 传入，并补写重开/复活/失误/用时等统计）
var _last_win_title: StringName = &"" # 上一次用过的标题，保证连续两次不重复

var _pass_text_strategy: PassTextStrategy # 通关文案策略，on_show 时按 AB 分组创建

var _win_text: Dictionary = {} # 策略产出：title / body / shown_percent

var _show_seq_id: int = 0 # 展示序号：异步等待之后用它判断这次展示是否已被顶掉


func _ready() -> void:
	if Engine.is_editor_hint():
		visible = true
		_overlay.color.a = 0.8
		_ray_light.modulate.a = 0.7
		_cat.scale = Vector2.ONE
		_title.fade = 1.0
		_title_up.fade = 1.0
		_next_btn.modulate.a = 1.0
		return
	bind_press_release_scale($Root/Ctrl/BankBtn)
	_gf_skip_link = find_node_by_name(_GF_SKIP_NODE_NAME) as Button


func on_show(params: Dictionary = {}) -> void:
	_next_logic_allowed_at_ms = 0
	modulate.a = 1.0

	_pass_text_strategy = PassTextStrategy.create()

	EndTitleArtStyle.apply(_title, _title_up, _title_style_cache, _LEGACY_TITLE_STYLE)
	var level_config: Dictionary = params.get("level_config", {})

	var board_view: BoardView = params.get("board_view")
	if board_view != null:
		show_win(level_config, board_view)
	connect_managed(RankActivityManager.settle_ready, _on_rank_settle_ready)
	_complete_unawarded_rank_period.call_deferred(_show_seq_id)


func _on_rank_settle_ready(_result: Dictionary) -> void:
	_complete_unawarded_rank_period.call_deferred(_show_seq_id)


func _complete_unawarded_rank_period(sequence: int) -> void:
	if sequence != _show_seq_id or not is_showing():
		return
	if int(_level_config.get("level", 0)) <= 0 or bool(_level_config.get("is_daily", false)):
		return
	if ABTestManager.podium_per_leaderboard.has_end_solo_podium():
		return
	if not RankActivityManager.get_pending_end_solo_podium().is_empty():
		RankActivityManager.notify_settlement_done()


func on_hide() -> void:
	if not visible:
		return
	var owns_companion_reward: bool = _companion_reward_sequence == _show_seq_id

	_show_seq_id += 1
	var hide_sequence: int = _show_seq_id
	_companion_reward_sequence = -1
	if owns_companion_reward:
		await UIManager.hide_ui(UiName.HOME_COMPANION_REWARD)
		if hide_sequence != _show_seq_id:
			return
	_anim.play("Disappear")
	await _anim.animation_finished
	if hide_sequence != _show_seq_id:
		return

	_reset_cat_spine()

	if _companion_strip != null:
		_companion_strip.hide_strip()


func get_hide_anim_duration() -> float:
	if _anim == null or not _anim.has_animation("Disappear"):
		return 0.0
	return 0.3 + _anim.get_animation("Disappear").length


func show_win(level_config: Dictionary, board_view: BoardView) -> void:
	_level_config = level_config
	_show_seq_id += 1
	var seq: int = _show_seq_id
	visible = true

	_refresh_golden_fish_skip()

	_level_config["last_win_beat_percent"] = GameState.get_last_win_beat_percent()
	_win_text = _pass_text_strategy.get_win_text(_level_config)
	_win_text = _resolve_win_text(_level_config, _win_text)
	_refresh_companion_strip()
	if not OS.has_feature("rel"):
		print(
			(
				"[DailyFirstWin] win lv=%d group=%d first=%s copy_key=%s"
				% [
					int(_level_config.get("level", 0)),
					int(ABTestManager.daily_first_win_encourage.value()),
					str(_level_config.get("is_daily_first_main_win", false)),
					str(_win_text.get("body_key", ""))
				]
			)
		)
	if not _level_config.get("is_daily", false):
		GameState.set_last_win_beat_percent(_win_text.get("shown_percent", -1.0))

	print("————————————————————————————————————————")
	print("[BEAT_PCT_DBG] 打败百分比 = %s" % str(_win_text.get("shown_percent", -1.0)))
	print("————————————————————————————————————————")

	if not _level_config.get("is_daily", false):
		if ABTestManager.pass_page.is_g1():
			_show_pass_board(_PASS_PAGE_G1_BOARD, seq)
			return
		if ABTestManager.pass_page.is_g2():
			_show_pass_board(_PASS_PAGE_G2_BOARD, seq)
			return

	_restore_default_win_body()

	_setup_win_title()
	_setup_next_btn()
	_maybe_show_stats_label()
	_maybe_show_beat_percent_tip()
	_apply_g4_inline()

	_apply_screen_adapt()

	_run_post_win_popups(seq)

	var is_gf: bool = _is_golden_fish_level()
	if not is_gf and not _level_config.get("is_daily", false):
		var lv: int = clampi(int(_level_config.get("lives", 3)), 1, 3)

		GameState.sync_pass_anim_cat_cycle_group(int(ABTestManager.pass_anim_cat.value()))
		if ABTestManager.pass_anim_cat.is_v2():
			var action: int = _pick_pass_anim_cat_v2_action()
			var cat_index: int = PassAnimCatConfig.anim_index_for_action(action)
			if cat_index > 0:
				await _play_pass_anim_cat(
					seq,
					"Appear_Passanimcat%d" % cat_index,
					"Loop_Passanimcat%d" % cat_index,
					PassAnimCatConfig.win_sound_for_action(action)
				)
				return
		elif ABTestManager.pass_anim_cat.is_g1():
			await _play_pass_anim_cat(
				seq,
				"Appear_Passanimcat%d" % lv,
				"Loop_Passanimcat%d" % lv,
				ABTestManager.pass_anim_cat.get_win_sound_kind(lv)
			)
			return
		if ABTestManager.pass_anim_cat.is_g2() and lv <= 2:
			await _play_pass_anim_cat(
				seq,
				"Appear_Passanimcat4",
				"Loop_Passanimcat4",
				ABTestManager.pass_anim_cat.get_win_sound_kind(lv)
			)
			return

	_reset_cat_spine()

	var appear_anim: StringName = &"GlodenFishAppear" if is_gf else &"Appear"
	var loop_anim: StringName = &"LoopGlodenFish" if is_gf else &"Loop"
	_anim.stop()
	_seed_reset()

	_anim.play(appear_anim)
	_anim.advance(0.0)
	_anim.pause()

	SoundManager.play(SoundManager.Kind.LEVEL_WIN)
	_resume_cat_spine()
	_anim.play(appear_anim)

	_anim.advance(0.0)
	AnimUtil.commit_nested(_anim)

	await _anim.animation_finished
	if seq != _show_seq_id:
		return

	_anim.play(loop_anim)


func _seed_reset() -> void:
	_anim.play("RESET")
	_anim.advance(0.0)


func _pick_pass_anim_cat_v2_action() -> int:
	var is_hard: bool = int(_level_config.get("diffi", 0)) >= 1
	var action: int = ABTestManager.pass_anim_cat.pick_v2_action(
		is_hard, GameState.get_pass_anim_cat_cycle_count(), randf()
	)
	if ABTestManager.pass_anim_cat.should_advance_cycle(is_hard):
		GameState.advance_pass_anim_cat_cycle()
	return action


func _is_golden_fish_level() -> bool:
	return LevelKind.is_golden_fish(int(_level_config.get("kind", LevelKind.default_kind())))


const _CAT_SEED_ANIM: Dictionary = {
	"VictoryCat": "appear",
	"VictoryCatGlodenFish": "in",
}


func _reset_cat_spine() -> void:
	for sp: SpineSprite in [_cat, _cat_gf]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_animation(_CAT_SEED_ANIM.get(sp.name, "appear"), false, 0)
			st.set_time_scale(0.0)


func _resume_cat_spine() -> void:
	for sp: SpineSprite in [_cat, _cat_gf]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


func _play_pass_anim_cat(
	seq: int, appear: String, loop: String, win_sound: int = SoundManager.Kind.LEVEL_WIN
) -> void:
	_anim.stop()
	_seed_reset()
	SoundManager.play(win_sound)
	_anim.play(appear)

	_anim.advance(0.0)
	AnimUtil.commit_nested(_anim)
	await _anim.animation_finished
	if seq != _show_seq_id:
		return
	_anim.play(loop)


func _show_pass_board(board_scene: PackedScene, seq: int) -> void:
	_hide_default_win_body()

	$Root.modulate = Color(1, 1, 1, 1)

	if _pass_board != null and _pass_board.scene_file_path != board_scene.resource_path:
		_pass_board.queue_free()
		_pass_board = null
	if _pass_board == null:
		_pass_board = board_scene.instantiate() as PassPageG1Board
		$Root.add_child(_pass_board)
		_pass_board.next_pressed.connect(_on_next_btn_pressed)
	_pass_board.visible = true
	_watch_board_for_strip()
	_place_companion_strip.call_deferred()

	var title_text: String = _win_text.get("title", "")
	if title_text.is_empty():
		title_text = _pick_default_win_title()
	var praise: String = _win_text.get("body", "")
	var next_label: String = _compute_next_btn_label()

	var lv: int = _level_config.get("level", 0)
	var next_is_super_hard: bool = lv > 0 and LevelSelector.is_super_hard_level(_next_level_index())
	var next_is_hard: bool = (
		next_is_super_hard or (lv > 0 and LevelSelector.is_hard_level(_next_level_index()))
	)

	(
		_pass_board
		. populate(
			title_text,
			praise,
			next_label,
			next_is_hard,
			{
				"size": _level_config.get("size", 0),
				"elapsed_sec": _level_config.get("elapsed_sec", 0),
				"final_score": _level_config.get("final_score", 0),
				"max_combo": _level_config.get("max_combo", 0),
				"completion_rate": _level_config.get("completion_rate", 0),
				"mistake_count": _level_config.get("mistake_count", 0),
				"tools_used": _level_config.get("tools_used", 0),
			},
			_is_next_level_golden_fish()
		)
	)

	_pass_board.set_next_super_hard(next_is_super_hard)
	SoundManager.play(SoundManager.Kind.PASS_PAGE_SETTLE)
	_pass_board.play_appear()

	_run_post_win_popups(seq)


func _hide_default_win_body() -> void:
	for n: Node in [
		_title,
		_title_up,
		_cat,
		_cat_gf,
		$Root/Ctrl/VictoryCatGlow,
		_ray_light,
		$Root/Ctrl/EffectRayLight,
		$Root/Ctrl/EffectFlreworks,
		$Root/Ctrl/VBoxContainer
	]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = false


func _restore_default_win_body() -> void:
	if _pass_board != null:
		_pass_board.visible = false

	for n: Node in [
		_title_up, $Root/Ctrl/VictoryCatGlow, $Root/Ctrl/EffectFlreworks, $Root/Ctrl/VBoxContainer
	]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = true

	EndTitleArtStyle.apply(_title, _title_up, _title_style_cache, _LEGACY_TITLE_STYLE)

	for n: Node in [_cat, _cat_gf, _ray_light, $Root/Ctrl/EffectRayLight]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = false


## 按糖果增长、陪伴奖励、会员日礼和评分顺序等待，各步检查展示序号防止旧协程继续操作新页面。
func _run_post_win_popups(seq: int) -> void:
	var lv: int = _level_config.get("level", 0)
	var will_show_rate_us: bool = _is_rate_us_eligible(lv)

	var will_show_vip_gift: bool = PurchaseManager.can_claim_vip_daily_gift()

	var will_show_companion_reward: bool = _has_pending_companion_rewards()

	if will_show_rate_us or will_show_vip_gift or will_show_companion_reward:
		UIManager.block_input_briefly(self, APPEAR_DURATION)
	if will_show_rate_us:
		_next_btn.modulate.a = 0.0
	if will_show_companion_reward:
		_companion_reward_sequence = seq

	await get_tree().create_timer(_COMPANION_GAIN_AT).timeout
	if seq != _show_seq_id:
		if will_show_rate_us:
			_restore_next_btn()
		return
	if _companion_strip != null:
		_companion_strip.play_candy_gain()
	await get_tree().create_timer(APPEAR_DURATION - _COMPANION_GAIN_AT).timeout
	if seq != _show_seq_id:
		if will_show_rate_us:
			_restore_next_btn()
		return

	if _companion_strip != null:
		if _companion_strip.is_gain_playing():
			await _companion_strip.candy_gain_finished
		if seq != _show_seq_id:
			if will_show_rate_us:
				_restore_next_btn()
			return
		await _show_companion_rewards(seq)
		if seq != _show_seq_id:
			if will_show_rate_us:
				_restore_next_btn()
			return
		_companion_strip.settle_candy()

	await VipDailyGiftFlow.run()
	if seq != _show_seq_id:
		if will_show_rate_us:
			_restore_next_btn()
		return

	if will_show_rate_us:
		await _show_rate_us(seq)


func _refresh_companion_strip() -> void:
	var eligible: bool = (
		int(_level_config.get("level", 0)) > 0 and not bool(_level_config.get("is_daily", false))
	)
	var strategy: HomeCompanionCatStrategy = HomeCompanionCatStrategy.create()
	var before: Dictionary = _level_config.get("companion_before_win", {})
	var after: Dictionary = GameState.get_home_companion_data()
	var resolved: HomeCompanionCatStrategy = HomeCompanionCatStrategy.for_mode(
		_companion_service.resolve_mode(strategy)
	)
	if _companion_strip == null:
		if not eligible or not resolved.has_companion():
			return
		_companion_strip = _COMPANION_STRIP.instantiate()
		$Root.add_child(_companion_strip)

		($Root/Ctrl/VBoxContainer as Control).item_rect_changed.connect(_place_companion_strip)
		_next_btn.item_rect_changed.connect(_place_companion_strip)
	_companion_strip.show_for(resolved, before, after, eligible and before is Dictionary)
	_place_companion_strip.call_deferred()


func _watch_board_for_strip() -> void:
	if _pass_board == null or _companion_strip == null:
		return
	var board_btn: Control = _pass_board.get_node_or_null(^"ContentGroup/CtaRow/NextBtn") as Control
	if board_btn != null and not board_btn.item_rect_changed.is_connected(_place_companion_strip):
		board_btn.item_rect_changed.connect(_place_companion_strip)


func _place_companion_strip() -> void:
	if _companion_strip == null or not _companion_strip.visible:
		return
	var anchor_btn: Control = _next_btn
	if _pass_board != null and _pass_board.visible:
		anchor_btn = _pass_board.get_node_or_null(^"ContentGroup/CtaRow/NextBtn") as Control
	if anchor_btn == null or not anchor_btn.is_visible_in_tree():
		_companion_strip.visible = false
		return

	$Root.move_child(_companion_strip, -1)
	var visible_bg: Control = anchor_btn.get_node_or_null(^"Root/Bg") as Control
	var bg_rect: Rect2 = (visible_bg if visible_bg != null else anchor_btn).get_global_rect()
	var anchor_x: float = _COMPANION_STRIP_SCRIPT.ANCHOR_X
	var top: float = bg_rect.end.y + _COMPANION_STRIP_SCRIPT.TOP_GAP
	var room: float = get_viewport_rect().size.y - top
	var fit: float = clampf(room / _companion_strip.size.y, 0.0, 1.0)

	_companion_strip.scale = Vector2(fit, fit)
	_companion_strip.global_position = Vector2(bg_rect.get_center().x - anchor_x * fit, top)


func _has_pending_companion_rewards() -> bool:
	if int(_level_config.get("level", 0)) <= 0 or bool(_level_config.get("is_daily", false)):
		return false
	var pending: Array[int] = _companion_service.pending_presentations()
	return not pending.is_empty()


func _show_companion_rewards(sequence: int) -> void:
	if sequence != _show_seq_id or not is_showing() or not _has_pending_companion_rewards():
		_companion_reward_sequence = -1
		return
	_companion_reward_sequence = sequence
	var pending: Array[int] = _companion_service.pending_presentations()
	for tier: int in pending:
		if sequence != _show_seq_id or not is_showing():
			return
		var chest_from: Vector2 = (
			_companion_strip.chest_global_center() if _companion_strip != null else Vector2.INF
		)
		var page: UIFrameWindow = UIManager.show_ui(
			UiName.HOME_COMPANION_REWARD, {"reward_tier": tier, "chest_from": chest_from}
		)
		if page == null:
			push_error("GameWinPage: companion reward page unavailable, 奖励已到账但玩家看不到取得画面")
			break
		await UIManager.await_hidden(UiName.HOME_COMPANION_REWARD)
		if sequence != _show_seq_id or not is_showing():
			return
		if not page.was_collected():
			break
		_companion_service.complete_reward_presentation(tier)
	_companion_reward_sequence = -1


func _is_rate_us_eligible(lv: int) -> bool:
	return (
		lv >= RateUsPopConfig.GATE_LV_BASELINE
		and not GameState.has_shown_rate_us()
		and UniKitManager.is_online()
	)


func _show_rate_us(seq: int) -> void:
	var lv: int = _level_config.get("level", 0)
	if not _is_rate_us_eligible(lv) or seq != _show_seq_id:
		_restore_next_btn()
		return

	GameState.mark_rate_us_shown()
	await _run_rate_us_flow()
	_restore_next_btn()


func _run_rate_us_flow() -> void:
	var rate_us := UIManager.show_ui(UiName.RATE_US_V2)
	var data: Dictionary = await rate_us.closed
	UIManager.hide_ui(UiName.RATE_US_V2)
	if data.get("is_submitted") and data.get("star_count", 0) > 4:
		InAppReviewManager.request_review()
	elif data.get("is_submitted") and data.get("star_count", 0) <= 4:
		var feedback := UIManager.show_ui(UiName.FEEDBACK, {"as_dlg": true})
		await feedback.closed
		UIManager.hide_ui(UiName.FEEDBACK)


## 「下一关」按钮淡回来（评星流程结束后）
func _restore_next_btn() -> void:
	var tw := create_tween()
	tw.tween_property(_next_btn, "modulate:a", 1.0, 0.25)


func _resolve_win_text(level_config: Dictionary, existing_text: Dictionary) -> Dictionary:
	if int(level_config.get("level", 0)) <= 1 or bool(level_config.get("is_daily", false)):
		return _resolve_first_win_text(level_config, existing_text)
	if (
		bool(level_config.get("is_comeback_main_win", false))
		and ABTestManager.comeback_func.has_welcome_text()
	):
		return _resolve_comeback_win_text(level_config, existing_text)
	return _resolve_daily_first_win_text(level_config, existing_text)


func _resolve_comeback_win_text(level_config: Dictionary, existing_text: Dictionary) -> Dictionary:
	if (
		int(level_config.get("level", 0)) <= 1
		or bool(level_config.get("is_daily", false))
		or not bool(level_config.get("is_comeback_main_win", false))
	):
		return existing_text
	var text_keys: Dictionary = ABTestManager.comeback_func.get_win_text_keys()
	if text_keys.is_empty():
		return existing_text
	var resolved_text: Dictionary = existing_text.duplicate()
	resolved_text["title"] = _translate_comeback_win_copy(text_keys["title_key"], "Great Comeback!")
	resolved_text["body"] = _render_win_override_body(
		text_keys["body_key"],
		_translate_comeback_win_copy(
			text_keys["body_key"], "Still sharp! You haven’t lost your magic touch!"
		)
	)
	resolved_text["body_key"] = text_keys["body_key"]
	return resolved_text


func _translate_comeback_win_copy(key: StringName, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == str(key) else translated


func _render_win_override_body(body_key: StringName, source: String) -> String:
	return TextHighlightRenderer.render(
		ABTestManager.text_highlight, str(body_key), source, "#02BE52"
	)


func _resolve_first_win_text(level_config: Dictionary, existing_text: Dictionary) -> Dictionary:
	var text_keys: Dictionary = ABTestManager.first_win_encourage.get_first_win_text_keys(
		level_config
	)
	if text_keys.is_empty():
		return existing_text
	var resolved_text: Dictionary = existing_text.duplicate()
	resolved_text["title"] = tr(text_keys["title_key"])
	resolved_text["body"] = _render_win_override_body(
		text_keys["body_key"], tr(text_keys["body_key"])
	)
	resolved_text["body_key"] = text_keys["body_key"]
	return resolved_text


func _resolve_daily_first_win_text(
	level_config: Dictionary, existing_text: Dictionary
) -> Dictionary:
	if (
		int(level_config.get("level", 0)) <= 1
		or bool(level_config.get("is_daily", false))
		or not bool(level_config.get("is_daily_first_main_win", false))
		or not ABTestManager.daily_first_win_encourage.has_win_praise()
	):
		return existing_text
	var text_keys: Dictionary = ABTestManager.daily_first_win_encourage.pick_win_text_keys()
	var resolved_text: Dictionary = existing_text.duplicate()
	resolved_text["title"] = tr(text_keys["title_key"])
	resolved_text["body"] = _render_win_override_body(
		text_keys["body_key"], tr(text_keys["body_key"])
	)
	resolved_text["body_key"] = text_keys["body_key"]
	return resolved_text


func _setup_win_title() -> void:
	var override_title: String = _win_text.get("title", "")
	if not override_title.is_empty():
		_apply_title_text(override_title)
		return
	_apply_title_text(_pick_default_win_title())


func _apply_title_text(title_text: String) -> void:
	_title.text = title_text
	_title_up.text = title_text


func _pick_default_win_title() -> String:
	var lv: int = _level_config.get("level", 0)
	var key: StringName

	var _is_hard: bool = LevelSelector.is_hard_level(lv) or LevelSelector.is_super_hard_level(lv)
	if lv > 0 and _is_hard:
		key = &"WIN_TITLE_HARD"
	else:
		var pool := WIN_TITLES_NORMAL.filter(
			func(k: StringName) -> bool: return k != _last_win_title
		)
		key = pool[randi() % pool.size()]
	_last_win_title = key
	return tr(key)


func _setup_next_btn() -> void:
	if _level_config.get("is_daily", false):
		_next_btn.visible = false
		return
	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		_next_btn.visible = true
		var next_lv: int = _next_level_index()
		_next_btn.btn_text = _compute_next_btn_label()

		var next_is_super_hard: bool = LevelSelector.is_super_hard_level(next_lv)
		_next_btn.super_hard = next_is_super_hard
		_next_btn.show_difficult = next_is_super_hard or LevelSelector.is_hard_level(next_lv)
		_next_btn.hard_effect_variant = ABTestManager.hard_button.effect_variant()

		var next_is_golden: bool = _is_next_level_golden_fish()
		GoldenFishBtnStyle.apply(_next_btn, next_is_golden)

		ColorChallengeBtnStyle.apply(
			_next_btn, (not next_is_golden) and _is_next_level_color_challenge()
		)
	else:
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			_next_btn.visible = true
			_next_btn.show_difficult = false
			_next_btn.super_hard = false
			_next_btn.btn_text = _compute_next_btn_label()

			GoldenFishBtnStyle.apply(_next_btn, false)
			ColorChallengeBtnStyle.apply(_next_btn, false)
		else:
			_next_btn.visible = false


func _compute_next_btn_label() -> String:
	if _level_config.get("is_daily", false):
		return ""
	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		return tr("GAME_LEVEL_TITLE") % _next_level_index()
	var bp: Dictionary = _level_config.get("bank_params", {})
	if bp.is_empty():
		return ""
	var idx: int = bp.get("bank_index", 1)
	var total: int = bp.get("bank_total", 1)
	var next_idx: int = (idx % total) + 1
	return _bank_next_label(bp, next_idx)


## 本局带 beat_percent 时，额外加一行「耗时 · Top x%」统计
func _maybe_show_stats_label() -> void:
	# 没有 beat_percent（<0）就不显示
	var beat: float = _level_config.get("beat_percent", -1.0)
	if beat < 0.0:
		return
	var elapsed: int = _level_config.get("elapsed_sec", 0)
	var m: int = elapsed / 60
	var s: int = elapsed % 60
	# Top = 100 - 击败百分比，越小越好
	var top: float = snappedf(100.0 - beat, 0.1)

	_show_stats_label("⏱ %02d:%02d  ·  Top %s" % [m, s, I18nFormat.percent(top, 1)])


## 通关文案正文：非空才显示 BeatPercentLabel
func _maybe_show_beat_percent_tip() -> void:
	if _beat_percent_label == null:
		return
	# body 为空时整块隐藏，避免留白
	var text: String = _win_text.get("body", "")
	_beat_percent_label.visible = not text.is_empty()
	if not text.is_empty():
		_beat_percent_label.text = text


func _apply_g4_inline() -> void:
	if _g4_info == null:
		return
	if not (ABTestManager.pass_page.is_g4() and not _level_config.get("is_daily", false)):
		_g4_info.visible = false
		return
	_g4_time_key.text = tr("PASS_PAGE_TIME")
	_g4_score_key.text = tr("PASS_PAGE_SCORE")
	_g4_combo_key.text = tr("PASS_PAGE_COMBO")

	var elapsed: int = ceili(float(_level_config.get("elapsed_sec", 0.0)))
	var score: int = int(_level_config.get("final_score", 0))
	var combo: int = int(_level_config.get("max_combo", 0))

	_g4_time.text = _format_pp_time(0)
	_g4_score.text = _format_pp_score(0)
	_g4_combo.text = "0"
	_g4_info.visible = true
	_g4_info.modulate.a = 0.0

	if _g4_roll_tween != null and _g4_roll_tween.is_valid():
		_g4_roll_tween.kill()

	const _G4_ROLL_DELAY: float = 1.0
	const _G4_ROLL_DUR: float = 0.65
	_g4_roll_tween = create_tween().set_parallel(true)

	_g4_roll_tween.tween_property(_g4_info, "modulate:a", 1.0, 0.2).set_delay(_G4_ROLL_DELAY - 0.2)

	_g4_roll_tween.tween_method(_g4_roll_time, 0.0, float(elapsed), _G4_ROLL_DUR).set_delay(
		_G4_ROLL_DELAY
	)
	_g4_roll_tween.tween_method(_g4_roll_score, 0.0, float(score), _G4_ROLL_DUR).set_delay(
		_G4_ROLL_DELAY
	)
	_g4_roll_tween.tween_method(_g4_roll_combo, 0.0, float(combo), _G4_ROLL_DUR).set_delay(
		_G4_ROLL_DELAY
	)


func _g4_roll_time(f: float) -> void:
	if is_instance_valid(_g4_time):
		_g4_time.text = _format_pp_time(int(round(f)))


func _g4_roll_score(f: float) -> void:
	if is_instance_valid(_g4_score):
		_g4_score.text = _format_pp_score(int(round(f)))


func _g4_roll_combo(f: float) -> void:
	if is_instance_valid(_g4_combo):
		_g4_combo.text = "%d" % int(round(f))


func _format_pp_time(total_sec: int) -> String:
	total_sec = clampi(total_sec, 0, 24 * 3600 - 1)
	var h: int = total_sec / 3600
	var m: int = (total_sec % 3600) / 60
	var s: int = total_sec % 60
	if h > 0:
		return "%02d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]


func _format_pp_score(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	var cnt: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out


## 运行时造一个 Label 当统计条：延时 0.6 秒后淡入并上浮 10 像素
func _show_stats_label(text: String) -> void:
	# 直接 new 一个 Label，不依赖场景
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 白色 42 号字，宽度对齐「下一关」按钮
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl.modulate.a = 0.0
	lbl.size = Vector2(_next_btn.size.x, 70.0)
	lbl.position = Vector2(_next_btn.position.x, _next_btn.position.y - 100.0)
	_next_btn.get_parent().add_child(lbl)
	# 记下起点，动画里往上浮 10 像素
	var start_y: float = lbl.position.y
	var tw := lbl.create_tween()
	# 先等 0.6 秒，再并行做淡入与上浮
	tw.tween_interval(0.6)
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.4)
	tw.tween_property(lbl, "position:y", start_y - 10.0, 0.4).set_ease(Tween.EASE_OUT)


func _on_next_btn_pressed() -> void:
	var play_btn: String = Tracker.Btn.LEVEL_PLAY
	if _is_next_level_golden_fish():
		play_btn = Tracker.Btn.GOLDEN_FISH_PLAY
	elif _next_skip_is_color_challenge():
		play_btn = Tracker.Btn.COLOR_CHALLENGE_PLAY
	Tracker.track_btn_click(play_btn, self)
	VibrateManager.play_at(VibrateManager.Pos.WIN_NEXT_BTN)

	var now_ms: int = Time.get_ticks_msec()
	if now_ms < _next_logic_allowed_at_ms:
		print(
			(
				"[GameWinPage] Next logic cooldown: ignored, remaining_ms=%d"
				% (_next_logic_allowed_at_ms - now_ms)
			)
		)
		return
	_next_logic_allowed_at_ms = now_ms + NEXT_LOGIC_COOLDOWN_MS
	await _run_next_flow()


## 切关前先完成排行榜待奖与签到队列，再按需展示排行榜开场，最后进入下一关。
func _run_next_flow() -> void:
	if _companion_reward_sequence == _show_seq_id:
		return

	var main_lv: int = _level_config.get("level", 0)
	var is_main: bool = not _level_config.get("is_daily", false) and main_lv > 0
	if is_main:
		_complete_unawarded_rank_period(_show_seq_id)

		if not RankActivityManager.get_pending_reward().is_empty():
			RankActivityManager.claim_reward(false)
			await get_tree().process_frame
			await UIManager.await_hidden(UiName.AWARD)
			if not visible:
				return
		RankActivityManager.maybe_open(false)

	if not _level_config.get("is_daily", false) and ABTestManager.daily_streak.is_settle_reorder():
		await _run_streak_queue_after_next()
		if not is_showing():
			return

	if is_main and RankActivityManager.is_open_not_joined():
		await _run_rank_open_popup()
		if not visible:
			return
	_go_next_level()


func _run_streak_queue_after_next() -> void:
	if StreakManager.has_pending_revive_decision():
		await StreakReviveFlow.run(self)
	if not StreakManager.has_pending_show():
		return

	modulate.a = 0.0
	await StreakPage.open_after_win()


func _run_rank_open_popup() -> void:
	var seq: int = _show_seq_id
	var dlg: UIFrameWindow = UIManager.show_ui(UiName.RANK_ACTIVITY_OPEN_POPUP)
	if dlg == null:
		return

	await UIManager.await_hidden(UiName.RANK_ACTIVITY_OPEN_POPUP)

	RankActivityManager.confirm_participation()
	if seq != _show_seq_id:
		return
	if RankActivityManager.get_period_count() == 1 and ProfileService.is_identity_default():
		var profile: UIFrameWindow = UIManager.show_ui(
			UiName.PROFILE, {"from_rank_open_guide": true}
		)
		if profile != null:
			await UIManager.await_hidden(UiName.PROFILE)


func _next_level_index() -> int:
	var lv: int = int(_level_config.get("level", 0))
	if lv <= 0:
		return 0
	if _gf_skip_target > 0:
		return _gf_skip_target

	if not LevelKind.occupies_level_number(
		int(_level_config.get("kind", LevelKind.default_kind()))
	):
		return lv
	return lv + 1


func _go_next_level() -> void:
	if _level_config.get("is_daily", false):
		UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
		return
	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		UIManager.show_ui(UiName.GAME, {"level_index": _next_level_index()})
		return
	var bp: Dictionary = _level_config.get("bank_params", {})
	if bp.is_empty():
		UIManager.show_ui(UiName.GAME, {"level_index": 1})
		return
	var idx: int = bp.get("bank_index", 1)
	var total: int = bp.get("bank_total", 1)
	var next_idx: int = (idx % total) + 1
	_play_bank_level(bp, next_idx, total)


func _is_next_level_golden_fish() -> bool:
	if _level_config.get("is_daily", false):
		return false
	var lv: int = int(_level_config.get("level", 0))
	if lv <= 0:
		return false

	return GoldenFishGate.should_show_golden_style(
		_next_level_index(),
		GameState.get_available_golden_fish_pending(),
		ABTestManager.golden_fish_func.is_enabled(),
		ABTestManager.golden_fish_timing.unlock_min_level()
	)


func _should_show_golden_fish_skip() -> bool:
	return _is_next_level_golden_fish() or _is_next_level_color_challenge()


func _is_next_level_color_challenge() -> bool:
	if _level_config.get("is_daily", false):
		return false
	var lv: int = int(_level_config.get("level", 0))
	if lv <= 0:
		return false
	return ColorChallengeGate.should_show_style(
		_next_level_index(),
		GameState.get_color_challenge_pending(),
		ABTestManager.color_challenge_func.group_value()
	)


func _refresh_golden_fish_skip() -> void:
	_gf_skip_busy = false
	_gf_skip_target = 0

	if _gf_skip_timer != null and is_instance_valid(_gf_skip_timer):
		remove_timer(_gf_skip_timer)
	_gf_skip_timer = null
	if _gf_skip_link == null:
		return
	_gf_skip_link.visible = false

	_reset_gf_skip_layout()
	if not _should_show_golden_fish_skip():
		return
	_apply_gf_skip_gap()

	_gf_skip_link.text = (
		ColorChallengeBtnStyle.skip_text(_next_level_index())
		if _next_skip_is_color_challenge()
		else GoldenFishBtnStyle.skip_text(_next_level_index())
	)
	_gf_skip_timer = create_countdown(_GF_SKIP_DELAY, _show_golden_fish_skip_link)


func _reset_gf_skip_layout() -> void:
	_set_gf_skip_gap(_GF_GAP_BASE)
	_set_gf_top_pad(0)


func _apply_gf_skip_gap() -> void:
	var h: float = get_viewport_rect().size.y
	var t: float = clampf((h - _GF_H_SHORT) / (_GF_H_TALL - _GF_H_SHORT), 0.0, 1.0)

	var pad: int = roundi(lerpf(_GF_PAD_AT_SHORT, _GF_PAD_AT_TALL, t))

	var skip_gap: float = _GF_GAP_BASE + float(pad)
	if _safe_bottom_shift() > 0.0:
		skip_gap = _GF_GAP_BASE
	_set_gf_skip_gap(skip_gap)
	_set_gf_top_pad(pad)


func _apply_screen_adapt() -> void:
	if scene_file_path == _ADAPT_SKIN_V2_PATH:
		return
	var h: float = get_viewport_rect().size.y
	var t: float = clampf((h - _ADAPT_H_SHORT) / (_ADAPT_H_TALL - _ADAPT_H_SHORT), 0.0, 1.0)
	var rise: float = _ADAPT_RISE_SHORT * (1.0 - t)
	_apply_cat_rise(rise)
	_apply_text_block_rise(rise, t)


func _apply_cat_rise(rise: float) -> void:
	var ctrl: Node = get_node_or_null(^"Root/Ctrl")
	if ctrl == null:
		return
	for node_name: StringName in _ADAPT_CAT_NODES:
		var cat: Node2D = ctrl.get_node_or_null(NodePath(node_name)) as Node2D
		if cat == null:
			continue
		if not _adapt_cat_base_y.has(node_name):
			_adapt_cat_base_y[node_name] = cat.position.y
		cat.position.y = float(_adapt_cat_base_y[node_name]) - rise
	for node_name: StringName in _ADAPT_RAY_NODES:
		var ray: Control = ctrl.get_node_or_null(NodePath(node_name)) as Control
		if ray == null:
			continue
		if not _adapt_cat_base_y.has(node_name):
			_adapt_cat_base_y[node_name] = ray.position.y
		ray.position.y = float(_adapt_cat_base_y[node_name]) - rise


func _apply_text_block_rise(rise: float, t: float) -> void:
	var vbox: VBoxContainer = get_node_or_null(^"Root/Ctrl/VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	var budget: Control = vbox.get_node_or_null(NodePath(_ADAPT_BUDGET_NODE)) as Control
	if budget == null:
		push_error("GameWinPage: 缺 %s(短屏自适应失效)" % _ADAPT_BUDGET_NODE)
		return

	if _adapt_vbox_base_sep == _ADAPT_SEP_UNREAD:
		_adapt_vbox_base_sep = vbox.get_theme_constant(&"separation")
	var sep: int = roundi(lerpf(float(_ADAPT_VBOX_SEP_SHORT), float(_adapt_vbox_base_sep), t))
	vbox.add_theme_constant_override(&"separation", sep)
	budget.visible = rise > 0.0
	if not budget.visible:
		budget.custom_minimum_size.y = 0.0
		return
	var k: int = _visible_sibling_count(vbox, budget)
	var extra: float = (
		float(_adapt_vbox_base_sep) * float(k - 1) - float(sep) * float(k) + rise * 2.0
	)
	budget.custom_minimum_size.y = maxf(0.0, extra)


func _visible_sibling_count(vbox: VBoxContainer, budget: Control) -> int:
	var count: int = 0
	for child in vbox.get_children():
		var ctl: Control = child as Control
		if ctl == null or ctl == budget or not ctl.visible:
			continue
		count += 1
	return count


func _safe_bottom_shift() -> float:
	var vbox: Control = $Root/Ctrl/VBoxContainer as Control
	if vbox == null or not vbox.has_meta(&"_safe_bottom_baseline"):
		return 0.0
	var baseline: Vector2 = vbox.get_meta(&"_safe_bottom_baseline")
	return maxf(0.0, baseline.x - vbox.offset_top)


func _set_gf_top_pad(pad: int) -> void:
	var mc: MarginContainer = $Root/Ctrl/VBoxContainer/MarginContainer
	if mc == null:
		return
	if _gf_top_pad_base < 0.0:
		_gf_top_pad_base = mc.custom_minimum_size.y
	mc.custom_minimum_size.y = _gf_top_pad_base + float(pad)
	mc.add_theme_constant_override("margin_top", pad)


func _set_gf_skip_gap(top: float) -> void:
	var gap: Control = get_node_or_null("Root/Ctrl/VBoxContainer/GapBeforeSkip") as Control
	if gap == null:
		push_error("GameWinPage: 缺 GapBeforeSkip(Skip 上方间距失效)")
		return
	gap.custom_minimum_size.y = top


func _show_golden_fish_skip_link() -> void:
	_gf_skip_timer = null
	if _gf_skip_link == null or not is_showing() or not _should_show_golden_fish_skip():
		return
	_gf_skip_link.visible = true

	_apply_screen_adapt()


func _next_skip_is_color_challenge() -> bool:
	return _is_next_level_color_challenge() and not _is_next_level_golden_fish()


func _on_golden_fish_skip_pressed() -> void:
	if _gf_skip_busy:
		return

	if _gf_skip_link != null and _gf_skip_link.modulate.a < _GF_SKIP_READY_ALPHA:
		return
	_gf_skip_busy = true
	var next_lv: int = int(_level_config.get("level", 0)) + 1
	if _next_skip_is_color_challenge():
		Tracker.track_btn_click(Tracker.Btn.COLOR_CHALLENGE_SKIP, self)

		GameState.on_color_challenge_skipped(
			next_lv, ABTestManager.color_challenge_func.group_value(), false
		)
	else:
		Tracker.track_btn_click(Tracker.Btn.GOLDEN_FISH_SKIP, self)

		GameState.on_golden_fish_skipped(next_lv)
	_gf_skip_target = GameState.get_current_level()
	await _run_next_flow()


## 题库下一关的按钮文案：不同题库取不同字段拼「尺寸 / R / 序号」
func _bank_next_label(bp: Dictionary, next_idx: int) -> String:
	# SP 题库：尺寸要从关卡表里取
	if bp.get("bank_sp", false):
		var sp_levels: Array = BankData.get_sp_levels()
		# 序号在表内才写具体信息
		if next_idx - 1 < sp_levels.size():
			var e: Dictionary = sp_levels[next_idx - 1]
			var sz: int = e.get("size", 9)
			return "SP  %d×%d  #%d" % [sz, sz, next_idx]
	elif bp.get("bank_lk", false):
		# LK 题库：分「修改版」与普通两套表
		var lk_levels: Array = (
			BankData.get_lk_modified_levels()
			if bp.get("bank_lk_modified", false)
			else BankData.get_lk_levels()
		)
		# 表内有这一关就显示尺寸与最大 R
		if next_idx - 1 < lk_levels.size():
			var e: Dictionary = lk_levels[next_idx - 1]
			var sz: int = int(e.get("size", 8))
			var rank: int = int(e.get("maxR", 1))
			return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
	elif bp.get("bank_lk_style", false):
		# LK-style 题库：尺寸与 R 都在参数里
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
	else:
		# 其余题库同理
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
	# 索引越界或参数缺失时只显示序号
	return "#%d" % next_idx


func _play_bank_level(bp: Dictionary, next_idx: int, total: int) -> void:
	if bp.get("bank_sp", false):
		var levels: Array = BankData.get_sp_levels()
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = BankData.materialize_entry(levels[next_idx - 1])
		(
			UIManager
			. show_ui(
				UiName.GAME,
				{
					"bank_mode": true,
					"bank_size": entry.get("size", 9),
					"bank_rank": entry.get("r", 1),
					"bank_index": next_idx,
					"bank_total": total,
					"prebuilt_regions": entry.get("regionMap", []),
					"prebuilt_solution": entry.get("solution", []),
					"level_seed": entry.get("id", 0),
					"r1_steps": entry.get("r1", 0),
					"r2_steps": entry.get("r2", 0),
					"r3_steps": entry.get("r3", 0),
					"r4_steps": entry.get("r4", 0),
					"r5_steps": entry.get("r5", 0),
					"bank_sp": true,
					"custom_color_map": entry.get("colorMap", []),
				}
			)
		)
	elif bp.get("bank_lk", false):
		var is_lk_modified: bool = bp.get("bank_lk_modified", false)
		var levels: Array = (
			BankData.get_lk_modified_levels() if is_lk_modified else BankData.get_lk_levels()
		)
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = BankData.materialize_entry(levels[next_idx - 1])
		(
			UIManager
			. show_ui(
				UiName.GAME,
				{
					"bank_mode": true,
					"bank_lk": true,
					"bank_lk_modified": is_lk_modified,
					"bank_size": int(entry.get("size", 8)),
					"bank_rank": int(entry.get("maxR", 1)),
					"bank_index": next_idx,
					"bank_total": total,
					"prebuilt_regions": entry.get("regionMap", []),
					"prebuilt_solution": entry.get("solution", []),
					"level_seed": entry.get("id", 0),
				}
			)
		)
	elif bp.get("bank_lk_style", false):
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var is_tier_h: bool = bp.get("bank_tier_h", false)
		var levels: Array = (
			BankData.get_lk_style_levels_by_tier(sz, rank, "H")
			if is_tier_h
			else BankData.get_lk_style_levels(sz, rank)
		)
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = BankData.materialize_entry(levels[next_idx - 1])
		(
			UIManager
			. show_ui(
				UiName.GAME,
				{
					"bank_mode": true,
					"bank_size": sz,
					"bank_rank": rank,
					"bank_index": next_idx,
					"bank_total": total,
					"prebuilt_regions": entry.get("regionMap", []),
					"prebuilt_solution": entry.get("solution", []),
					"level_seed": entry.get("seed", 0),
					"r1_steps": entry.get("r1", 0),
					"r2_steps": entry.get("r2", 0),
					"r3_steps": entry.get("r3", 0),
					"r4_steps": entry.get("r4", 0),
					"r5_steps": entry.get("r5", 0),
					"bank_lk_style": true,
					"bank_tier_h": is_tier_h,
				}
			)
		)
	elif bp.get("bank_gc", false):
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var bank_tier: String = bp.get("bank_tier", "")
		var levels: Array = (
			BankData.get_gc_levels_by_tier(sz, rank, bank_tier)
			if (bank_tier == "H" or bank_tier == "N")
			else BankData.get_gc_levels(sz, rank)
		)
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = BankData.materialize_entry(levels[next_idx - 1])
		(
			UIManager
			. show_ui(
				UiName.GAME,
				{
					"bank_mode": true,
					"bank_size": sz,
					"bank_rank": rank,
					"bank_index": next_idx,
					"bank_total": total,
					"prebuilt_regions": entry.get("regionMap", []),
					"prebuilt_solution": entry.get("solution", []),
					"level_seed": entry.get("seed", 0),
					"r1_steps": entry.get("r1", 0),
					"r2_steps": entry.get("r2", 0),
					"r3_steps": entry.get("r3", 0),
					"r4_steps": entry.get("r4", 0),
					"r5_steps": entry.get("r5", 0),
					"bank_gc": true,
					"bank_tier": bank_tier,
					"bank_tier_h": bank_tier == "H",
				}
			)
		)
	else:
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var is_tier_h: bool = bp.get("bank_tier_h", false)
		var levels: Array = (
			BankData.get_levels_by_tier(sz, rank, "H")
			if is_tier_h
			else BankData.get_levels(sz, rank)
		)
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = BankData.materialize_entry(levels[next_idx - 1])
		(
			UIManager
			. show_ui(
				UiName.GAME,
				{
					"bank_mode": true,
					"bank_size": sz,
					"bank_rank": rank,
					"bank_index": next_idx,
					"bank_total": total,
					"prebuilt_regions": entry.get("regionMap", []),
					"prebuilt_solution": entry.get("solution", []),
					"level_seed": entry.get("seed", 0),
					"r1_steps": entry.get("r1", 0),
					"r2_steps": entry.get("r2", 0),
					"r3_steps": entry.get("r3", 0),
					"r4_steps": entry.get("r4", 0),
					"r5_steps": entry.get("r5", 0),
					"bank_tier_h": is_tier_h,
				}
			)
		)


func get_scr_name() -> String:
	if _is_golden_fish_level():
		return Tracker.Scr.GOLDEN_FISH_GAME_SUCCESS
	return Tracker.Scr.NORMAL_GAME_SUCCESS
