## 排行榜主页的虚拟列表适配器；提供稳定键、修订号和行节点生命周期，避免为全部名次常驻创建节点。

class_name RankVirtualListAdapter
extends VirtualListAdapter

const ROW_SCENE: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")

var snapshots: Array[Dictionary] = []
var _page: UIBaseWindow = null


func _init(page: UIBaseWindow) -> void:
	_page = page


func get_item_count() -> int:
	return snapshots.size()


## 提供数据项稳定标识，让列表区分“同一玩家更新”和“节点改绑到另一玩家”。
func get_item_key(index: int) -> String:
	return snapshots[index].key


func get_item_data(index: int) -> Variant:
	return snapshots[index]


func get_item_scene(_index: int) -> PackedScene:
	return ROW_SCENE


func get_item_revision(index: int) -> int:
	return snapshots[index].revision


func create_cell(scene: PackedScene, parent: Control) -> Control:
	var cell: RankCell = _page.create_child(scene) as RankCell
	if cell == null:
		push_error("RankVirtualListAdapter: RankCell factory failed")
		return null
	cell.reparent(parent, false)
	cell.reset_for_reuse()
	cell.enable_label_z_batching()
	cell.hide()
	_preserve_and_disable_modes(cell)
	return cell


## 将索引对应快照应用到复用行，并接上当前页面需要的交互。
func bind_cell(cell: Control, binding: VirtualListBinding) -> void:
	RankRowSnapshot.apply(cell as RankCell, binding.data)
	(cell as RankCell).show_static()


## 解除旧条目的绑定与交互，防止回收后的行仍响应上一位玩家的事件。
func unbind_cell(_cell: Control, binding: VirtualListBinding) -> void:
	_page.call("cancel_row_intro", binding)


## 把行恢复为可重新绑定状态，清掉动画和临时表现。
func reset_cell(cell: Control) -> void:
	(cell as RankCell).reset_for_reuse()


func dispose_cell(cell: Control) -> void:
	if is_instance_valid(_page) and is_instance_valid(cell):
		_page.destroy_child(cell as UIChildWindow)
