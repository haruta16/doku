## 等待认证回调时共享的完成状态；done 表示回调已结束，ok 表示这次结果成功。

class_name AuthFlowOutcome
extends RefCounted

var done: bool = false

var ok: bool = false

var code: int = 0

var message: String = ""

var user_id: String = ""

var changed: bool = false


## 认证成功回调写入结果并置 done；等待方由同一个对象读取完成状态。
func finish_ok() -> void:
	done = true
	ok = true


## 保留认证失败的码和消息，同时置 done，确保等待方能区分失败与仍在等待。
func finish_fail(error_code: int, error_message: String = "") -> void:
	done = true
	ok = false
	code = error_code
	message = error_message
