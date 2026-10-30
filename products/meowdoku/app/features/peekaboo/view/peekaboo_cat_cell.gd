## 首页藏猫的 Spine 表现；依据道具切换动画，并用可点击状态防止重复开启交互流程。

extends UIChildWindow

signal cat_pressed

@onready var _cat_anim: AnimationPlayer = $CatSpine/AnimationPlayer
@onready var _click_btn: Button = $ClickBtn

var _consumed: bool = false

const _PROP_ANIM_SUFFIX := ["Pot", "Basket", "Bag", "Leaf", "Plant"]

var _idle_anim_name: String = ""


func on_show(params: Dictionary = {}) -> void:
	if _cat_anim != null and not _cat_anim.animation_finished.is_connected(_on_cat_anim_finished):
		_cat_anim.animation_finished.connect(_on_cat_anim_finished)
	_rearm()
	setup(int(params.get("prop_index", 0)))


func setup(prop_index: int) -> void:
	_idle_anim_name = "Cat%sIdle" % _prop_suffix(prop_index)
	_play_cat_anim(_idle_anim_name)


func play_peek_out(prop_index: int) -> float:
	_idle_anim_name = ""
	var appear_name: String = "Cat%sAppear" % _prop_suffix(prop_index)
	if not _play_cat_anim(appear_name):
		return 0.0
	var anim: Animation = _cat_anim.get_animation(appear_name)
	return anim.length if anim != null else 0.0


func _prop_suffix(prop_index: int) -> String:
	var suffix_count: int = _PROP_ANIM_SUFFIX.size()
	if suffix_count <= 0:
		return "Pot"
	return _PROP_ANIM_SUFFIX[posmod(prop_index, suffix_count)]


func _play_cat_anim(anim_name: String) -> bool:
	if _cat_anim == null or not _cat_anim.has_animation(anim_name):
		push_warning("[PeekabooCatCell] 缺动画 %s，猫将不播动效" % anim_name)
		return false
	_cat_anim.play(anim_name)
	return true


func _on_cat_anim_finished(anim_name: StringName) -> void:
	if _idle_anim_name != "" and String(anim_name) == _idle_anim_name:
		_play_cat_anim(_idle_anim_name)


func _rearm() -> void:
	_consumed = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	_click_btn.disabled = false
	_click_btn.mouse_filter = Control.MOUSE_FILTER_STOP


func disarm() -> void:
	_consumed = true

	_click_btn.disabled = true
	_click_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_click_btn_pressed() -> void:
	if _consumed:
		return
	disarm()

	cat_pressed.emit()
