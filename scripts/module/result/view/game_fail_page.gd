# 失败弹窗：显示剩余空格、鼓励 / 复活推广文案，负责复活（免费或看广告）与重开
class_name GameFailPage
extends UIFrameWindow

# 复活条件已就绪（免费名额或广告已发奖）时发出，GamePage 收到后真正复活
signal revive_requested

# 复活流程开始（免费或广告都已拉起）时发出，GamePage 先把棋盘上的猫复位
signal revive_ad_started

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _title_label: CurveLabel = $Root/title/TitleLabel # 顶部标题
@onready var _count_num: Label = $Root/Ctrl/CatCountRow/CountNum # 剩余空格数

@onready var _encourage_label: RichTextLabel = $Root/Ctrl/VBoxContainer/EncourageLabel # 鼓励语 / 复活推广文案
@onready var _revive_btn: Control = $Root/Ctrl/VBoxContainer/ReviveBtn # 复活按钮
@onready var _restart_btn: Control = $Root/Ctrl/VBoxContainer/RestartBtn # 重开按钮
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗动画（appear / idle / disappear）
@onready var _revive_ad_icon: TextureRect = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow/Icon # 复活按钮里的广告图标
@onready var _revive_badge: GameAdBadge = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/Badge # 复活按钮上的角标（AD / FREE）

@onready
var _revive_text_icon_row: HBoxContainer = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow # 复活按钮里的「文字 + 图标」行
@onready var _revive_main_label: Label = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow/Label # 复活按钮主文案
@onready var _revive_subtitle: Label = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/SubtitleLabel # 复活按钮副标题（两行样式才显示）

# 两行按钮时，文字行整体上移的像素数
const _REVIVE_TWO_LINE_OFFSET: float = -20.0

# ---- 复活主文案的自适应宽度参数（像素） ----
const _REVIVE_ROW_MAX_WIDTH: float = 705.0 # 可用最大宽度
const _REVIVE_ROW_ICON_WIDTH: float = 100.0 # 广告图标占位宽
const _REVIVE_ROW_SEPARATION: float = 24.0 # 图标与文字间距
const _REVIVE_MAIN_FONT_SIZE_BASE: int = 88 # 基准字号
const _REVIVE_MAIN_FONT_SIZE_MIN: int = 40 # 缩放下限字号

# ---- 运行时状态 ----
var _revive_row_init_top: float = 0.0 # 文字行原始 offset_top（切回一行时还原用）
var _revive_row_init_bottom: float = 0.0 # 文字行原始 offset_bottom

var _level_config: Dictionary = {} # 本局关卡参数（GamePage 传入）
var _retry_params: Dictionary = {} # 重开时原样回传给 GamePage 的参数

var _encourage_fade_tween: Tween = null # 鼓励文案的淡入 tween，刷新时先 kill


# ================= 生命周期 =================
func _ready() -> void:
	# 记下文字行的初始偏移，供一行 / 两行切换时还原
	_revive_row_init_top = _revive_text_icon_row.offset_top
	_revive_row_init_bottom = _revive_text_icon_row.offset_bottom
	# 按当前 AB 分组刷新标题与按钮文案
	_refresh_dynamic_text()


# 语言切换后重新取文案（多处按语言 / 分组分支）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


# 刷新标题与复活按钮文案：鱼生命条、三鱼按钮等 AB 分支都在这里落地
func _refresh_dynamic_text() -> void:
	# 标题：鱼形生命条分组用另一套文案
	var key: String = (
		"FAIL_TITLE_FISH" if ABTestManager.life_icon.is_fish_life_bar() else "FAIL_TITLE"
	)
	_title_label.text = tr(key)

	# 主文案：三鱼按钮分组用另一套
	var main_key: String = (
		"FAIL_REVIVE_3FISH" if ABTestManager.revive_life.is_alt_button_text() else "FAIL_REVIVE"
	)
	_revive_main_label.text = tr(main_key)
	# 两行样式还要显示副标题，并把文字行整体上移
	var two_line: bool = ABTestManager.revive_life.is_two_line_button()
	_revive_subtitle.visible = two_line
	if two_line:
		# 三鱼按钮的副标题
		_revive_text_icon_row.offset_top = _revive_row_init_top + _REVIVE_TWO_LINE_OFFSET
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom + _REVIVE_TWO_LINE_OFFSET
		_revive_subtitle.text = tr("FAIL_REVIVE_SUBTITLE_3FISH")
	else:
		# 一行样式：还原原始偏移
		_revive_text_icon_row.offset_top = _revive_row_init_top
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom
	# 两行样式字更长，重新算一次字号
	_fit_main_label_width()


# 让主文案在可用宽度内不溢出：按测量结果等比缩字号，但不小于下限
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


# 打开失败页：暂停 BGM、遮输入 1.5 秒，然后按参数铺界面
func on_show(params: Dictionary = {}) -> void:
	# 失败页暂停背景音乐
	SoundManager.set_bgm_paused(true)

	# 动画期间先挡住输入
	UIManager.block_input_briefly(self, 1.5)
	# GamePage 传入：本局配置 / 重开参数 / 剩余空格数
	var lc: Dictionary = params.get("level_config", {})
	var rp: Dictionary = params.get("retry_params", {})
	var rc: int = params.get("remaining_cats", 0)
	show_fail(lc, rp, rc)


# 关闭：恢复 BGM、断广告回调、播消失动画后复位猫
func on_hide() -> void:
	# 恢复背景音乐
	SoundManager.set_bgm_paused(false)
	# 断开本页挂上去的广告回调，免得串页
	_disconnect_self_reward_callbacks()
	# 鼓励文案的淡入 tween 也要停
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	# 先 stop 再 play，保证从第 0 帧开始
	_anim.stop()
	_anim.play("disappear")
	await _anim.animation_finished

	# 复位两只失败猫的骨骼
	_reset_fail_cat_spines()
	visible = false


# 铺失败界面：剩余数、标题、复活按钮形态、鼓励文案、动画分组
func show_fail(
	level_config: Dictionary, retry_params: Dictionary = {}, remaining_cats: int = 0
) -> void:
	# 记下参数，后面刷新文案与重开都要用
	_level_config = level_config
	_retry_params = retry_params
	# 剩余空格数直接显示
	_count_num.text = str(remaining_cats)
	# 语言 / AB 相关文案统一在这里刷新
	_refresh_dynamic_text()
	# 每日关与普通关的广告位不同
	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)

	# 免费复活无条件显示按钮；否则要求该广告位能发奖
	var free: bool = _is_free_revive()
	_revive_btn.visible = true if free else UniKitManager.is_reward_valid("reward", pos)

	# 按钮角标三态：合规角标 / 纯广告图标 / FREE
	var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()
	if not free:
		# 需要展示合规角标时用 AD 角标
		if ad_tag:
			_revive_ad_icon.visible = false
			_revive_badge.visible = true
			_revive_badge.show_icon_with_ad()
			_revive_badge.scale = Vector2.ONE
		else:
			# 否则退回纯广告图标
			_revive_ad_icon.visible = true
			_revive_badge.visible = false
	else:
		# 免费复活：换成 FREE 角标并放大
		_revive_ad_icon.visible = false
		_revive_badge.visible = true
		_revive_badge.show_free()
		_revive_badge.scale = Vector2.ONE * 1.4

	# 按钮文案定稿后再量一次宽度
	_fit_main_label_width()
	# 鼓励语 / 复活推广文案
	_refresh_encourage_label(remaining_cats)
	visible = true
	# 失败音效分高低音量两档
	if ABTestManager.wrong_cat_effect.should_lower_fail_volume():
		# 低音量版
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL_LOW)
	else:
		# 标准版
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL)

	# 鱼形生命条分组用另一套动画
	var group1: bool = ABTestManager.life_icon.is_fish_life_bar()
	_anim.stop()

	# 先 RESET 再从头播
	_anim.play("RESET")
	_anim.advance(0.0)

	# 先定格再恢复播放（与通关页同一套做法）
	_reset_fail_cat_spines()
	_resume_fail_cat_spines()
	# 按分组播出现动画
	_anim.play("appear_group1" if group1 else "appear")

	_anim.advance(0.0)
	# 出现动画播完自动接 idle
	_anim.queue("idle_group1" if group1 else "idle")


# 复位两只失败猫：回到 in 第 0 帧并暂停，随后隐藏
func _reset_fail_cat_spines() -> void:
	# 两只失败猫都处理
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


# 恢复两只失败猫的骨骼播放
func _resume_fail_cat_spines() -> void:
	for sp: SpineSprite in [$Root/SpineSprite, $Root/SpineSprite2]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


# 是否走免费复活：调试开关 → 该关是否已需要道具 → AB 分组判定
func _is_free_revive() -> bool:
	# 调试：强制所有工具免费
	if BaseGamePage.debug_force_free_tool == "all":
		return true
	# 还没到「必须用道具」的关卡，复活本就免费
	if not ABTestManager.reward_unlock_level.is_reward_required_at(GameState.get_current_level()):
		return true
	return ABTestManager.revive_free_logic.should_free_revive()


# 铺鼓励文案：按 AB 分组决定用「复活推广」还是「完成度鼓励」，两者都淡入
func _refresh_encourage_label(remaining_cats: int) -> void:
	# 重刷前先停掉上一次的淡入
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	# 分组没开鼓励文案就整块隐藏
	if not ABTestManager.fail_text.should_show_encourage():
		_encourage_label.visible = false
		return
	# 关卡号与盘面尺寸（配置缺尺寸时按关卡查表）
	var level: int = int(_level_config.get("level", 1))
	var sz: int = int(_level_config.get("size", LevelData.get_size(level)))
	# 两个分支的淡入延迟不同，时长一致
	var delay: float
	var fade_dur: float
	# 复活推广：本关的百分比只抽一次，抽到就缓存复用
	if ABTestManager.fail_text.should_show_revive_promote() and _revive_btn.visible:
		var x: float = GameState.get_fail_text_revive_x(level)
		# 首次进入本关：抽一个并缓存（只存内存）
		if x < 0.0:
			var is_daily: bool = _level_config.get("is_daily", false)
			x = FailTextStats.pick_revive_promote_x(level, sz, is_daily)
			GameState.set_fail_text_revive_x(level, x)
		# 文案模板见 FAIL_REVIVE_PROMOTE
		_encourage_label.text = FailTextStats.format_revive_promote(x)
		delay = 0.8166
		fade_dur = 0.35
	else:
		# 普通鼓励：完成度 = 已放猫数 / 总格数
		var found_ratio: float = 0.0 if sz <= 0 else float(sz - remaining_cats) / float(sz)
		_encourage_label.text = FailTextStats.pick_encourage_text(found_ratio)
		delay = 0.9833
		fade_dur = 0.35

	# 统一从全透明淡入
	_encourage_label.visible = true
	_encourage_label.modulate = Color(1, 1, 1, 0)
	_encourage_fade_tween = create_tween()
	_encourage_fade_tween.tween_interval(delay)
	_encourage_fade_tween.tween_property(_encourage_label, "modulate:a", 1.0, fade_dur)


# 点复活：免费直接走，否则看激励视频，广告发奖后才发 revive_requested
func _on_revive_btn_pressed() -> void:
	# 埋点：复活按钮
	Tracker.track_btn_click(Tracker.Btn.REVIVE, self)

	# 免费复活：消耗免费名额并立刻请求复活
	if _is_free_revive():
		ABTestManager.revive_free_logic.consume_if_needed()
		revive_ad_started.emit()
		revive_requested.emit()
		return

	# 广告位与 show_fail 里保持一致
	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)

	# 先问广告是否就绪，没就绪给 toast
	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", pos, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	# 回调先写好：只有 reward 位发奖才算复活
	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		revive_requested.emit()
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

	# 清掉本页可能残留的广告回调
	_disconnect_self_reward_callbacks()
	# 只监听一次，避免下次打开时重复复活
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)

	# 通知 GamePage：广告要开始了（先把棋盘复位）
	revive_ad_started.emit()
	UniKitManager.show_reward("reward", pos, show_id)


# 只断开「回调对象是本页」的广告连接，不动其它页面的监听
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


# 点重开：通知 LevelOps 计数，然后按每日 / 普通各自重开本局
func _on_restart_btn_pressed() -> void:
	# 埋点：重开按钮
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)

	# 统一的「重开」副作用（计数 / 埋点）
	LevelOps.on_restart_click()
	# 每日关回每日游戏页
	if _level_config.get("is_daily", false):
		UIManager.show_ui(UiName.DAILY_GAME, {"_tracker_status": Tracker.GameStatus.RESTART})
		return

	# 优先用原样参数重开，缺参数时退回按关卡号开
	var params: Dictionary = (
		_retry_params.duplicate()
		if not _retry_params.is_empty()
		else {"level_index": _level_config.get("level", 1)}
	)
	# 标记为「重开」，埋点用
	params["_tracker_status"] = Tracker.GameStatus.RESTART
	UIManager.show_ui(UiName.GAME, params)


# 埋点用页面名
func get_scr_name() -> String:
	return Tracker.Scr.NORMAL_GAME_FAIL
