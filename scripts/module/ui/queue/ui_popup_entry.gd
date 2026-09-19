# 弹窗队列的一条排队数据：要弹谁、多急、带什么参数、满足什么条件才弹、是否只弹一次
class_name UIPopupEntry
extends Resource

@export var ui_name: String = "" # UIManager 注册名（UIRegistry 的 key）
@export var priority: int = 0 # 优先级，越大越靠前（enqueue 时插到第一个更小的前面；同级则排在已有同级之后）
@export var params: Dictionary = {} # 原样透传给 UIManager.show_ui
var condition: Callable = Callable() # 可选条件函数；返回 false 就跳过这条（Callable() 表示无条件）
@export var once_per_session: bool = false # true 表示本次运行只弹一次，弹过就记进 UIPopupQueue._shown_this_session
