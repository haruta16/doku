# 每日挑战通关页：展示本局耗时与「超越百分比」，继续按钮回主线接着闯关
class_name DailyWinPage
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _time_label: RichTextLabel = $Root/Ctrl/TimeLabel # 本局耗时文案
@onready var _beat_label: RichTextLabel = $Root/Ctrl/BeatLabel # 超越百分比文案
@onready var _cat: SpineSprite = $Root/Ctrl/VictoryCat # 胜利猫（Spine 骨骼动画）
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面出现动画
@onready var _anim_loop: AnimationPlayer = $AnimationPlayer2 # 继续按钮的循环动画

# 通关动画的等待时长（秒）；主页 Toast 已经占掉这段时间时跳过
const APPEAR_DELAY: float = 0.8

# 游戏页传进来的本局配置（elapsed_sec / beat_percent 等）
var _level_config: Dictionary = {}


# ================= 生命周期 =================
# 给继续按钮接上按下/抬起缩放
func _ready() -> void:
	bind_press_release_scale($Root/Ctrl/ContinueBtn)


# 进页面先挡 2 秒输入防误触，再演通关结算
func on_show(params: Dictionary = {}) -> void:
	UIManager.block_input_briefly(self, 2.0)
	show_win(params.get("level_config", {}), params.get("board_view") as BoardView)


# 填耗时与百分比文案，然后播猫的胜利动画
func show_win(level_config: Dictionary, board_view: BoardView) -> void:
	_level_config = level_config
	visible = true

	# 耗时拆成 mm:ss；文本带 BBCode，所以拼好色再 append
	var elapsed: int = level_config.get("elapsed_sec", 0)
	var m: int = elapsed / 60
	var s: int = elapsed % 60
	# 先清空再 append_text，避免重复追加
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

	# beat_percent 由 DailyStats 按耗时算好，这里只负责把数字高亮放大
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
	# 把百分比数字从整句里抠出来染色放大，再拼回原句
	_beat_label.text = ""
	_beat_label.append_text(beat_bbcode)

	# 猫先复位到动画第一帧（下面会暂停，等延迟结束再放开）
	_reset_cat_spine()

	_anim.stop()
	_anim.play("Appear")
	_anim.advance(0.0)
	_anim.pause()

	# 主页 Toast 已展示过、或打卡流程占用了这段延迟时，就不再等
	if (
		not level_config.get("toast_was_shown", false)
		and not level_config.get("skip_appear_delay", false)
	):
		await get_tree().create_timer(APPEAR_DELAY).timeout
	SoundManager.play(SoundManager.Kind.LEVEL_WIN)
	_resume_cat_spine()
	_anim.play("Appear")

	# 出现动画放完接上循环待机
	_anim.advance(0.0)
	_cat.update_skeleton(0.0)
	_anim.queue("Loop")
	_anim_loop.play("ContinueLoop")


# ================= 猫 Spine 控制 =================
# 离开页面把猫复位，免得下次进来停在半路
func on_hide() -> void:
	_reset_cat_spine()


# 把猫停在 appear 第 0 帧并隐藏，作为「还没开始」的状态
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


# 恢复猫的时间缩放，让它真正动起来
func _resume_cat_spine() -> void:
	if _cat == null:
		return
	var st := _cat.get_animation_state()
	if st != null:
		st.set_time_scale(1.0)


# ================= 按钮 =================
# 继续：带 CONTINUE 埋点状态回主线下一关，并关掉每日两个页面
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


# 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME_SUCCESS
