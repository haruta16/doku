## 虚拟列表几何模型：计算行矩形、总高度、可见范围和滚动锚点，不创建界面节点。
## 所有位置都在 Content 的局部坐标中；滚动与画布变换由调用方转换成这里使用的可见区间。
class_name VirtualListLayout
extends RefCounted

const EMPTY_RANGE: Vector2i = Vector2i(-1, -1) # 无可见条目的哨兵值；合法范围使用 [first, end) 半开区间

var _count: int = 0 # 已提交的条目数量
var _available_width: float = 0.0 # 扣除左右内边距后的行宽（像素）
var _heights: PackedFloat64Array = PackedFloat64Array() # 变高模式的逐行高度；空数组表示等高模式
var _prefix: PackedFloat64Array = PackedFloat64Array() # 变高模式的累计步长，含每行高度和其后间距，长度为 count + 1
var _uniform_height: float = 0.0 # 等高模式的单行高度（像素）
var _spacing: float = 0.0 # 相邻行之间的间距（像素），总高度不含最后一行后的间距
var _padding: Vector4 = Vector4.ZERO # 左、上、右、下内边距（像素）
var _total_height: float = 0.0 # 含上下内边距的最终内容高度（像素）


## 先验证并计算候选几何，全部通过后才替换模型；失败返回 false，保留上一次有效布局。
## heights 为空走等高模式，否则每项行高须与 count 一一对应；padding 顺序为左、上、右、下。
func configure(
	count: int,
	width: float,
	heights: PackedFloat64Array,
	uniform_height: float,
	spacing: float,
	padding: Vector4
) -> bool:
	if (
		count < 0
		or not is_finite(width)
		or width < 0.0
		or not is_finite(uniform_height)
		or not is_finite(spacing)
		or spacing < 0.0
	):
		return _reject_configuration("invalid count, width, height or spacing")
	for component: int in 4:
		if not is_finite(padding[component]) or padding[component] < 0.0:
			return _reject_configuration("padding must be finite and nonnegative")
	var available_width: float = width - padding.x - padding.z
	if available_width < 0.0 or not is_finite(available_width):
		return _reject_configuration("padding exceeds width")
	# 先在局部变量里计算，任意数值溢出或非法行高都不会破坏旧模型。
	var candidate_prefix: PackedFloat64Array = PackedFloat64Array()
	var candidate_heights: PackedFloat64Array = PackedFloat64Array()
	var content_height: float = 0.0
	if heights.is_empty():
		if uniform_height <= 0.0 and count > 0:
			return _reject_configuration("uniform height must be positive")
		if not is_finite(uniform_height + spacing):
			return _reject_configuration("uniform stride overflow")
		content_height = count * uniform_height + maxi(count - 1, 0) * spacing
	else:
		if heights.size() != count:
			return _reject_configuration("heights must match count")
		candidate_prefix.resize(count + 1)
		candidate_prefix[0] = 0.0
		for index: int in count:
			var height: float = heights[index]
			if not is_finite(height) or height <= 0.0:
				return _reject_configuration("item heights must be positive and finite")
			# 前缀和包含行后的间距，使第 i 行顶部可直接读取 prefix[i]；总高度最后再减去末尾间距。
			var next_prefix: float = candidate_prefix[index] + height + spacing
			if not is_finite(next_prefix):
				return _reject_configuration("height accumulation overflow")
			candidate_prefix[index + 1] = next_prefix
		content_height = candidate_prefix[count] - spacing
		candidate_heights = heights.duplicate()
	var total_height: float = padding.y + padding.w + content_height
	if not is_finite(total_height):
		return _reject_configuration("total height overflow")
	# 所有校验通过后再一次性发布，调用方不会读到一半新、一半旧的布局。
	_count = count
	_available_width = available_width
	_heights = candidate_heights
	_prefix = candidate_prefix
	_uniform_height = uniform_height
	_spacing = spacing
	_padding = padding
	_total_height = total_height
	return true


## 返回内容局部坐标中的条目矩形（不含行间距）；越界索引报错并返回空矩形。
func get_item_rect(index: int) -> Rect2:
	if index < 0 or index >= _count:
		push_error("VirtualListLayout: item index out of range: %d" % index)
		return Rect2()
	return Rect2(_padding.x, _item_top(index), _available_width, _item_height(index))


## 返回包含上下内边距、行高及行间距的总高度（像素）。
func get_total_height() -> float:
	return _total_height


## 按内容坐标区间 [top, bottom) 求相交条目，返回索引半开区间 [first, end)；无条目返回 EMPTY_RANGE。
func get_visible_range(top: float, bottom: float) -> Vector2i:
	if not is_finite(top) or not is_finite(bottom) or bottom < top:
		push_error("VirtualListLayout: invalid visible interval")
		return EMPTY_RANGE
	if _count == 0 or top == bottom:
		return EMPTY_RANGE
	# 边界使用严格相交：底边恰好等于 top、或顶边恰好等于 bottom 的行不算可见。
	var first: int = _first_item_ending_after(top)
	var end: int = 0
	if _heights.is_empty():
		end = ceili(
			clampf((bottom - _padding.y) / (_uniform_height + _spacing), 0.0, float(_count))
		)
		if end > 0 and _item_top(end - 1) >= bottom:
			end -= 1
		if end < _count and _item_top(end) < bottom:
			end += 1
	else:
		end = _first_item_starting_at_or_after(bottom)
	if first >= end:
		return EMPTY_RANGE
	return Vector2i(first, end)


## 在实际可见条目两端加 before/after 个预留单元并夹到合法索引；用于提前创建，不改变可见范围定义。
func get_active_range(top: float, bottom: float, before: int, after: int) -> Vector2i:
	if before < 0 or after < 0:
		push_error("VirtualListLayout: overscan must be nonnegative")
		return EMPTY_RANGE
	var visible: Vector2i = get_visible_range(top, bottom)
	if visible == EMPTY_RANGE:
		return EMPTY_RANGE
	return Vector2i(
		visible.x - mini(before, visible.x), visible.y + mini(after, _count - visible.y)
	)


## 找顶部位置对应的锚点行；位置超过末尾时取最后一行，无条目或输入非法返回 -1。
func find_anchor_index(top: float) -> int:
	if not is_finite(top):
		push_error("VirtualListLayout: anchor position must be finite")
		return -1
	if _count == 0:
		return -1
	return mini(_first_item_ending_after(top), _count - 1)


## 找底边严格大于 top 的第一行；等高时算术定位，变高时二分查找，可能返回 _count 表示已越过末行。
func _first_item_ending_after(top: float) -> int:
	if _heights.is_empty():
		var candidate: int = floori(
			clampf((top - _padding.y) / (_uniform_height + _spacing), 0.0, float(_count - 1))
		)
		# 除法先定位到步长，再检查实际行框；top 可能落在行间距里，不能把间距当可见内容。
		if candidate > 0 and _item_top(candidate - 1) + _uniform_height > top:
			candidate -= 1
		if _item_top(candidate) + _uniform_height <= top:
			candidate += 1
		return candidate
	# 行高都为正且间距非负，底边单调递增，因此可二分而无需遍历所有行。
	var lower: int = 0
	var upper: int = _count
	while lower < upper:
		var middle: int = lower + (upper - lower) / 2
		if _item_top(middle) + _heights[middle] <= top:
			lower = middle + 1
		else:
			upper = middle
	return lower


## 二分找顶边大于等于 bottom 的第一行，作为可见索引区间的排他上界。
func _first_item_starting_at_or_after(bottom: float) -> int:
	var lower: int = 0
	var upper: int = _count
	while lower < upper:
		var middle: int = lower + (upper - lower) / 2
		if _item_top(middle) < bottom:
			lower = middle + 1
		else:
			upper = middle
	return lower


## 返回行顶在内容内的 y 坐标；等高用步长相乘，变高用前缀和读取，调用者负责索引有效。
func _item_top(index: int) -> float:
	if _heights.is_empty():
		return _padding.y + index * (_uniform_height + _spacing)
	return _padding.y + _prefix[index]


## 读取指定行高；等高模式不需要逐项数组，调用者负责索引有效。
func _item_height(index: int) -> float:
	return _uniform_height if _heights.is_empty() else _heights[index]


## 报告几何配置错误并统一返回 false；不改动已经提交的模型字段。
func _reject_configuration(reason: String) -> bool:
	push_error("VirtualListLayout: " + reason)
	return false
