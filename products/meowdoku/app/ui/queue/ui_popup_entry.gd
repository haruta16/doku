## 弹窗队列条目：保存一次弹窗任务的键、回调与执行条件。
class_name UIPopupEntry
extends Resource

var key: String = "" # 业务去重/取消键；不自动去重，由调用方先 cancel 同键旧待办。
var priority: int = 0 # 数值越大越先执行；相同优先级保留入队顺序。
var callable: Callable = Callable() # 可选业务任务，设置后优先于 ui_name；队列等待它返回才继续。

@export var ui_name: String = "" # 无有效 callable 时使用的窗口注册名，也作为 once_per_session 的身份。
@export var params: Dictionary = {} # 传给 UIManager.show_ui 的本次展示参数；条目不自行复制或冻结它。
var condition: Callable = Callable() # 取下一条时检查的条件，false 留在待办中；回调允许同步取消队列。
@export var once_per_session: bool = false # 按 ui_name 跳过已展示条目；callable 执行不登记展示，但取出时仍受此筛选。
