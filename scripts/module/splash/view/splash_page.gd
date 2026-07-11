class_name SplashPage
extends UIFrameWindow

signal loading_complete

const _PROGRESS_LEFT: float = -450.0
const _PROGRESS_WIDTH: float = 900.0
const _DEFAULT_MIN_WAIT_SECONDS: float = 3.0

const _FINISH_TWEEN_DURATION: float = 0.1

const _SLOGAN_COUNT: int = 67
const _QUOTE_KEY_PREFIX: String = "splash_slogan_"
const _AUTHOR_KEY_PREFIX: String = "splash_slogan_author_"

@onready var _progress_fill: Panel = $Root/ProgressFill
@onready var _cat_face: TextureRect = $Root/CatFace
@onready var _quote_label: Label = $Root/QuoteAuthor/QuoteLabel
@onready var _author_label: Label = $Root/QuoteAuthor/AuthorLabel

var _current_progress: float = 0.0
var _elapsed_time: float = 0.0
var _min_wait_seconds: float = _DEFAULT_MIN_WAIT_SECONDS
var _running: bool = false
var _force_complete_requested: bool = false
var _completed: bool = false
var _finish_tween: Tween = null


func on_show(_params: Dictionary = {}) -> void:
	_setup_quote_for_today()
	_min_wait_seconds = float(_params.get("min_wait_seconds", _DEFAULT_MIN_WAIT_SECONDS))
	_current_progress = 0.0
	_elapsed_time = 0.0
	_force_complete_requested = false
	_completed = false
	_running = true
	_apply_progress(0.0)
	set_process(true)


func _setup_quote_for_today() -> void:
	var today_str: String = Time.get_date_string_from_system()
	var is_first_today: bool = GameState.get_last_splash_date() != today_str
	if is_first_today:
		GameState.set_last_splash_date(today_str)

	if ABTestManager.splash_slogan.is_cat_slogan():
		var key: String
		if ABTestManager.splash_slogan.has_daily_fixed_slogan() and is_first_today:
			key = SplashSloganConfig.CAT_DAILY_FIXED_KEY
		elif ABTestManager.splash_slogan.has_daily_fixed_slogan():
			key = "SPLASH_CAT_%02d" % randi_range(2, SplashSloganConfig.CAT_SLOGAN_COUNT)
		else:
			key = "SPLASH_CAT_%02d" % randi_range(1, SplashSloganConfig.CAT_SLOGAN_COUNT)
		if _quote_label != null:
			_quote_label.text = tr(key)
		if _author_label != null:
			_author_label.visible = false
	else:
		var idx: int = 0 if is_first_today else randi_range(1, _SLOGAN_COUNT - 1)
		if _quote_label != null:
			_quote_label.text = tr("%s%d" % [_QUOTE_KEY_PREFIX, idx])
		if _author_label != null:
			_author_label.visible = true
			_author_label.text = "- " + tr("%s%d" % [_AUTHOR_KEY_PREFIX, idx])


func on_hide() -> void:
	_running = false
	set_process(false)
	if _finish_tween != null and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	visible = false


func _process(delta: float) -> void:
	if not _running or _completed:
		return

	_elapsed_time += delta
	if _current_progress < 1.0:
		_current_progress += (1.0 - _current_progress) * (delta / _min_wait_seconds)
		if _current_progress > 1.0:
			_current_progress = 1.0
		_apply_progress(_current_progress)

	if _current_progress >= 1.0 and _force_complete_requested:
		_finalize()
		return

	if _force_complete_requested and _finish_tween == null:
		_start_finish_tween()


func force_complete() -> void:
	if _completed or _force_complete_requested:
		return
	_force_complete_requested = true

	if _current_progress >= 1.0:
		_finalize()


func _start_finish_tween() -> void:
	_finish_tween = create_tween()
	_finish_tween.tween_method(_apply_progress, _current_progress, 1.0, _FINISH_TWEEN_DURATION)
	_finish_tween.finished.connect(_finalize)


func _apply_progress(value: float) -> void:
	_current_progress = value
	if _progress_fill != null:
		_progress_fill.offset_right = _PROGRESS_LEFT + _PROGRESS_WIDTH * value
	if _cat_face != null:
		var cat_center_x: float = _PROGRESS_LEFT + _PROGRESS_WIDTH * value
		_cat_face.offset_left = cat_center_x - 43.0
		_cat_face.offset_right = cat_center_x + 43.0


func _finalize() -> void:
	if _completed:
		return
	_completed = true
	_running = false
	set_process(false)
	_apply_progress(1.0)
	loading_complete.emit()


func get_scr_name() -> String:
	return Tracker.Scr.SPLASH
