# 通关弹窗：标题 + 胜利猫动画 + 策略产出的通关文案，并在这里安排「评星弹窗」
@tool
class_name GameWinPage
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _overlay: ColorRect = $Root/Overlay # 全屏半透明遮罩
@onready var _ray_light: TextureRect = $Root/Ctrl/RayLight # 光芒
@onready var _confetti: TextureRect = $Root/Ctrl/Confetti # 撒花
@onready var _cat: SpineSprite = $Root/Ctrl/VictoryCat # 胜利猫（Spine 骨骼动画）
@onready var _title: Label = $Root/Ctrl/TitleLabel # 通关标题
@onready var _next_btn: Control = $Root/Ctrl/VBoxContainer/NextBtn # 「下一关」按钮（Control，带 btn_text / show_difficult 属性）
@onready var _continue_btn: Button = $Root/Ctrl/VBoxContainer/ContinueBtn # 每日关的「继续」按钮
@onready var _beat_percent_label: RichTextLabel = $Root/Ctrl/VBoxContainer/BeatPercentLabel # 通关文案正文（富文本，由策略产出）
@onready var _anim: AnimationPlayer = $AnimationPlayer # 弹窗本体动画（Appear / Loop / Disappear）
@onready var _anim_loop: AnimationPlayer = $AnimationPlayer2 # 循环动画（ContinueLoop）

# ---- 动画时序（秒） ----
const APPEAR_DELAY: float = 1.2 # 出现前的等待：先让棋盘把自己的动画播完

const APPEAR_DURATION: float = 2.467 # Appear 动画时长，用于算遮输入时长与评星延迟

# 普通关标题候选池：随机取，且避开上一次用过的那条
const WIN_TITLES_NORMAL: Array[StringName] = [
	&"WIN_TITLE", &"WIN_TITLE_1", &"WIN_TITLE_2", &"WIN_TITLE_3", &"WIN_TITLE_4"
]

# ---- 运行时状态 ----
var _level_config: Dictionary = {} # 本局关卡参数（GamePage 传入，并补写重开/复活/失误/用时等统计）
var _last_win_title: StringName = &"" # 上一次用过的标题，保证连续两次不重复

var _pass_text_strategy: PassTextStrategy # 通关文案策略，on_show 时按 AB 分组创建

var _win_text: Dictionary = {} # 策略产出：title / body / shown_percent

var _show_seq_id: int = 0 # 展示序号：异步等待之后用它判断这次展示是否已被顶掉


# ================= 生命周期 =================
func _ready() -> void:
	# 编辑器里直接把最终状态摆好，方便调 UI
	if Engine.is_editor_hint():
		visible = true
		_overlay.color.a = 0.8
		_ray_light.modulate.a = 0.7
		_confetti.modulate.a = 1.0
		_cat.scale = Vector2.ONE
		_title.modulate.a = 1.0
		_next_btn.modulate.a = 1.0
		return
	# 运行时要交互，只给「银行」按钮绑按下缩放
	bind_press_release_scale($Root/Ctrl/BankBtn)


# 打开：建策略、判定评星资格（决定遮输入多久），再进 show_win
func on_show(params: Dictionary = {}) -> void:
	# 每次打开都重建策略，AB 分组可能已经变了
	_pass_text_strategy = PassTextStrategy.create()
	var lc: Dictionary = params.get("level_config", {})
	var lv: int = lc.get("level", 0)

	# 本关可弹评星：把整段进场动画都遮掉，免得玩家先点到「下一关」
	if (
		ABTestManager.rate_us_pop.is_eligible_at_game_win(
			lv, GameState.get_session_consecutive_wins()
		)
		and not GameState.has_shown_rate_us()
	):
		UIManager.block_input_briefly(self, APPEAR_DELAY + APPEAR_DURATION)
	# 不弹评星：只遮 2 秒
	else:
		UIManager.block_input_briefly(self, 2.0)
	# 关卡参数由 GamePage 传入
	var bv: BoardView = params.get("board_view")
	# board_view 目前没在函数体里用到，保留形参
	if bv != null:
		show_win(lc, bv)


# 关闭：让挂起的异步流程失效 → 播消失动画 → 复位猫
func on_hide() -> void:
	# 已经隐藏过就别重播动画
	if not visible:
		return

	# 序号自增：先前 await 中的流程会因此提前退出
	_show_seq_id += 1
	# 先停循环动画再播消失
	_anim_loop.stop()
	_anim.play("Disappear")
	await _anim.animation_finished

	# 复位猫的骨骼，避免下次打开停在最后一帧
	_reset_cat_spine()
	visible = false


# 展示通关界面：出文案 → 摆标题/按钮/统计 → 排评星 → 播出现动画
func show_win(level_config: Dictionary, board_view: BoardView) -> void:
	# 记下参数，后面几个 _setup_ 都读它
	_level_config = level_config
	# 换序号：上一次挂起的 await 到此作废
	_show_seq_id += 1
	var seq: int = _show_seq_id
	visible = true

	# 策略要和「上局纪录」比，先把纪录塞进配置
	_level_config["last_win_beat_percent"] = GameState.get_last_win_beat_percent()
	# 策略产文案：title / body / shown_percent
	_win_text = _pass_text_strategy.get_win_text(_level_config)
	# 每日关不写纪录；shown_percent=-1 会把纪录置空
	if not _level_config.get("is_daily", false):
		GameState.set_last_win_beat_percent(_win_text.get("shown_percent", -1.0))

	# 依次摆好标题、下一关按钮、统计条、正文
	_setup_win_title()
	_setup_next_btn()
	_maybe_show_stats_label()
	_maybe_show_beat_percent_tip()

	# 评星弹窗安排在进场动画之后
	_delayed_maybe_show_rate_us(seq)

	_reset_cat_spine()

	# 把猫定格、动画播到第 0 帧后暂停，等下面的等待结束再真正开播
	_anim.stop()
	_anim.play("Appear")
	_anim.advance(0.0)
	_anim.pause()

	# 连胜流程或通关 toast 已经消耗过等待时就不再等
	if (
		not level_config.get("skip_appear_delay", false)
		and not level_config.get("toast_was_shown", false)
	):
		# 等待期间被新的展示顶掉就放弃
		await get_tree().create_timer(APPEAR_DELAY).timeout
		if seq != _show_seq_id:
			return
	# 真正开播：放通关音效并恢复猫的骨骼播放
	SoundManager.play(SoundManager.Kind.LEVEL_WIN)
	_resume_cat_spine()
	_anim.play("Appear")

	# 强制刷一帧骨骼，免得第一帧还是旧姿势
	_anim.advance(0.0)
	_cat.update_skeleton(0.0)
	await _anim.animation_finished
	# 动画期间被顶掉就不再往下走
	if seq != _show_seq_id:
		return

	# 出现播完转循环（猫在 Loop，继续按钮在 AnimationPlayer2）
	_anim.play("Loop")

	_anim_loop.play("ContinueLoop")


# 把猫复位到 appear 第 0 帧并暂停；期间短暂显示以强制刷新骨骼，最后再隐藏
func _reset_cat_spine() -> void:
	# 节点缺失时直接跳过（编辑器预览 / 换皮场景）
	if _cat == null:
		return
	_cat.visible = true
	var st := _cat.get_animation_state()
	if st != null:
		# 时间缩放归零：定格但不卸载
		st.set_animation("appear", false, 0)
		st.set_time_scale(0.0)
	_cat.update_skeleton(0.0)
	# 隐藏，等出现动画开始时再显示
	_cat.visible = false


# 恢复猫的骨骼播放（时间缩放回到 1）
func _resume_cat_spine() -> void:
	if _cat == null:
		return
	var st := _cat.get_animation_state()
	if st != null:
		st.set_time_scale(1.0)


# 延迟弹评星：条件满足就先把「下一关」藏起来，走完流程再淡回来
func _delayed_maybe_show_rate_us(seq: int) -> void:
	var lv: int = _level_config.get("level", 0)
	# 资格判定：AB 分组 + 本次会话连胜数，且全局只弹一次
	if (
		not ABTestManager.rate_us_pop.is_eligible_at_game_win(
			lv, GameState.get_session_consecutive_wins()
		)
		or GameState.has_shown_rate_us()
	):
		return

	# 离线不弹（评星要联网）
	if not UniKitManager.is_online():
		return
	# 展示已被顶掉就放弃
	if seq != _show_seq_id:
		return
	# 先标记已弹，避免同一会话反复弹
	GameState.mark_rate_us_shown()
	# 藏掉按钮：评星结束前不让玩家点下一关
	_next_btn.modulate.a = 0.0

	# 等进场动画播完再弹，别和通关演出抢镜
	await get_tree().create_timer(APPEAR_DELAY + APPEAR_DURATION).timeout
	if seq != _show_seq_id:
		return
	# 流程结束后把按钮淡回来
	await _run_rate_us_flow()
	_restore_next_btn()


# 评星流程：按 AB 选新版 / 旧版评星页，等它关闭后决定下一步
func _run_rate_us_flow() -> void:
	# 页面 key 由 AB 分组决定
	var page_key: StringName = (
		UiName.RATE_US_V2 if ABTestManager.rate_us_pop_ui.is_new_ui() else UiName.RATE_US
	)
	var rate_us := UIManager.show_ui(page_key)
	# 页面关闭时回传 {is_submitted, star_count}
	var data: Dictionary = await rate_us.closed
	UIManager.hide_ui(page_key)
	# 提交且 5 星：请求应用内评价
	if data.get("is_submitted") and data.get("star_count", 0) > 4:
		InAppReviewManager.request_review()
	# 提交但不满 5 星：弹反馈弹窗收意见
	elif data.get("is_submitted") and data.get("star_count", 0) <= 4:
		var feedback := UIManager.show_ui(UiName.FEEDBACK, {"as_dlg": true})
		await feedback.closed
		UIManager.hide_ui(UiName.FEEDBACK)


# 「下一关」按钮淡回来（评星流程结束后）
func _restore_next_btn() -> void:
	var tw := create_tween()
	tw.tween_property(_next_btn, "modulate:a", 1.0, 0.25)


# 定标题：策略给的标题优先，否则用默认池（困难关走固定横幅）
func _setup_win_title() -> void:
	# 策略产出的标题非空就覆盖默认
	var override_title: String = _win_text.get("title", "")
	if not override_title.is_empty():
		_title.text = override_title
		return
	var lv: int = _level_config.get("level", 0)
	# 困难关判定：遵守 rule_normal_rank 的 group_j 规则
	var key: StringName
	var _is_hard: bool = (
		LevelData.is_hard_level_group_j(lv)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(lv)
	)
	if lv > 0 and _is_hard:
		key = &"WIN_TITLE_HARD"
	else:
		# 普通关随机取，排除上一次用过的那条
		var pool := WIN_TITLES_NORMAL.filter(
			func(k: StringName) -> bool: return k != _last_win_title
		)
		key = pool[randi() % pool.size()]
	_last_win_title = key
	_title.text = tr(key)


# 摆「下一关」按钮：每日关用继续按钮，主线显示第 n+1 关，题库关按题库算
func _setup_next_btn() -> void:
	# 每日关显示「继续」
	_continue_btn.visible = _level_config.get("is_daily", false)

	# 每日关没有「下一关」
	if _level_config.get("is_daily", false):
		_next_btn.visible = false
		return
	var lv: int = _level_config.get("level", 0)
	# 主线关：下一关就是 lv+1
	if lv > 0:
		_next_btn.visible = true
		var next_lv: int = lv + 1
		_next_btn.btn_text = tr("GAME_LEVEL_TITLE") % next_lv
		# 下一关是否困难，决定按钮上的难度标记
		_next_btn.show_difficult = (
			LevelData.is_hard_level_group_j(next_lv)
			if ABTestManager.rule_normal_rank.is_group_j()
			else LevelData.is_hard_level(next_lv)
		)
	else:
		# 题库关（level<=0）：下一关在题库里循环
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			# 有题库参数才写按钮文案
			_next_btn.visible = true
			_next_btn.show_difficult = false
			# 序号循环：最后一关回到第 1 关
			var idx: int = bp.get("bank_index", 1)
			var total: int = bp.get("bank_total", 1)
			var next_idx: int = (idx % total) + 1
			_next_btn.btn_text = _bank_next_label(bp, next_idx)
		else:
			# 缺题库参数就不显示按钮
			_next_btn.visible = false


# 本局带 beat_percent 时，额外加一行「耗时 · Top x%」统计
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


# 通关文案正文：非空才显示 BeatPercentLabel
func _maybe_show_beat_percent_tip() -> void:
	if _beat_percent_label == null:
		return
	# body 为空时整块隐藏，避免留白
	var text: String = _win_text.get("body", "")
	_beat_percent_label.visible = not text.is_empty()
	if not text.is_empty():
		_beat_percent_label.text = text


# 运行时造一个 Label 当统计条：延时 0.6 秒后淡入并上浮 10 像素
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


# 点「下一关」：每日关回当前关，主线进 lv+1，题库关按题库参数开下一关
func _on_next_btn_pressed() -> void:
	# 埋点：这一下算「开始关卡」
	Tracker.track_btn_click(Tracker.Btn.LEVEL_PLAY, self)
	# 每日关：继续当前进度
	if _level_config.get("is_daily", false):
		UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
		return
	# 主线关：直接下一关
	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		UIManager.show_ui(UiName.GAME, {"level_index": lv + 1})
		return
	# 题库参数缺失（异常）兜底回第 1 关
	var bp: Dictionary = _level_config.get("bank_params", {})
	if bp.is_empty():
		UIManager.show_ui(UiName.GAME, {"level_index": 1})
		return
	var idx: int = bp.get("bank_index", 1)
	var total: int = bp.get("bank_total", 1)
	var next_idx: int = (idx % total) + 1
	_play_bank_level(bp, next_idx, total)


# 题库下一关的按钮文案：不同题库取不同字段拼「尺寸 / R / 序号」
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


# 打开题库里的下一关：按题库取表，带上预制区域与解法后打开游戏页
func _play_bank_level(bp: Dictionary, next_idx: int, total: int) -> void:
	# SP 题库
	if bp.get("bank_sp", false):
		var levels: Array = BankData.get_sp_levels()
		if next_idx - 1 >= levels.size():
			# 越界直接放弃
			return
		var entry: Dictionary = levels[next_idx - 1]
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
		# LK 题库（含修改版）
		var is_lk_modified: bool = bp.get("bank_lk_modified", false)
		var levels: Array = (
			BankData.get_lk_modified_levels() if is_lk_modified else BankData.get_lk_levels()
		)
		# 越界直接放弃
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = levels[next_idx - 1]
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
		# LK-style 题库（可按 tier H 取表）
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var is_tier_h: bool = bp.get("bank_tier_h", false)
		var levels: Array = (
			BankData.get_lk_style_levels_by_tier(sz, rank, "H")
			if is_tier_h
			else BankData.get_lk_style_levels(sz, rank)
		)
		# 越界直接放弃
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = levels[next_idx - 1]
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
		# GC 题库（tier 为 H/N 时用分档表）
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var bank_tier: String = bp.get("bank_tier", "")
		var levels: Array = (
			BankData.get_gc_levels_by_tier(sz, rank, bank_tier)
			if (bank_tier == "H" or bank_tier == "N")
			else BankData.get_gc_levels(sz, rank)
		)
		# 越界直接放弃
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = levels[next_idx - 1]
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
		# 普通题库（可按 tier H 取表）
		var sz: int = bp.get("bank_size", 7)
		var rank: int = bp.get("bank_rank", 1)
		var is_tier_h: bool = bp.get("bank_tier_h", false)
		var levels: Array = (
			BankData.get_levels_by_tier(sz, rank, "H")
			if is_tier_h
			else BankData.get_levels(sz, rank)
		)
		# 越界直接放弃
		if next_idx - 1 >= levels.size():
			return
		var entry: Dictionary = levels[next_idx - 1]
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


# 埋点用页面名
func get_scr_name() -> String:
	return Tracker.Scr.NORMAL_GAME_SUCCESS
