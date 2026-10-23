## 每日挑战胜利页：展示用时和成绩，衔接继续、重玩及挑战奖励流程。
class_name DailyWinPage
extends UIFrameWindow

signal replay_requested

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _time_label: RichTextLabel = $Root/Ctrl/TimeLabel # 本局耗时文案
@onready var _beat_label: RichTextLabel = $Root/Ctrl/BeatCenter/BeatLabel
@onready var _cat: SpineSprite = $Root/Ctrl/VictoryCat # 胜利猫（Spine 骨骼动画）
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面出现动画
@onready var _anim_loop: AnimationPlayer = $AnimationPlayer2 # 继续按钮的循环动画
@onready var _title_under: SingleLineGlyphLabel = $Root/Ctrl/TitleLabelUnder
@onready var _title_up: SingleLineGlyphLabel = $Root/Ctrl/TitleLabelUp

@onready var _replay_btn: Control = $Root/Ctrl/ReplayBtn

var _replay_busy: bool = false

var _continue_busy: bool = false

const _LEGACY_TITLE_STYLE: Dictionary = {
	"outline_thickness": 12,
	"outline_color": Color(0.8, 0.34901962, 0, 1),
}

var _title_style_cache: Dictionary = {}

## 通关动画的等待时长（秒）；主页 Toast 已经占掉这段时间时跳过
const APPEAR_DELAY: float = 0.8

const _DC_QUANT_BOARD: PackedScene = preload(
	"res://scripts/module/result/ui/dc_pass_page_board.tscn"
)
var _quant_board: DcPassPageBoard = null

## 游戏页传进来的本局配置（elapsed_sec / beat_percent 等）
var _level_config: Dictionary = {}


func _ready() -> void:
	bind_press_release_scale($Root/Ctrl/ContinueBtn)

	bind_press_release_scale($Root/Ctrl/ReplayBtn)


func on_show(params: Dictionary = {}) -> void:
	UIManager.block_input_briefly(self, 2.0)

	EndTitleArtStyle.apply(_title_under, _title_up, _title_style_cache, _LEGACY_TITLE_STYLE)
	show_win(params.get("level_config", {}), params.get("board_view") as BoardView)


func show_win(level_config: Dictionary, board_view: BoardView) -> void:
	_level_config = level_config
	visible = true

	_replay_busy = false

	_continue_busy = false

	if ABTestManager.dc_pass_page.is_quant_board():
		await _show_quant_board()
		return

	_restore_default_win_body()

	_apply_screen_adapt()

	_apply_replay_entry()

	var elapsed: int = level_config.get("elapsed_sec", 0)
	var m: int = elapsed / 60
	var s: int = elapsed % 60
	_time_label.text = ""
	(
		_time_label
		. append_text(
			(
				"[color=#fff1b9]%s [/color][color=#f19320][font_size=80][b]%02d:%02d[/b][/font_size][/color]"
				% [tr("DAILY_WIN_TIME"), m, s]
			)
		)
	)

	var beat: float = level_config.get("beat_percent", 50.0)
	var pct_text: String = I18nFormat.percent(beat, 1)
	var beat_str: String = tr("DAILY_WIN_BEAT") % pct_text
	var highlighted: String = (
		"[color=#02be52][font_size=90][b]%s[/b][/font_size][/color]" % pct_text
	)
	var beat_bbcode: String = (
		"[color=#ffe375]"
		+ beat_str.replace(pct_text, "[/color]" + highlighted + "[color=#ffe375]")
		+ "[/color]"
	)
	_beat_label.text = ""
	_beat_label.append_text(beat_bbcode)

	_reset_cat_spine()

	_anim.stop()
	_anim.play("Appear")
	_anim.advance(0.0)
	_anim.pause()

	if (
		not level_config.get("toast_was_shown", false)
		and not level_config.get("skip_appear_delay", false)
	):
		await get_tree().create_timer(APPEAR_DELAY).timeout
	SoundManager.play(SoundManager.Kind.LEVEL_WIN)
	_resume_cat_spine()
	_anim.play("Appear")

	_anim.advance(0.0)
	AnimUtil.commit_nested(_anim)
	_anim.queue("Loop")
	_anim_loop.play("ContinueLoop")


const _ADAPT_H_SHORT: float = 1920.0
const _ADAPT_H_TALL: float = 2400.0

const _ADAPT_RISE_SHORT: float = 65.0

const _ADAPT_BTN_EXTRA_SHORT: float = 20.0

var _adapt_base_offsets: Dictionary = {}


func _apply_screen_adapt() -> void:
	var h: float = get_viewport_rect().size.y
	var t: float = clampf((h - _ADAPT_H_SHORT) / (_ADAPT_H_TALL - _ADAPT_H_SHORT), 0.0, 1.0)
	var rise: float = _ADAPT_RISE_SHORT * (1.0 - t)
	_shift_by(get_node_or_null(^"Root/Ctrl") as Control, -rise)

	_shift_by(_title_up, rise)
	_shift_by(_title_under, rise)

	var btn_extra: float = -_ADAPT_BTN_EXTRA_SHORT * (1.0 - t)
	_shift_by(get_node_or_null(^"Root/Ctrl/ContinueBtn") as Control, btn_extra)
	_shift_by(_replay_btn, btn_extra)


func _apply_replay_entry() -> void:
	_replay_btn.visible = DailyEntryState.can_replay_today()


func _shift_by(node: Control, delta: float) -> void:
	if node == null:
		return
	if not _adapt_base_offsets.has(node.name):
		_adapt_base_offsets[node.name] = Vector2(node.offset_top, node.offset_bottom)
	var base: Vector2 = _adapt_base_offsets[node.name]
	node.offset_top = base.x + delta
	node.offset_bottom = base.y + delta


func _show_quant_board() -> void:
	if _anim != null:
		_anim.stop()
	if _anim_loop != null:
		_anim_loop.stop()
	_hide_default_win_body()

	$Root.modulate = Color(1, 1, 1, 1)
	if _quant_board == null:
		_quant_board = _DC_QUANT_BOARD.instantiate() as DcPassPageBoard
		$Root.add_child(_quant_board)

		_quant_board.next_pressed.connect(_on_continue_btn_pressed)

		_quant_board.replay_pressed.connect(_on_replay_btn_pressed)

	_quant_board.visible = false

	_quant_board.set_replay_available(DailyEntryState.can_replay_today())
	(
		_quant_board
		. populate(
			tr("DAILY_WIN_TITLE"),
			"",
			tr("WIN_CONTINUE"),
			false,
			{
				"elapsed_sec": _level_config.get("elapsed_sec", 0),
				"beat_percent": _level_config.get("beat_percent", 0.0),
				"final_score": _level_config.get("final_score", 0),
				"max_combo": _level_config.get("max_combo", 0),
			}
		)
	)
	if (
		not _level_config.get("toast_was_shown", false)
		and not _level_config.get("skip_appear_delay", false)
	):
		await get_tree().create_timer(APPEAR_DELAY).timeout

		if not is_showing():
			return
	SoundManager.play(SoundManager.Kind.PASS_PAGE_SETTLE)
	_quant_board.show_and_play_appear()


func _hide_default_win_body() -> void:
	for n: Node in [
		$Root/Overlay,
		$Root/Ctrl/TitleLabelUnder,
		$Root/Ctrl/TitleLabelUp,
		_time_label,
		_beat_label,
		_cat,
		$Root/Ctrl/VictoryCatGlow,
		$Root/Ctrl/EffectRayLight,
		$Root/Ctrl/EffectFlreworks,
		$Root/Ctrl/ContinueBtn,
		_replay_btn,
	]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = false


func _restore_default_win_body() -> void:
	if _quant_board == null:
		return
	_quant_board.visible = false

	for n: Node in [
		$Root/Overlay,
		_title_up,
		_time_label,
		_beat_label,
		$Root/Ctrl/VictoryCatGlow,
		$Root/Ctrl/EffectFlreworks,
		$Root/Ctrl/ContinueBtn,
	]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = true

	EndTitleArtStyle.apply(_title_under, _title_up, _title_style_cache, _LEGACY_TITLE_STYLE)

	for n: Node in [_cat, $Root/Ctrl/EffectRayLight]:
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = false


# ================= 猫 Spine 控制 =================
## 离开页面把猫复位，免得下次进来停在半路
func on_hide() -> void:
	_reset_cat_spine()


func _reset_cat_spine() -> void:
	if _cat == null:
		return
	var st := _cat.get_animation_state()
	if st != null:
		st.set_animation("appear", false, 0)
		st.set_time_scale(0.0)


## 恢复猫的时间缩放，让它真正动起来
func _resume_cat_spine() -> void:
	if _cat == null:
		return
	var st := _cat.get_animation_state()
	if st != null:
		st.set_time_scale(1.0)


func _on_continue_btn_pressed() -> void:
	if _continue_busy:
		return
	_continue_busy = true
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)

	if ABTestManager.daily_streak.is_settle_reorder():
		await _run_streak_queue_after_next()
		if not is_showing():
			return

	(
		UIManager
		. show_ui(
			UiName.GAME,
			{
				"level_index": GameState.get_current_level(),
				"_tracker_status": Tracker.GameStatus.CONTINUE,
			}
		)
	)
	UIManager.hide_ui(UiName.DAILY_WIN)
	UIManager.hide_ui(UiName.DAILY_GAME)


func _on_replay_btn_pressed() -> void:
	if _replay_busy:
		return

	if not DailyEntryState.can_replay_today():
		return
	_replay_busy = true

	await DcReplayFlow.start_ad_replay(self, _on_replay_ad_passed)
	_replay_busy = false


func _on_replay_ad_passed() -> void:
	if replay_requested.get_connections().is_empty():
		push_error("DailyWinPage: replay_requested 无接收方,玩家看完重玩广告却不会开新一局")
	replay_requested.emit()


func _run_streak_queue_after_next() -> void:
	if StreakManager.has_pending_revive_decision():
		await StreakReviveFlow.run(self)
	if not StreakManager.has_pending_show():
		return
	await StreakPage.open_after_win()


## 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME_SUCCESS
