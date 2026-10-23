## BI 配置下载器：选择平台请求器、拉取并预处理内容，然后写入原生构建资源目录。
@tool
class_name UniKitBIConfigFetcher
extends RefCounted


## 按平台过滤请求器，并给广告配置请求器设置 SDK 主版本。
static func requesters_for(
	platform: String, ad_major_version: int = UniKitBIConfigRequester.AD_MAJOR_7
) -> Array:
	var out := []
	for cls in [
		UniKitABTestRequester,
		UniKitAdConfigRequester,
		UniKitUserTagRequester,
		UniKitSKAdNetworkRequester
	]:
		var r = cls.new()
		if r.supports_platform(platform):
			r.ad_major_version = ad_major_version
			out.append(r)
	return out


## 依次拉取并保存各类配置，累计成功信息和错误供编辑器面板展示。
func fetch(
	production_id: String,
	platform: String,
	is_debug: bool,
	ios_config_dir: String,
	ad_major_version: int = UniKitBIConfigRequester.AD_MAJOR_7
) -> Dictionary:
	var written := PackedStringArray()
	var errors := PackedStringArray()
	for r in requesters_for(platform, ad_major_version):
		var content := ""
		if r is UniKitSKAdNetworkRequester:
			content = _fetch_skadnetwork(r, errors)
		else:
			var url: String = r.get_url(production_id, is_debug, platform)
			var res := UniKitBIHttp.get_sync(url, r.get_request_headers())
			if not res.ok:
				errors.append("%s 拉取失败 code=%d" % [r.config_name(), res.code])
				continue
			content = r.preprocess(res.body)
		if content == "":
			errors.append("%s 内容为空/预处理失败" % r.config_name())
			continue
		for save_path in r.get_save_paths(platform, is_debug, ios_config_dir):
			if _write_file(save_path, content):
				written.append(save_path)
			else:
				errors.append("%s 写文件失败: %s" % [r.config_name(), save_path])
	return {"ok": errors.is_empty(), "written": written, "errors": errors}


## 汇总多个广告网络来源，必需来源失败时终止该配置，其他来源允许缺失。
func _fetch_skadnetwork(r: UniKitSKAdNetworkRequester, errors: PackedStringArray) -> String:
	var id_lists := []
	for src in r.SOURCES:
		var res := UniKitBIHttp.get_sync(src.url, {})
		var ids := r.parse_source(src.mode, res.body) if res.ok else PackedStringArray()
		if src.required and ids.size() == 0:
			errors.append("SKAdNetwork required 源 %s 拉取失败" % src.name)
		id_lists.append(ids)
	var agg := r.aggregate(id_lists)
	if agg.size() == 0:
		return ""
	return JSON.stringify(agg)


## 创建配置父目录后保存文本，返回写入是否成功。
func _write_file(res_path: String, content: String) -> bool:
	var abs := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()
	return true
