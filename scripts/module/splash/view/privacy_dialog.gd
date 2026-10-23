## 隐私确认页：显示协议、适配正文高度，处理接受操作与外部链接。
extends UIFrameWindow

## 点同意、关闭动画播完后发出；launcher await 它之后才 agree_privacy() 并继续启动
signal accepted

## 富文本正文，内含两个 [url] 链接
@onready var _content_label: RichTextLabel = $Root/Content/Panel/ContentLabel
## 弹窗动画（GenericPopup：Mark 之前为开场段，之后为关闭段）
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

## 关闭流程进行中，防止连点同意触发两次
var _closing: bool = false

const _BASE_FONT_SIZE: int = 70
const _FIT_MIN_LINE_SPACING: int = -20
const _FIT_MIN_FONT_SIZE: int = 60


func _ready() -> void:
	var terms_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/tos.html"
	)
	var policy_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/pp.html"
	)
	_content_label.text = tr("PRIVACY_DIALOG_DESC_RICH") % [terms_url, policy_url]
	_content_label.meta_clicked.connect(_on_link_clicked)
	_fit_content_label()


func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")

	_fit_content_label()


func _fit_content_label() -> void:
	await get_tree().process_frame
	_content_label.add_theme_constant_override("line_separation", 0)
	_content_label.add_theme_font_size_override("normal_font_size", _BASE_FONT_SIZE)
	await get_tree().process_frame
	var box_height: float = _content_label.size.y
	var line_count: int = _content_label.get_line_count()
	var content_height: float = _content_label.get_content_height()
	if line_count >= 2 and content_height > box_height:
		var spacing: int = -int(ceil((content_height - box_height) / float(line_count - 1)))
		_content_label.add_theme_constant_override(
			"line_separation", maxi(spacing, _FIT_MIN_LINE_SPACING)
		)
		await get_tree().process_frame

	var font_size: int = _BASE_FONT_SIZE
	while _content_label.get_content_height() > box_height and font_size > _FIT_MIN_FONT_SIZE:
		font_size -= 2
		_content_label.add_theme_font_size_override("normal_font_size", font_size)
		await get_tree().process_frame


## 同意按钮：防连点、埋点、播关闭动画，播完才发信号
func _on_accept_btn_pressed() -> void:
	# 已在关闭流程中就直接忽略
	if _closing:
		return
	# 埋点：同意隐私弹窗
	Tracker.track_btn_click(Tracker.Btn.ACCEPT, self)
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	# 等关闭动画播完再通知外部
	await _anim.animation_finished
	# 先通知再隐藏，保证 launcher 一定收到
	accepted.emit()

	visible = false


## 链接点击：meta 就是 bbcode 里写的 url，交给系统浏览器打开
func _on_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


## 埋点用的弹窗名（Tracker.Dlg.PRIVACY）
func get_dlg_name() -> String:
	return Tracker.Dlg.PRIVACY
