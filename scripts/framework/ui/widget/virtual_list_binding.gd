## 列表单元绑定凭据：通过有效性检查避免异步回调写入已被复用的单元。
## 它是身份与弱引用的记录，不负责调度或取消任务；异步调用方要主动检查再操作。
class_name VirtualListBinding
extends RefCounted

var key: String: # 稳定条目键，只读；重排后仍用它识别同一条数据
	get:
		return _key
	set(_value):
		_reject_assignment("key")

var index: int: # 本次绑定时的索引，只读；不随数据源后续重排自动更新
	get:
		return _index
	set(_value):
		_reject_assignment("index")

var revision: int: # 条目内容版本，只读；由适配器定义何时发生内容变化
	get:
		return _revision
	set(_value):
		_reject_assignment("revision")

var generation: int: # 每次绑定递增的代次，只读；同一个节点再次复用也会换代次
	get:
		return _generation
	set(_value):
		_reject_assignment("generation")

var data: Variant: # 绑定时取得的业务值，只读属性但不保证内部容器深度只读
	get:
		return _data
	set(_value):
		_reject_assignment("data")

var _key: String = "" # 公开 key 的底层存储，仅初始化时写入
var _index: int = -1 # 公开 index 的底层存储，-1 表示尚无合法条目
var _revision: int = 0 # 公开 revision 的底层存储
var _generation: int = -1 # 公开 generation 的底层存储，-1 表示尚未绑定
var _data: Variant = null # 保留适配器提供的数据值；若为引用类型，不在这里复制
var _cell_ref: WeakRef = null # 对单元的弱引用；按需取存活节点，不向调用方交出失效或待删除节点
var _valid: bool = false # 单向有效标志；invalidate 后不能恢复成新绑定


## 记录一次绑定的条目标识、内容版本和代次；参数无效则保持失效，不持有单元的强引用。
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
	# 保存弱引用只解决节点存活检查；旧任务是否仍属于当前条目，还要看凭据有没有被 invalidate。
	_cell_ref = weakref(cell)
	_valid = true


## 使当前凭据永久失效并清掉弱引用；回收旧单元时先调用，迟到回调便取不到复用后的节点。
func invalidate() -> void:
	_valid = false
	_cell_ref = null


## 返回凭据是否仍能取得存活且未排队删除的单元；列表归属与当前显示周期另由 is_binding_current 检查。
func is_valid() -> bool:
	return get_cell() != null


## 返回仍有效的单元，否则返回 null；WeakRef 不延长节点生命周期，也不会自动取消调用方的等待。
func get_cell() -> Control:
	if not _valid or _cell_ref == null:
		return null
	var cell: Control = _cell_ref.get_ref() as Control
	if not is_instance_valid(cell) or cell.is_queued_for_deletion():
		return null
	return cell


## 拒绝外部重写绑定身份并报错；要表达下一次绑定应新建凭据，不能修改旧凭据。
func _reject_assignment(field: String) -> void:
	push_error("VirtualListBinding: %s is read-only" % field)
