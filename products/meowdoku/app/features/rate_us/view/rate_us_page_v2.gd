## 评分引导页：读取星级选择，等待关闭动画后把提交结果交给外层流程。
class_name RateUsPageV2
extends UIFrameWindow

signal closed(data: Dictionary)

@onready var _star1: TextureRect = $Root/Content/Dialog/StarsRow/Star1
@onready var _star2: TextureRect = $Root/Content/Dialog/StarsRow/Star2
@onready var _star3: TextureRect = $Root/Content/Dialog/StarsRow/Star3
@onready var _star4: TextureRect = $Root/Content/Dialog/StarsRow/Star4
@onready var _star5: TextureRect = $Root/Content/Dialog/StarsRow/Star5
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

const _ANIM_NAME: StringName = &"GenericPopupV2"

const _STAR_FILL_AT: float = 0.3

var _stars: Array[TextureRect]
var _star_lit_tex: Texture2D
var _star_dim_tex: Texture2D
var _selected_stars: int = 5
var _closing: bool = false
var _dragging: bool = false


func _ready() -> void:
	_stars = [_star1, _star2, _star3, _star4, _star5]

	_star_lit_tex = _star1.texture
	_star_dim_tex = _star4.texture
	for i in range(_stars.size()):
		var idx := i
		_stars[i].gui_input.connect(
			func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						_dragging = true
						_select_stars(idx + 1)
					else:
						_dragging = false
		)
	bind_press_release_scale($Root/Content/Dialog/CloseBtn)


func _input(event: InputEvent) -> void:
	if not _dragging:
		return

	if event is InputEventMouseButton and not event.pressed:
		_dragging = false
		return
	if event is InputEventMouseMotion:
		var star_idx: int = _star_index_at(event.global_position)
		if star_idx >= 0:
			_select_stars(star_idx + 1)


func _star_index_at(global_pos: Vector2) -> int:
	for i in range(_stars.size()):
		var rect: Rect2 = _stars[i].get_global_rect()
		if rect.has_point(global_pos):
			return i
	return -1


func on_show(_params: Dictionary = {}) -> void:
	var revision: int = get_presentation_revision()
	_closing = false
	_select_stars(0)
	_anim.play_section_with_markers(_ANIM_NAME, &"", &"Mark")
	while _anim.is_playing() and _anim.current_animation_position < _STAR_FILL_AT:
		await get_tree().process_frame
		if revision != get_presentation_revision() or not is_showing() or _closing:
			return
	if not _closing and revision == get_presentation_revision() and is_showing():
		_select_stars(5)


func _select_stars(n: int) -> void:
	_selected_stars = n
	for i in range(_stars.size()):
		_stars[i].texture = _star_lit_tex if i < n else _star_dim_tex


func _on_close_btn_pressed() -> void:
	if _closing or not is_showing():
		return
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	_finish_with_result({"star_count": 0, "is_submitted": false})
func _on_rate_us_btn_pressed() -> void:
	if _closing or not is_showing():
		return
	Tracker.track_btn_click(Tracker.Btn.RATE_US, self, {"rate_star": _selected_stars})
	_finish_with_result({"star_count": _selected_stars, "is_submitted": true})


func _close_with_anim() -> bool:
	if _closing or not is_showing():
		return false
	_closing = true
	var revision: int = get_presentation_revision()
	_anim.play_section_with_markers(_ANIM_NAME, &"Mark", &"")
	while _anim.is_playing():
		await get_tree().process_frame
		if revision != get_presentation_revision() or not is_showing():
			return false
	return revision == get_presentation_revision() and is_showing()



func get_hide_anim_duration() -> float:
	if _anim == null:
		return 0.0
	if not _anim.has_animation(_ANIM_NAME):
		return 0.0
	var a := _anim.get_animation(_ANIM_NAME)
	return maxf(0.0, a.length - (a.get_marker_time(&"Mark") if a.has_marker(&"Mark") else 0.0))


func get_dlg_name() -> String:
	return Tracker.Dlg.RATE


func get_dlg_extra() -> Dictionary:
	return {"dlg_star_ui": "dlg_star_ui_1"}


func _finish_with_result(data: Dictionary) -> void:
	var revision: int = get_presentation_revision()
	_dragging = false
	if not await _close_with_anim():
		return
	closed.emit(data)
	if revision == get_presentation_revision() and is_showing():
		close_requested.emit()

func on_hide() -> void:
	_closing = true
	_dragging = false
	_anim.stop()

static func wait_for_result(page: UIFrameWindow, owner_is_current: Callable = Callable()) -> Dictionary:
	if not is_instance_valid(page) or not page.is_showing():
		return {}
	var tree: SceneTree = page.get_tree()
	var revision: int = page.get_presentation_revision()
	var result := {"done": false, "data": {}}
	var completed := func(data: Dictionary) -> void:
		result.done = true
		result.data = data
	page.closed.connect(completed)
	while not result.done and is_instance_valid(page) and page.is_showing() and revision == page.get_presentation_revision():
		if not owner_is_current.is_null() and (not owner_is_current.is_valid() or not owner_is_current.call()):
			page.close_requested.emit()
			break
		await tree.process_frame
	if is_instance_valid(page) and page.closed.is_connected(completed):
		page.closed.disconnect(completed)
	return result.data if result.done else {}
