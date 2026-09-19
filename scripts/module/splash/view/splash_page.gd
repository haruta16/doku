# 启动页（Splash）：按 min_wait_seconds 平滑推进假进度条 + 每天换一句标语
# 进度是否算「加载完」不由自己决定，外部（launcher / cheat 面板）调 force_complete() 才收尾并发 loading_complete
class_name SplashPage
extends UIFrameWindow

# 进度跑满并收尾完成时发出；launcher 等这个信号之后才进首页或教程
signal loading_complete

# ---- 进度条几何（像素，相对屏幕下边中点的偏移） ----
const _PROGRESS_LEFT: float = -450.0  # 进度条左端 X 偏移
const _PROGRESS_WIDTH: float = 900.0  # 进度条总宽
const _DEFAULT_MIN_WAIT_SECONDS: float = 3.0  # 默认最短等待秒数（秒），可被 on_show 覆盖

# ---- 收尾补间与标语 key ----
const _FINISH_TWEEN_DURATION: float = 0.1  # 补满剩余进度的补间时长（秒）

const _SLOGAN_COUNT: int = 67  # 普通标语条数，key 为 splash_slogan_0 ~ _66
const _QUOTE_KEY_PREFIX: String = "splash_slogan_"  # 标语正文的翻译 key 前缀
const _AUTHOR_KEY_PREFIX: String = "splash_slogan_author_"  # 标语署名的翻译 key 前缀

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _progress_fill: Panel = $Root/ProgressFill  # 进度条填充块，靠改 offset_right 伸缩
@onready var _cat_face: TextureRect = $Root/CatFace  # 骑在进度条前端的猫脸，跟着一起移动
@onready var _quote_label: Label = $Root/QuoteAuthor/QuoteLabel  # 标语正文
@onready var _author_label: Label = $Root/QuoteAuthor/AuthorLabel  # 标语署名（猫标语模式下隐藏）

# ---- 运行时状态 ----
var _current_progress: float = 0.0  # 当前进度，0~1
var _elapsed_time: float = 0.0  # 已运行秒数
var _min_wait_seconds: float = _DEFAULT_MIN_WAIT_SECONDS  # 本次的最短等待秒数
var _running: bool = false  # 是否在推进（隐藏后置 false）
var _force_complete_requested: bool = false  # 外部已请求收尾
var _completed: bool = false  # 已收尾并发过信号
var _finish_tween: Tween = null  # 收尾补间（null 表示还没建）


# ================= 生命周期 =================
# 每次被 UIManager 显示时调用：复位进度、抽今日标语、打开逐帧推进
func on_show(_params: Dictionary = {}) -> void:
	# 先定标语，再决定进度从 0 开始跑
	_setup_quote_for_today()
	# 允许调用方覆盖最短等待秒数（当前调用方都没传，实际用默认 3 秒）
	_min_wait_seconds = float(_params.get("min_wait_seconds", _DEFAULT_MIN_WAIT_SECONDS))
	_current_progress = 0.0
	_elapsed_time = 0.0
	_force_complete_requested = false
	_completed = false
	_running = true
	_apply_progress(0.0)
	# 进度推进完全靠 _process
	set_process(true)


# 挑选今天的标语：先记下「今天已展示过」，再按 A/B 分组取猫标语或普通名言
func _setup_quote_for_today() -> void:
	# 系统当天日期字符串
	var today_str: String = Time.get_date_string_from_system()
	# 存档里的上次展示日期；与今天不同即「今天第一次进启动页」
	var is_first_today: bool = GameState.get_last_splash_date() != today_str
	# 今天是第一次：更新存档日期（会写 user:// 存档）
	if is_first_today:
		GameState.set_last_splash_date(today_str)

	# splash_slogan A/B：猫标语模式（随机猫语录，且不显示作者）
	if ABTestManager.splash_slogan.is_cat_slogan():
		# 先声明 key，下面各分支负责赋值
		var key: String
		# 每日固定模式 + 当天首启：固定用 SPLASH_CAT_01
		if ABTestManager.splash_slogan.has_daily_fixed_slogan() and is_first_today:
			key = SplashSloganConfig.CAT_DAILY_FIXED_KEY
		# 每日固定模式但不是首启：在 02~35 里随机
		elif ABTestManager.splash_slogan.has_daily_fixed_slogan():
			key = "SPLASH_CAT_%02d" % randi_range(2, SplashSloganConfig.CAT_SLOGAN_COUNT)
		# 随机模式：01~35 随机
		else:
			key = "SPLASH_CAT_%02d" % randi_range(1, SplashSloganConfig.CAT_SLOGAN_COUNT)
		# 写正文（tr 查翻译表）
		if _quote_label != null:
			_quote_label.text = tr(key)
		# 猫标语没有作者署名
		if _author_label != null:
			_author_label.visible = false
	# 普通名言：当天首启固定第 0 条，之后在 1~66 随机
	else:
		# idx = 0 是当天的固定开场语
		var idx: int = 0 if is_first_today else randi_range(1, _SLOGAN_COUNT - 1)
		if _quote_label != null:
			# 正文 key = 前缀 + 序号
			_quote_label.text = tr("%s%d" % [_QUOTE_KEY_PREFIX, idx])
		if _author_label != null:
			# 普通名言才显示作者
			_author_label.visible = true
			# 署名前加「- 」
			_author_label.text = "- " + tr("%s%d" % [_AUTHOR_KEY_PREFIX, idx])


# 每次被隐藏时调用：停止推进，并杀掉可能还在跑的收尾补间
# （补间不会因为隐藏而自动停，不 kill 会继续改 UI）
func on_hide() -> void:
	# 置 false 后 _process 直接返回
	_running = false
	set_process(false)
	if _finish_tween != null and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	visible = false


# ================= 进度推进 =================
func _process(delta: float) -> void:
	# 逐帧逼近 1.0：越接近越慢（指数式），所以自然状态下不会真的到 1
	if not _running or _completed:
		return

	# 累计运行秒数（目前只记录，不参与计算）
	_elapsed_time += delta
	# 没满 1 就继续推
	if _current_progress < 1.0:
		_current_progress += (1.0 - _current_progress) * (delta / _min_wait_seconds)
		# 浮点误差可能超过 1，夹住
		if _current_progress > 1.0:
			_current_progress = 1.0
		_apply_progress(_current_progress)

	# 进度已满且外部请求过收尾：立刻最终化
	if _current_progress >= 1.0 and _force_complete_requested:
		_finalize()
		return

	# 外部请求收尾但进度还没满：起一个 0.1 秒补间补到 1
	if _force_complete_requested and _finish_tween == null:
		_start_finish_tween()


# 外部请求收尾（launcher 等 2 秒后、cheat 面板 3 秒后调用），重复调用无副作用
func force_complete() -> void:
	# 已经收尾或已经请求过就直接忽略
	if _completed or _force_complete_requested:
		return
	_force_complete_requested = true

	# 进度本来就满了：不用补间，立刻收尾
	if _current_progress >= 1.0:
		_finalize()


# 把进度补到 1.0，播完即最终化
func _start_finish_tween() -> void:
	_finish_tween = create_tween()
	# 每帧调 _apply_progress 做插值
	_finish_tween.tween_method(_apply_progress, _current_progress, 1.0, _FINISH_TWEEN_DURATION)
	_finish_tween.finished.connect(_finalize)


# 把 0~1 的进度换算成进度条与猫脸的位置（猫脸 86 像素宽，所以左右各 43）
func _apply_progress(value: float) -> void:
	_current_progress = value
	if _progress_fill != null:
		# 进度条右端 = 左端 + 总宽 × 进度
		_progress_fill.offset_right = _PROGRESS_LEFT + _PROGRESS_WIDTH * value
	if _cat_face != null:
		# 猫脸中心贴住进度条前端
		var cat_center_x: float = _PROGRESS_LEFT + _PROGRESS_WIDTH * value
		_cat_face.offset_left = cat_center_x - 43.0
		_cat_face.offset_right = cat_center_x + 43.0


# 收尾：停在满格、停止推进、通知外部（可重复调用）
func _finalize() -> void:
	# 已经收尾过就直接返回，保证信号只发一次
	if _completed:
		return
	_completed = true
	_running = false
	set_process(false)
	_apply_progress(1.0)
	# launcher 在等这个信号
	loading_complete.emit()


# ================= 埋点 =================
# 启动页的埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.SPLASH
