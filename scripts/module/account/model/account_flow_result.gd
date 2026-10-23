## 页面消费的登录流程结果；用独立对象把账号流程结束与结果弹窗展示解耦。

class_name AccountFlowResult
extends RefCounted

const TYPE_LOGIN_SUCCESS: String = "login_success"

var type: String = ""

var channel: String = ""

var code: int = 0


static func login_success(login_channel: String, result_code: int = 0) -> AccountFlowResult:
	var result := AccountFlowResult.new()
	result.type = TYPE_LOGIN_SUCCESS
	result.channel = login_channel
	result.code = result_code
	return result
