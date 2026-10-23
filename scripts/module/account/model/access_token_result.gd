## 获取访问令牌的结果对象；把令牌、错误码和错误消息放在同一个返回值中。
## 业务层通过 is_ok 判断是否可继续访问接口，不应只检查对象是否存在。

class_name AccessTokenResult
extends RefCounted

var token: String = ""

var code: int = 0

var message: String = ""


## 错误码成功且令牌非空才算有效；空字符串不能作为后续接口的 bearer。
func is_ok() -> bool:
	return code == 0 and not token.is_empty()


static func success(bearer: String) -> AccessTokenResult:
	var result := AccessTokenResult.new()
	result.token = bearer
	return result


static func fail(error_code: int, error_message: String) -> AccessTokenResult:
	var result := AccessTokenResult.new()
	result.code = error_code
	result.message = error_message
	return result
