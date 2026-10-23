## 启动展示页：组合活动装扮、标语和进度表现，完成收尾动画后发出结束信号。
class_name SplashPage
extends UIFrameWindow

## 进度跑满并收尾完成时发出；launcher 等这个信号之后才进首页或教程
signal loading_complete

# ---- 进度条几何（像素，相对屏幕下边中点的偏移） ----
const _PROGRESS_LEFT: float = -450.0 # 进度条左端 X 偏移
const _PROGRESS_WIDTH: float = 900.0 # 进度条总宽
const _DEFAULT_MIN_WAIT_SECONDS: float = 3.0 # 默认最短等待秒数（秒），可被 on_show 覆盖

# ---- 收尾补间与标语 key ----
const _FINISH_TWEEN_DURATION: float = 0.1 # 补满剩余进度的补间时长（秒）

const Picker: GDScript = preload("res://scripts/module/splash/core/splash_slogan_picker.gd")

const _CHEAT_LONGEST_QUOTE: String = '"Mahalin ang isa\'t isa at tulungan ang iba na umangat sa mas mataas na antas, sa simpleng pagbuhos lamang ng pag-ibig. Nakakahawa ang pag-ibig at ito ang pinakadakilang enerhiya ng pagpapagaling."'
const _CHEAT_LONGEST_QUOTE_AUTHOR: String = "Sai Baba"

const _DESIGN_H: float = 2400.0

const _PIN_ADAPT_RATIO_DESIGN: float = 1080.0 / 2400.0
const _PIN_ADAPT_RATIO_FIT: float = 1080.0 / 1920.0
const _TOP_ONLY_PIN_ADAPT_EDGE_DIST: float = 110.0

@onready var _root: Control = $Root

@onready var _top_pin: Control = $Root/TopPin
@onready var _bottom_pin: Control = $Root/BottomPin

@onready var _progress_bg: Control = $Root/BottomPin/ProgressBg
@onready var _progress_fill: Panel = $Root/BottomPin/ProgressFill
@onready var _cat_face: TextureRect = $Root/BottomPin/CatFace
@onready var _logo: TextureRect = $Root/BottomPin/Logo
@onready var _quote_author: VBoxContainer = $Root/TopPin/QuoteAuthor
@onready var _quote_label: Label = $Root/TopPin/QuoteAuthor/QuoteLabel
@onready var _author_label: Label = $Root/TopPin/QuoteAuthor/AuthorLabel
@onready var _halloween_bat: TextureRect = $Root/HalloweenBat
@onready var _halloween_bottom_scene: TextureRect = $Root/HalloweenBottomScene

@export var halloween_logo: Texture2D
@export var halloween_cat_face: Texture2D

const _COMPANION_SERVICE: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
var _companion_service: RefCounted = _COMPANION_SERVICE.new()

var _default_logo: Texture2D
var _default_cat_face: Texture2D

# ---- 运行时状态 ----
var _current_progress: float = 0.0 # 当前进度，0~1
var _min_wait_seconds: float = _DEFAULT_MIN_WAIT_SECONDS # 本次的最短等待秒数
var _running: bool = false # 是否在推进（隐藏后置 false）

var _cheat_force_longest_quote: bool = false
var _force_complete_requested: bool = false # 外部已请求收尾
var _completed: bool = false # 已收尾并发过信号
var _finish_tween: Tween = null # 收尾补间（null 表示还没建）

var _is_first_today: bool = false

var _shared_base: Dictionary = {}

var _pin_base_top_dist: float = -1.0

const _BASE_ANCHOR_KEYS: Array[String] = [
	"anchor_left",
	"anchor_top",
	"anchor_right",
	"anchor_bottom",
]
const _BASE_OFFSET_KEYS: Array[String] = [
	"offset_left",
	"offset_top",
	"offset_right",
	"offset_bottom",
]


func on_show(_params: Dictionary = {}) -> void:
	_min_wait_seconds = float(_params.get("min_wait_seconds", _DEFAULT_MIN_WAIT_SECONDS))
	_current_progress = 0.0
	_force_complete_requested = false
	_completed = false
	_running = true

	if _finish_tween != null:
		_finish_tween.kill()
		_finish_tween = null

	var today_str: String = Time.get_date_string_from_system()
	_is_first_today = GameState.get_last_splash_date() != today_str
	if _is_first_today:
		GameState.set_last_splash_date(today_str)
	_cheat_force_longest_quote = GameState.consume_loading_page_test_force_longest_quote()
	_apply_quote()

	_capture_shared_base()
	_restore_shared_base()
	_apply_pin_adaptation()
	_apply_halloween_dress()

	_apply_progress(0.0)
	set_process(true)


func _apply_halloween_dress() -> void:
	if _default_logo == null:
		_default_logo = _logo.texture
		_default_cat_face = _cat_face.texture
	var strategy: HomeCompanionCatStrategy = HomeCompanionCatStrategy.for_group(
		ABTestManager.home_companion_cat.peek_group()
	)
	var mode: int = _companion_service.resolve_mode(strategy)
	var active: bool = _COMPANION_SERVICE.is_halloween_dress_mode(mode)
	_logo.texture = halloween_logo if active and halloween_logo != null else _default_logo
	_cat_face.texture = (
		halloween_cat_face if active and halloween_cat_face != null else _default_cat_face
	)

	_halloween_bat.visible = active
	_halloween_bottom_scene.visible = active


func _shared_layout_nodes() -> Array[Control]:
	return [_top_pin, _bottom_pin, _quote_author, _progress_bg, _progress_fill, _logo, _cat_face]


func _capture_shared_base() -> void:
	if not _shared_base.is_empty():
		return
	var nodes: Array[Control] = _shared_layout_nodes()
	for node in nodes:
		if node == null:
			continue
		var snapshot: Dictionary = {}
		for key in _BASE_ANCHOR_KEYS:
			snapshot[key] = node.get(key)
		for key in _BASE_OFFSET_KEYS:
			snapshot[key] = node.get(key)
		_shared_base[node] = snapshot
	if _top_pin != null:
		_pin_base_top_dist = _top_pin.anchor_top * _DESIGN_H + _top_pin.offset_top


func _restore_shared_base() -> void:
	var nodes: Array[Control] = _shared_layout_nodes()
	for node in nodes:
		if node == null or not _shared_base.has(node):
			continue
		var snapshot: Dictionary = _shared_base[node]
		for key in _BASE_ANCHOR_KEYS:
			node.set(key, snapshot[key])
		for key in _BASE_OFFSET_KEYS:
			node.set(key, snapshot[key])


func _apply_pin_adaptation() -> void:
	if _root == null or _top_pin == null:
		return
	var target_top: float = lerpf(
		_pin_base_top_dist, _TOP_ONLY_PIN_ADAPT_EDGE_DIST, _resolve_pin_adapt_factor()
	)
	var delta_top: float = _pin_base_top_dist - target_top
	_top_pin.offset_top -= delta_top
	_top_pin.offset_bottom -= delta_top


func _resolve_pin_adapt_factor() -> float:
	if _root == null:
		return 0.0
	var root_size: Vector2 = _root.size
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return 0.0
	var ratio: float = root_size.x / root_size.y
	if ratio <= _PIN_ADAPT_RATIO_DESIGN:
		return 0.0
	return clampf(
		(ratio - _PIN_ADAPT_RATIO_DESIGN) / (_PIN_ADAPT_RATIO_FIT - _PIN_ADAPT_RATIO_DESIGN),
		0.0,
		1.0
	)


func _apply_quote() -> void:
	var use_rich_pool: bool = ABTestManager.splash_slogan.uses_rich_pool()
	var time_based: bool = ABTestManager.splash_slogan.is_time_based()
	var quote_text: String = _CHEAT_LONGEST_QUOTE
	var author_text: String = _CHEAT_LONGEST_QUOTE_AUTHOR
	if not _cheat_force_longest_quote:
		var hour: int = int(Time.get_datetime_dict_from_system()["hour"])
		var index_range: Vector2i = Picker.index_range(
			use_rich_pool, time_based, _is_first_today, hour
		)
		var index: int = randi_range(index_range.x, index_range.y)
		quote_text = tr(Picker.quote_key(use_rich_pool, index))
		author_text = tr(Picker.author_key(use_rich_pool, index))
	if _quote_label != null:
		_quote_label.text = quote_text
	if _author_label != null:
		_author_label.visible = true
		_author_label.text = "- " + author_text


func on_hide() -> void:
	for i in 10:
		var ev := InputEventScreenTouch.new()
		ev.index = i
		ev.pressed = false
		Input.parse_input_event(ev)
	_running = false
	set_process(false)
	if _finish_tween != null and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	visible = false


func _process(delta: float) -> void:
	if not _running or _completed:
		return

	_current_progress += (1.0 - _current_progress) * (delta / _min_wait_seconds)
	if _current_progress > 1.0:
		_current_progress = 1.0
	_apply_progress(_current_progress)

	if _current_progress >= 1.0 and _force_complete_requested:
		_finalize()
		return

	if _force_complete_requested and _finish_tween == null:
		_start_finish_tween()


## 外部请求收尾（launcher 等 2 秒后、cheat 面板 3 秒后调用），重复调用无副作用
func force_complete() -> void:
	# 已经收尾或已经请求过就直接忽略
	if _completed or _force_complete_requested:
		return
	_force_complete_requested = true

	# 进度本来就满了：不用补间，立刻收尾
	if _current_progress >= 1.0:
		_finalize()


## 把进度补到 1.0，播完即最终化
func _start_finish_tween() -> void:
	_finish_tween = create_tween()
	# 每帧调 _apply_progress 做插值
	_finish_tween.tween_method(_apply_progress, _current_progress, 1.0, _FINISH_TWEEN_DURATION)
	_finish_tween.finished.connect(_finalize)


## 把 0~1 的进度换算成进度条与猫脸的位置（猫脸 86 像素宽，所以左右各 43）
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


## 收尾：停在满格、停止推进、通知外部（可重复调用）
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
## 启动页的埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.SPLASH
