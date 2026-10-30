## 原始翻译的运行时视图：保留恢复文件字节，仅重定位富文本内嵌图片资源。
extends Translation

const _LEGACY_ASSETS := "res://assets/"
const _PRODUCT_ASSETS := "res://products/meowdoku/assets/"
var _source: Translation


func _init(source: Translation) -> void:
	_source = source
	locale = source.locale


func _get_message(src_message: StringName, context: StringName) -> StringName:
	return StringName(_remap_images(str(_source.get_message(src_message, context))))


func _get_plural_message(src_message: StringName, src_plural_message: StringName, n: int, context: StringName) -> StringName:
	return StringName(_remap_images(str(_source.get_plural_message(src_message, src_plural_message, n, context))))


## 只改 img 标签中的旧资源根，不触碰正文、外链、翻译键和已经迁移的路径。
static func _remap_images(text: String) -> String:
	var cursor: int = 0
	while true:
		var tag: int = text.find("[img", cursor)
		if tag < 0:
			break
		var tag_end: int = text.find("]", tag + 4)
		if tag_end < 0:
			break
		var image_end: int = text.find("[/img]", tag_end + 1)
		if image_end < 0:
			break
		var path: String = text.substr(tag_end + 1, image_end - tag_end - 1).strip_edges()
		if path.begins_with(_LEGACY_ASSETS):
			var mapped: String = _PRODUCT_ASSETS + path.trim_prefix(_LEGACY_ASSETS)
			text = text.left(tag_end + 1) + mapped + text.substr(image_end)
			cursor = tag_end + 1 + mapped.length() + 6
		else:
			cursor = image_end + 6
	return text
