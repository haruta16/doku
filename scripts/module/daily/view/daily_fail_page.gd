# 每日挑战失败页：显示还差几只猫，给「免费/看广告复活」和「重开一局」两条路
class_name DailyFailPage
extends UIFrameWindow

# ---- 信号（由 DailyGamePage 连接） ----
signal revive_requested # 复活已生效，请游戏页把棋盘恢复正常

signal revive_ad_started # 广告即将播放，先让棋盘上的猫回位

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _root: Control = $Root # 整页根节点，用于复位整体透明度
@onready var _count_num: Label = $Root/BottomGroup/CatCountRow/CountNum # 还差几只猫的数字

@onready var _encourage_label: RichTextLabel = $Root/BottomGroup/VBoxContainer/EncourageLabel # 底部鼓励 / 复活推广文案
@onready var _revive_btn: Control = $Root/BottomGroup/VBoxContainer/ReviveBtn # 复活按钮
@onready var _try_again_btn: Control = $Root/BottomGroup/VBoxContainer/TryAgainBtn # 重开按钮
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面进出场动画
# 复活按钮上的广告图标
@onready
var _revive_ad_icon: TextureRect = $Root/BottomGroup/VBoxContainer/ReviveBtn/Root/TextIconRow/Icon
@onready var _revive_badge: GameAdBadge = $Root/BottomGroup/VBoxContainer/ReviveBtn/Root/Badge # 复活按钮上的角标（免费 / AD）

# 图标+文字行；两行文案时整行上移
@onready
var _revive_text_icon_row: HBoxContainer = $Root/BottomGroup/VBoxContainer/ReviveBtn/Root/TextIconRow
# 复活按钮主文案
@onready
var _revive_main_label: Label = $Root/BottomGroup/VBoxContainer/ReviveBtn/Root/TextIconRow/Label
@onready var _revive_subtitle: Label = $Root/BottomGroup/VBoxContainer/ReviveBtn/Root/SubtitleLabel # 复活按钮副标题（两行样式才显示）

# ---- 布局常量（像素 / 字号），用于按钮文案自适应 ----
const _REVIVE_TWO_LINE_OFFSET: float = -20.0 # 两行文案时整行上移的像素（负值 = 往上）

const _REVIVE_ROW_MAX_WIDTH: float = 705.0 # 图标行可用最大宽度
const _REVIVE_ROW_ICON_WIDTH: float = 100.0 # 广告图标占用的宽度
const _REVIVE_ROW_SEPARATION: float = 24.0 # 图标与文字之间的间距
const _REVIVE_MAIN_FONT_SIZE_BASE: int = 88 # 主文案基准字号
const _REVIVE_MAIN_FONT_SIZE_MIN: int = 40 # 缩放后允许的最小字号

# ---- 运行时状态 ----
var _revive_row_init_top: float = 0.0 # 图标行在场景里的初始上边距
var _revive_row_init_bottom: float = 0.0 # 图标行在场景里的初始下边距

var _encourage_fade_tween: Tween = null # 鼓励文案淡入用的 Tween


# ================= 生命周期 =================
# 记下图标行的初始位置，并刷一遍随语言变化的排版
func _ready() -> void:
	_revive_row_init_top = _revive_text_icon_row.offset_top
	_revive_row_init_bottom = _revive_text_icon_row.offset_bottom
	_refresh_dynamic_text()


# 切换语言后要重新排版（按钮字号是量出来的）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


# ================= 文案与自适应 =================
# 按 AB 实验决定按钮文案（普通 / 3 条命）与是否两行，然后重排
func _refresh_dynamic_text() -> void:
	var main_key: String = (
		"FAIL_REVIVE_3FISH" if ABTestManager.revive_life.is_alt_button_text() else "FAIL_REVIVE"
	)
	_revive_main_label.text = tr(main_key)
	var two_line: bool = ABTestManager.revive_life.is_two_line_button()
	_revive_subtitle.visible = two_line
	if two_line:
		_revive_text_icon_row.offset_top = _revive_row_init_top + _REVIVE_TWO_LINE_OFFSET
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom + _REVIVE_TWO_LINE_OFFSET
		_revive_subtitle.text = tr("FAIL_REVIVE_SUBTITLE_3FISH")
	else:
		_revive_text_icon_row.offset_top = _revive_row_init_top
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom
	_fit_main_label_width()


# 主文案超宽就按可用宽度等比缩小字号（用同一个字体量宽度）
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


# ================= 失败展示 =================
# 暂停 BGM，从参数里取关卡配置与剩余猫数
func on_show(params: Dictionary = {}) -> void:
	SoundManager.set_bgm_paused(true)
	var lc: Dictionary = params.get("level_config", {})
	var rc: int = params.get("remaining_cats", 0)
	show_fail(lc, rc)


# 显示失败：填剩余猫数、决定复活按钮能否用、刷文案并播动画
func show_fail(level_config: Dictionary, remaining_cats: int = 0) -> void:
	visible = true
	_root.modulate = Color(1, 1, 1, 1)
	_count_num.text = str(remaining_cats)

	_refresh_dynamic_text()

	# 免费复活直接给按钮；否则要广告就绪才显示
	var free: bool = _is_free_revive()
	_revive_btn.visible = (
		true if free else UniKitManager.is_reward_valid("reward", Tracker.AdPos.DAILY_GAME_FAIL)
	)
	# 合规要求挂 AD 角标时用角标，否则免费标与广告图标二选一
	var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()
	if ad_tag:
		_revive_ad_icon.visible = false
		_revive_badge.visible = not free
		_revive_badge.show_icon_with_ad()
		_revive_badge.scale = Vector2.ONE
	else:
		_revive_ad_icon.visible = not free
		_revive_badge.visible = free
		_revive_badge.show_free()
		_revive_badge.scale = Vector2.ONE * 1.4

	_fit_main_label_width()
	_refresh_encourage_label(level_config, remaining_cats)
	# 失败音效按实验分档（低音量 / 普通）
	if ABTestManager.wrong_cat_effect.should_lower_fail_volume():
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL_LOW)
	else:
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL)

	# 两套出场动画按生命图标样式选（鱼形生命条走 group1）
	var group1: bool = ABTestManager.life_icon.is_fish_life_bar()
	_anim.stop()

	# 先 RESET 再播出现，保证每次都从同一帧开始
	_anim.play("RESET")
	_anim.advance(0.0)

	# Spine 猫先复位到 in 第 0 帧，再恢复时间缩放正式播
	_reset_fail_cat_spines()
	_resume_fail_cat_spines()
	_anim.play("appear_group1" if group1 else "appear")

	# 出现播完接 idle 循环
	_anim.advance(0.0)
	_anim.queue("idle_group1" if group1 else "idle")


# ================= 猫 Spine 控制 =================
# 把两只失败猫停在 in 第 0 帧并隐藏，作为「还没出场」状态
func _reset_fail_cat_spines() -> void:
	for sp: SpineSprite in [$Root/SpineSprite, $Root/SpineSprite2]:
		if sp == null:
			continue
		sp.visible = true
		var st := sp.get_animation_state()
		if st != null:
			st.set_animation("in", false, 0)
			st.set_time_scale(0.0)
		sp.update_skeleton(0.0)
		sp.visible = false


# 恢复两只猫的时间缩放，让动画真正跑起来
func _resume_fail_cat_spines() -> void:
	for sp: SpineSprite in [$Root/SpineSprite, $Root/SpineSprite2]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


# ================= 鼓励文案 =================
# 先杀掉上一次的淡入 Tween，再按实验选复活推广或普通鼓励
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


# ================= 离场 =================
# 恢复 BGM、断开广告回调，播完退场动画再隐藏
func on_hide() -> void:
	SoundManager.set_bgm_paused(false)
	_disconnect_self_reward_callbacks()
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	_anim.stop()
	_anim.play("disappear")
	await _anim.animation_finished

	_reset_fail_cat_spines()
	visible = false


# ================= 复活与重开 =================
# 是否免费复活：调试强制 / 等级还没到要看广告 / 实验判定免费
func _is_free_revive() -> bool:
	if BaseGamePage.debug_force_free_tool == "all":
		return true
	if not ABTestManager.reward_unlock_level.is_reward_required_at(GameState.get_current_level()):
		return true
	return ABTestManager.revive_free_logic.should_free_revive()


# 复活按钮：免费直接复原；否则校验广告就绪后拉激励视频，看完才发 revive_requested
func _on_revive_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.REVIVE, self)

	if _is_free_revive():
		ABTestManager.revive_free_logic.consume_if_needed()
		revive_ad_started.emit()
		revive_requested.emit()
		return
	# 广告位固定为「每日挑战失败页」
	var pos: String = Tracker.AdPos.DAILY_GAME_FAIL

	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", pos, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	# 只有看完广告才算复活：发信号让游戏页恢复棋盘
	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		revive_requested.emit()
	# 广告中途关闭不发奖励，什么都不做
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

	# 先清掉自己上次挂上的回调，避免重复触发
	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)

	revive_ad_started.emit()
	UniKitManager.show_reward("reward", pos, show_id)


# 遍历两个广告信号，只断开 callable 属于本节点的连接
func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


# 重开：走 LevelOps 的重开流程，并以 RESTART 状态重进每日页
func _on_try_again_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)

	LevelOps.on_restart_click()
	UIManager.show_ui(UiName.DAILY_GAME, {"_tracker_status": Tracker.GameStatus.RESTART})


# 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME_FAIL
