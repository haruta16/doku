## 弹窗队列条目：保存一次弹窗任务的键、回调与执行条件。
class_name UIPopupEntry
extends Resource

var key: String = ""
var priority: int = 0
var callable: Callable = Callable()
