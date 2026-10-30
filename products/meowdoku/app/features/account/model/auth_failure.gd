## 认证失败的轻量值对象；让异步信号携带结构化错误，而不是让页面解析日志。

class_name AuthFailure
extends RefCounted

var code: int = 0

var message: String = ""


static func of(error_code: int, error_message: String) -> AuthFailure:
	var failure := AuthFailure.new()
	failure.code = error_code
	failure.message = error_message
	return failure
