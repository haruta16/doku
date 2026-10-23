## 列表单元绑定凭据：通过有效性检查避免异步回调写入已被复用的单元。
class_name VirtualListBinding
extends RefCounted

var key: String:
	get:
		return _key
	set(_value):
		_reject_assignment("key")

var index: int:
	get:
		return _index
	set(_value):
		_reject_assignment("index")

var revision: int:
	get:
		return _revision
	set(_value):
		_reject_assignment("revision")

var generation: int:
	get:
		return _generation
	set(_value):
		_reject_assignment("generation")

var data: Variant:
	get:
		return _data
	set(_value):
		_reject_assignment("data")

var _key: String = ""
var _index: int = -1
var _revision: int = 0
var _generation: int = -1
var _data: Variant = null
var _cell_ref: WeakRef = null
var _valid: bool = false


func _init(
	cell: Control,
	item_key: String,
	item_index: int,
	item_revision: int,
	binding_generation: int,
	item_data: Variant
) -> void:
	_key = item_key
	_index = item_index
	_revision = item_revision
	_generation = binding_generation
	_data = item_data
	if (
		not is_instance_valid(cell)
		or cell.is_queued_for_deletion()
		or item_key.is_empty()
		or item_index < 0
		or binding_generation < 0
	):
		push_error("VirtualListBinding: invalid cell or descriptor")
		return
	_cell_ref = weakref(cell)
	_valid = true


func invalidate() -> void:
	_valid = false
	_cell_ref = null


func is_valid() -> bool:
	return get_cell() != null


func get_cell() -> Control:
	if not _valid or _cell_ref == null:
		return null
	var cell: Control = _cell_ref.get_ref() as Control
	if not is_instance_valid(cell) or cell.is_queued_for_deletion():
		return null
	return cell


func _reject_assignment(field: String) -> void:
	push_error("VirtualListBinding: %s is read-only" % field)
