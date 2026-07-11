class_name DailyWinPage
extends UIFrameWindow

@onready var _time_label: RichTextLabel = $Root/Ctrl/TimeLabel
@onready var _beat_label: RichTextLabel = $Root/Ctrl/BeatLabel
@onready var _cat: SpineSprite = $Root/Ctrl/VictoryCat
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _anim_loop: AnimationPlayer = $AnimationPlayer2

const APPEAR_DELAY: float = 0.8

var _level_config: Dictionary = {}


func _ready() -> void:
	bind_press_release_scale($Root/Ctrl/ContinueBtn)


func on_show(params: Dictionary = {}) -> void:
	UIManager.block_input_briefly(self, 2.0)
	show_win(params.get("level_config", {}), params.get("board_view") as BoardView)


func show_win(level_config: Dictionary, board_view: BoardView) -> void:
	_level_config = level_config
	visible = true

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
	_cat.update_skeleton(0.0)
	_anim.queue("Loop")
	_anim_loop.play("ContinueLoop")


func on_hide() -> void:
	_reset_cat_spine()


func _reset_cat_spine() -> void:
	if _cat == null:
		return
	_cat.visible = true
	var st := _cat.get_animation_state()
	if st != null:
		st.set_animation("appear", false, 0)
		st.set_time_scale(0.0)
	_cat.update_skeleton(0.0)
	_cat.visible = false


func _resume_cat_spine() -> void:
	if _cat == null:
		return
	var st := _cat.get_animation_state()
	if st != null:
		st.set_time_scale(1.0)


func _on_continue_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)
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


func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME_SUCCESS
