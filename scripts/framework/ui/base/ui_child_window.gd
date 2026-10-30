## 子窗口基类：在 UIBaseWindow 之上补两个「被盖住 / 重新露出」的钩子，供 create_child 造出来的窗口用
class_name UIChildWindow
extends UIBaseWindow


## 可选遮挡钩子；子窗口不在管理器页面栈中，需要父窗口按自身规则转发。
func on_stack_top() -> void:
	pass


## 被上层全屏窗口遮挡而隐藏时调用
func on_stack_bottom() -> void:
	pass
