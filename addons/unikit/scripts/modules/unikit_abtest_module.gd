## 实验配置桥接：读取原生实验值、管理分组染色，并转发远端实验刷新状态。
class_name UniKitAbTestModule
extends UniKitModuleBase

signal abtest_ready(user_info: Dictionary)
signal abtest_params_updated(update_type: String, user_info: Dictionary)

signal abtest_locsrv_fetched(success: bool)

signal abtest_remote_config_ready


## 读取字符串实验值；原生插件缺失时使用调用方默认值。
func get_ab_string(key: String, default_value: String = "") -> String:
	if _host._plugin == null:
		return default_value
	return _host._plugin.getAbString(key, default_value)


## 读取整数实验值；原生插件缺失时使用调用方默认值。
func get_ab_int(key: String, default_value: int = 0) -> int:
	if _host._plugin == null:
		return default_value
	return _host._plugin.getAbInt(key, default_value)


## 读取浮点实验值；原生插件缺失时使用调用方默认值。
func get_ab_float(key: String, default_value: float = 0.0) -> float:
	if _host._plugin == null:
		return default_value
	return _host._plugin.getAbFloat(key, default_value)


## 通知原生层为指定实验染色，标记该实验已实际参与业务。
func dye_ab(key: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.dyeAbTest(key)


## 解析原生返回的全部实验字典，异常数据回退为空字典。
func get_all_ab_experiments() -> Dictionary:
	if _host._plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_host._plugin.getAllAbExperimentsJson())
	return d if d is Dictionary else {}


## 读取已发布实验的原生快照，供配置和调试使用。
func get_all_publish_ab_experiments() -> Dictionary:
	if _host._plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_host._plugin.getAllPublishAbExperimentsJson())
	return d if d is Dictionary else {}


## 读取原生聚合的全部实验标签字符串。
func get_ab_all_tag() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getAbAllTag()


## 读取已经染色的实验标签字符串。
func get_ab_dyeing_tag() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getAbDyeingTag()


## 读取原生实验分组标识。
func get_ab_group_id() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getAbGroupId()


## 解析原生实验用户信息，保留字典形式供业务消费。
func get_ab_user_info() -> Dictionary:
	if _host._plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_host._plugin.getAbUserInfoJson())
	return d if d is Dictionary else {}


## 发起远端实验结果刷新，完成状态通过模块信号返回。
func fetch_remote_ab_result() -> void:
	if _host._plugin == null:
		return
	_host._plugin.fetchRemoteLocSerAbResult()


## 读取远端实验参数，空串或插件缺失时使用默认值。
func get_ab_locsrv_param(key: String, default_value: String = "") -> String:
	if _host._plugin == null:
		return default_value
	var v: String = _host._plugin.getAbLocSerParam(key)
	return v if v != "" else default_value


## 取得远端实验参数快照，异常 JSON 回退为空字典。
func get_all_ab_locsrv_params() -> Dictionary:
	if _host._plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_host._plugin.getAbAllLocSerParamsJson())
	return d if d is Dictionary else {}


## 通知原生层染色指定本地服务实验参数。
func dye_ab_locsrv(key: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.dyeAbLocSerTag(key)


## 以 JSON 数组提交有效标签和空标签，保持原生接口的数据格式。
func set_ab_locsrv_all_tag(all_tags: Array[String], empty_tags: Array[String] = []) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setAbServerTag(JSON.stringify(all_tags), JSON.stringify(empty_tags))


## 向原生层提交服务端实验标签染色。
func dye_ab_locsrv_tag(tag: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.dyeAbServerTag(tag)


## 读取实验系统采用的国家或地区标识。
func get_ab_country() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getAbCountry()


## 覆盖原生实验分组标识，供指定分组或调试流程使用。
func set_ab_group_id(group_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setAbGroupId(group_id)


## 覆盖原生实验地区标识，后续实验读取由原生层处理。
func set_ab_country(country: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setAbCountry(country)


## 按键从原生 JSON 取实验值，键不存在时返回空值。
func get_experiment_value(key: String) -> Variant:
	if _host._plugin == null:
		return null
	var d: Variant = JSON.parse_string(_host._plugin.getExperimentValue(key))
	if d is Dictionary and d.has(key):
		return d[key]
	return null


## 查询指定实验是否已经被染色。
func is_dyeing(key: String) -> bool:
	if _host._plugin == null:
		return false
	return _host._plugin.isDyeing(key)


## 读取指定实验的原生分组状态字符串。
func get_group_status(key: String) -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getGroupStatus(key)


## 读取指定实验的染色时间字符串。
func get_dyeing_time(key: String) -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getDyeingTime(key)


## 解析全部实验染色时间，异常 JSON 回退为空字典。
func get_all_dyeing_times() -> Dictionary:
	if _host._plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_host._plugin.getAllDyeingTimes())
	return d if d is Dictionary else {}
