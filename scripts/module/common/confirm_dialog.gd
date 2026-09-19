# 通用确认弹窗：标题 + 正文 + 一个动作按钮，开/关都播 GenericPopup 动画
# 场景在 assets/prefab/confirm_dialog.tscn；按钮信号在场景里连到本脚本
class_name ConfirmDialog
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _title_label: Label = $Root/Content/DialogRoot/TitleLabel # 标题文本
@onready var _content_label: Label = $Root/Content/DialogRoot/ContentLabel # 正文文本
@onready var _action_btn: Button = $Root/Content/DialogRoot/ActionButton # 主行动按钮（发出 tag_pressed）
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # GenericPopup 弹窗动画

# ---- 回调与状态 ----
var _on_confirm: Callable # 点主行动按钮后的回调
var _on_close: Callable # 点右上角关闭后的回调，可为空
var _closing: bool = false # 退场动画是否已在播，用来防重复关闭


# 初始化：给关闭按钮接上按下/抬起缩放反馈（基类提供）
func _ready() -> void:
	bind_press_release_scale($Root/Content/DialogRoot/CloseButton)


# UIManager 拉起本页时的入口：把 params 里的文案和回调转交给 open()
func on_show(params: Dictionary = {}) -> void:
	open(
		params.get("title", _title_label.text),
		params.get("content", _content_label.text),
		params.get("btn_text", _action_btn.text),
		params.get("on_confirm", Callable()),
		params.get("on_close", Callable())
	)


# 打开弹窗：文案过一遍 tr() 翻译，记下两个回调，然后播「开头 → Mark」的进场段
func open(
	title: String,
	content: String,
	btn_text: String,
	on_confirm: Callable,
	on_close: Callable = Callable()
) -> void:
	_title_label.text = tr(title)
	_content_label.text = tr(content)
	_action_btn.text = tr(btn_text)
	_on_confirm = on_confirm
	_on_close = on_close
	_closing = false
	visible = true
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


# 关闭弹窗：播「Mark → 结尾」的退场段，动画播完才真正隐藏；重复调用被 _closing 挡掉
func close() -> void:
	if _closing:
		return
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished

	visible = false


# 主行动按钮（场景里连的 tag_pressed）：先关闭，再走确认回调
func _on_action_btn_pressed() -> void:
	close()
	if _on_confirm.is_valid():
		_on_confirm.call()


# 右上角关闭按钮：只走 on_close 回调，不触发确认
func _on_close_btn_pressed() -> void:
	close()
	if _on_close.is_valid():
		_on_close.call()
