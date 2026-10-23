## 虚拟列表几何模型：计算行矩形、总高度、可见范围和滚动锚点，不创建界面节点。
class_name VirtualListLayout
extends RefCounted

const EMPTY_RANGE: Vector2i = Vector2i(-1, -1)

var _count: int = 0
var _available_width: float = 0.0
var _heights: PackedFloat64Array = PackedFloat64Array()
var _prefix: PackedFloat64Array = PackedFloat64Array()
var _uniform_height: float = 0.0
var _spacing: float = 0.0
var _padding: Vector4 = Vector4.ZERO
var _total_height: float = 0.0


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
			var next_prefix: float = candidate_prefix[index] + height + spacing
			if not is_finite(next_prefix):
				return _reject_configuration("height accumulation overflow")
			candidate_prefix[index + 1] = next_prefix
		content_height = candidate_prefix[count] - spacing
		candidate_heights = heights.duplicate()
	var total_height: float = padding.y + padding.w + content_height
	if not is_finite(total_height):
		return _reject_configuration("total height overflow")
	_count = count
	_available_width = available_width
	_heights = candidate_heights
	_prefix = candidate_prefix
	_uniform_height = uniform_height
	_spacing = spacing
	_padding = padding
	_total_height = total_height
	return true


func get_item_rect(index: int) -> Rect2:
	if index < 0 or index >= _count:
		push_error("VirtualListLayout: item index out of range: %d" % index)
		return Rect2()
	return Rect2(_padding.x, _item_top(index), _available_width, _item_height(index))


func get_total_height() -> float:
	return _total_height


func get_visible_range(top: float, bottom: float) -> Vector2i:
	if not is_finite(top) or not is_finite(bottom) or bottom < top:
		push_error("VirtualListLayout: invalid visible interval")
		return EMPTY_RANGE
	if _count == 0 or top == bottom:
		return EMPTY_RANGE
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


func find_anchor_index(top: float) -> int:
	if not is_finite(top):
		push_error("VirtualListLayout: anchor position must be finite")
		return -1
	if _count == 0:
		return -1
	return mini(_first_item_ending_after(top), _count - 1)


func _first_item_ending_after(top: float) -> int:
	if _heights.is_empty():
		var candidate: int = floori(
			clampf((top - _padding.y) / (_uniform_height + _spacing), 0.0, float(_count - 1))
		)
		if candidate > 0 and _item_top(candidate - 1) + _uniform_height > top:
			candidate -= 1
		if _item_top(candidate) + _uniform_height <= top:
			candidate += 1
		return candidate
	var lower: int = 0
	var upper: int = _count
	while lower < upper:
		var middle: int = lower + (upper - lower) / 2
		if _item_top(middle) + _heights[middle] <= top:
			lower = middle + 1
		else:
			upper = middle
	return lower


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


func _item_top(index: int) -> float:
	if _heights.is_empty():
		return _padding.y + index * (_uniform_height + _spacing)
	return _padding.y + _prefix[index]


func _item_height(index: int) -> float:
	return _uniform_height if _heights.is_empty() else _heights[index]


func _reject_configuration(reason: String) -> bool:
	push_error("VirtualListLayout: " + reason)
	return false
