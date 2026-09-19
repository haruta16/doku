# 首启隐私弹窗：正文里嵌协议/政策链接，点「同意」发 accepted
extends UIFrameWindow

# 点同意、关闭动画播完后发出；launcher await 它之后才 agree_privacy() 并继续启动
signal accepted

# 富文本正文，内含两个 [url] 链接
@onready var _content_label: RichTextLabel = $Root/Content/Panel/ContentLabel
# 弹窗动画（GenericPopup：Mark 之前为开场段，之后为关闭段）
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

# 关闭流程进行中，防止连点同意触发两次
var _closing: bool = false


# 初始化正文：把本地化后的协议/政策地址填进带两个占位符的文案
func _ready() -> void:
	# 用户协议地址：按当前语言做本地化（不同地区可能指向不同页面）
	var terms_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/tos.html"
	)
	# 隐私政策地址：同上
	var policy_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/pp.html"
	)
	# PRIVACY_DIALOG_DESC_RICH 里有两个 %s，依次填协议、政策地址
	_content_label.text = tr("PRIVACY_DIALOG_DESC_RICH") % [terms_url, policy_url]
	# RichTextLabel 的链接点击回调（bbcode 里的 [url]）
	_content_label.meta_clicked.connect(_on_link_clicked)


# 每次被显示时调用：复位关闭标记并播开场动画
func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


# 同意按钮：防连点、埋点、播关闭动画，播完才发信号
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


# 链接点击：meta 就是 bbcode 里写的 url，交给系统浏览器打开
func _on_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


# 埋点用的弹窗名（Tracker.Dlg.PRIVACY）
func get_dlg_name() -> String:
	return Tracker.Dlg.PRIVACY
