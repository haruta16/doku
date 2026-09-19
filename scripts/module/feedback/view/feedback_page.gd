# 意见反馈页（注册名 UiName.FEEDBACK）：一个多行输入框加提交 / 关闭按钮，提交后弹 Toast 并关闭
# 既能当普通页面也能当弹窗用，由 on_show 的 as_dlg 参数决定（会影响埋点归类）
class_name FeedbackPage
extends UIFrameWindow

# 关闭或提交后广播，供调用方续接流程
signal closed

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _text_edit: TextEdit = $Root/Content/Card/ContentArea/InputText # 反馈内容输入框
@onready var _submit_btn: Button = $Root/Content/Card/SubmitBtn # 有内容时才显示的提交按钮
@onready var _submit_btn_disabled: Button = $Root/Content/Card/SubmitBtnDisabled # 无内容时显示的灰态按钮（不可点）
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 开 / 收场动画播放器

# ---- 运行时状态 ----
var _closing: bool = false # 正在播关闭动画，防重入
var _as_dlg: bool = false # 本次是否以弹窗形态打开
var is_submitted: bool = false # 本次是否通过「提交」关闭，外部可读


# ================= 生命周期 =================
# 接输入变化、刷新按钮态，并给关闭按钮加按下缩放反馈
func _ready() -> void:
	_text_edit.text_changed.connect(_on_input_text_changed)
	_update_submit_state() # 初始为灰态
	bind_press_release_scale($Root/Content/Card/CloseBtn) # 关闭按钮加按下缩放反馈


# 每次打开：读 as_dlg 参数、清空输入、复位状态并播开场动画
func on_show(_params: Dictionary = {}) -> void:
	_as_dlg = _params.get("as_dlg", false) # 弹窗形态只记 Dlg 埋点
	_text_edit.text = "" # 每次打开都清空输入
	_update_submit_state()
	_closing = false
	is_submitted = false
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


# 输入框失焦处理：点到输入框外面就收起软键盘
func _input(event: InputEvent) -> void:
	if not _text_edit.has_focus():
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return
	if not _text_edit.get_global_rect().has_point(event.position):
		_text_edit.release_focus()
		if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			DisplayServer.virtual_keyboard_hide()


# ================= 输入与提交 =================
# 输入内容变化：只影响提交按钮的可用态
func _on_input_text_changed() -> void:
	_update_submit_state()


# 提交：埋点上报 + 本地打印内容，弹 Toast 后播关闭动画并广播 closed
func _on_submit_pressed() -> void:
	var content: String = _text_edit.text.strip_edges()
	if content.is_empty():
		return
	Tracker.track_btn_click(Tracker.Btn.SUBMIT, self, {"feedback_record": content}) # 内容随埋点一起上报
	print("[FeedbackPage] 用户反馈: ", content) # 只在本地打印，没有额外的网络请求

	Toast.popup(
		"%s\n%s" % [tr("FEEDBACK_TOAST_THANKS_TITLE"), tr("FEEDBACK_TOAST_THANKS_DESC")], self
	)
	is_submitted = true # 供调用方区分「提交」和「取消」
	await _close_with_anim()
	closed.emit()


# 关闭按钮：埋点后播关闭动画并广播 closed
func _on_close_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	await _close_with_anim()
	closed.emit()


# 反向播一遍开场动画（GenericPopup 的 Mark 之后半段）
func _close_with_anim() -> void:
	if _closing:
		return
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


# ================= 状态与埋点 =================
# 按「有没有非空白内容」切换提交按钮和灰态按钮
func _update_submit_state() -> void:
	var has_text: bool = not _text_edit.text.strip_edges().is_empty()
	_submit_btn.visible = has_text # 有内容才显示可点的提交按钮
	_submit_btn_disabled.visible = not has_text # 没内容就显示灰态按钮


# 埋点用页面名：当弹窗打开时返回空串，避免重复计数
func get_scr_name() -> String:
	return "" if _as_dlg else Tracker.Scr.FEEDBACK


# 埋点用弹窗名：只有弹窗形态才返回反馈弹窗
func get_dlg_name() -> String:
	return Tracker.Dlg.FEEDBACK if _as_dlg else ""
