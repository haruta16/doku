# 子窗口基类：在 UIBaseWindow 之上补两个「被盖住 / 重新露出」的钩子，供 create_child 造出来的窗口用
class_name UIChildWindow
extends UIBaseWindow


# 被上层全屏窗口盖住后重新露出、恢复可见时调用（UIManager 刷新遮挡时触发）
func on_stack_top() -> void:
	pass


# 被上层全屏窗口遮挡而隐藏时调用
func on_stack_bottom() -> void:
	pass
