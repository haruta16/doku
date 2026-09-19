# ATT 引导页：iOS 弹系统授权框之前先给玩家看的说明页，点「继续」发 continued
extends UIFrameWindow

# 点继续按钮、关闭动画播完后发出；launcher 等它才会去调 UniKitManager.init_att()
signal continued

# 弹窗动画（GenericPopup：Mark 之前为开场段，之后为关闭段）
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

# 关闭流程进行中，防止连点触发两次
var _closing: bool = false


# 每次被 UIManager 显示时调用：复位关闭标记并播开场动画
func on_show(_params: Dictionary = {}) -> void:
	# 复位，允许再次点继续
	_closing = false

	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


# 继续按钮：防连点、埋点、播关闭动画，播完才通知外部继续走 ATT 流程
func _on_continue_btn_pressed() -> void:
	# 已在关闭流程中就直接忽略
	if _closing:
		return
	# 先埋点再关，保证点击被记录
	Tracker.track_btn_click(Tracker.Btn.ATT_CONTINUE, self)
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	# 等关闭动画播完
	await _anim.animation_finished
	# 通知 launcher 可以继续了
	continued.emit()

	# 隐藏自己（真正从栈里摘下由 UIManager 负责）
	visible = false


# 埋点用的弹窗名（Tracker.Dlg.PRE_ATT_GUIDE）
func get_dlg_name() -> String:
	return Tracker.Dlg.PRE_ATT_GUIDE
