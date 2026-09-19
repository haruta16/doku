# 均衡排版 RichTextLabel（@tool）：按实际内容高度回写 custom_minimum_size，避免文字被裁或留白
@tool
class_name BalancedRichTextLabel
extends RichTextLabel

var _last_width: float = -1.0 # 上次同步用的宽度；-1 表示脏了要重算
var _syncing: bool = false # 重入保护：写 custom_minimum_size 会再次触发 _set

var _pending_recheck: bool = false # 标记还需要再复查一次（二次排版后高度可能变）


# ================= 生命周期与同步 =================
# 进树：锁死 fit_content、关滚动、开裁剪，接尺寸变化并延迟同步一次
func _ready() -> void:
	fit_content = false # 高度自己算，不用引擎的 fit_content

	scroll_active = false
	clip_contents = true
	size_flags_vertical = Control.SIZE_SHRINK_CENTER # 垂直方向收缩居中，不抢空间
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_sync.call_deferred() # 延迟一帧，等排版完成再算


# 在检视面板里把 fit_content 置成只读（本类接管高度）
func _validate_property(property: Dictionary) -> void:
	if property.name == "fit_content":
		property.usage |= PROPERTY_USAGE_READ_ONLY


# 主题或语言变化：标脏并重算
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_TRANSLATION_CHANGED:
		_last_width = -1.0
		_sync.call_deferred()


# 拦截 text / custom_minimum_size 赋值：标脏并排一次同步（自己写的那次跳过）
func _set(property: StringName, value: Variant) -> bool:
	if property == &"text" or (property == &"custom_minimum_size" and not _syncing):
		_last_width = -1.0
		_sync.call_deferred()
	return false


# 宽度真的变了才重算（避免高度回写引发死循环）
func _on_resized() -> void:
	if not is_equal_approx(size.x, _last_width):
		_sync.call_deferred()


# 同步：用内容高度减去尾部行距写 custom_minimum_size；写完再排一次复查，抵消二次排版的误差
func _sync() -> void:
	if _syncing or not is_inside_tree() or size.x <= 0.0: # 重入中、不在树内、宽度还没定：都不算
		return
	_syncing = true
	_last_width = size.x
	var sep: float = float(get_theme_constant("line_separation"))

	var h: float = get_content_height() - sep # 内容高度把最后一段行距也算进去了，要减掉
	custom_minimum_size = Vector2(custom_minimum_size.x, maxf(h, 0.0)) # 只改高度，横向最小宽度保持原样

	var do_recheck: bool = not _pending_recheck # 第一次写入可能让文本重排，所以再安排一次复查
	_pending_recheck = false
	_syncing = false
	# 复查只做一轮：第二轮写完不再递归，避免无限延迟循环
	if do_recheck:
		_pending_recheck = true
		_sync.call_deferred()
