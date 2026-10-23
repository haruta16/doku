## UniKit 配置总表：组合 Android、iOS 子资源，供平台导出器分别读取。
@tool
class_name UniKitConfig
extends Resource

@export_group("Android（Google 渠道）")
@export var android: UniKitAndroidConfig

@export_group("iOS（Apple 渠道）")
@export var ios: UniKitIOSConfig


## 收集两个平台子资源的验证结果，为字段加平台前缀以区分来源。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if android == null:
		errors.append("android (子 Resource 未创建)")
	else:
		for f in android.validate():
			errors.append("android." + f)
	if ios == null:
		errors.append("ios (子 Resource 未创建)")
	else:
		for f in ios.validate():
			errors.append("ios." + f)
	return errors


## 检查指定平台是否存在子配置且已填写产品标识。
func has_platform(platform: String) -> bool:
	match platform:
		"android":
			return android != null and android.production_id != ""
		"ios":
			return ios != null and ios.production_id != ""
		_:
			return false
