## 通用确认框：从参数接收正文和按钮样式，点击后发布确认并关闭页面。
class_name ConfirmDialog
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _title_label: Label = $Root/Content/DialogRoot/TitleLabel # 标题文本
@onready var _content_label: Label = $Root/Content/DialogRoot/ContentLabel # 正文文本

@onready var _action_btn: Control = $Root/Content/DialogRoot/ActionButton
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # GenericPopup 弹窗动画

# ---- 回调与状态 ----
var _on_confirm: Callable # 点主行动按钮后的回调
var _on_close: Callable # 点右上角关闭后的回调，可为空


## 初始化：给关闭按钮接上按下/抬起缩放反馈（基类提供）
func _ready() -> void:
	bind_press_release_scale($Root/Content/DialogRoot/CloseButton)


func on_show(params: Dictionary = {}) -> void:
	_title_label.text = tr(params.get("title", _title_label.text))
	_content_label.text = tr(params.get("content", _content_label.text))

	_action_btn.btn_text = str(params.get("btn_text", _action_btn.btn_text))
	_on_confirm = params.get("on_confirm", Callable())
	_on_close = params.get("on_close", Callable())
	_apply_action_btn_look(params)


func _apply_action_btn_look(params: Dictionary) -> void:
	if params.has("btn_bg_color"):
		_action_btn.bg_color = params["btn_bg_color"]
		_action_btn.shadow_color = params["btn_bg_color"]
	if params.has("btn_icon"):
		_action_btn.btn_icon = params["btn_icon"]


func on_hide() -> void:
	_anim.play_section_with_markers(&"GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func _on_action_btn_pressed() -> void:
	UIManager.hide_ui(_ui_name)
	if _on_confirm.is_valid():
		_on_confirm.call()


func _on_close_btn_pressed() -> void:
	UIManager.hide_ui(_ui_name)
	if _on_close.is_valid():
		_on_close.call()
