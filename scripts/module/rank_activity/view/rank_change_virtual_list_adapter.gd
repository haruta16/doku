## 名次变动页的虚拟列表适配器；将排名数据与动画布局状态绑定到可回收的 RankCell。

class_name RankChangeVirtualListAdapter
extends VirtualListAdapter

const ROW_SCENE: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_cell.tscn")
var snapshots: Array[Dictionary] = []
var bindings: Dictionary = {}
var presentation: RankChangeListState
var intro_pending: bool = false
var _page: UIBaseWindow


func _init(page: UIBaseWindow, state: RankChangeListState) -> void:
	_page = page
	presentation = state


func get_item_count() -> int:
	return snapshots.size()


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
		push_error("RankChangeVirtualListAdapter: RankCell factory failed")
		return null
	cell.reparent(parent, false)
	cell.like_heart_pressed.connect(_page._on_like_heart_pressed)
	cell.reset_for_reuse()
	cell.hide()
	_preserve_and_disable_modes(cell)
	return cell


## 把排名资料与当前名次变化状态一起应用到行，确保新进入视口的节点接上当前动画进度。
func bind_cell(cell: Control, binding: VirtualListBinding) -> void:
	bindings[binding.index] = binding
	var row: RankCell = cell as RankCell
	var data: Dictionary = binding.data
	row.set_player(PlayerInfo.from_dict(data.player))
	row.apply_score_icon()
	row.set_show_chest(false)
	row.set_entry(data.shown_rank, data.is_self, data.player.nickname, data.score)
	row.set_online(data.online_shown, data.online, data.idle_sec, data.is_self)
	row.set_like_display(data.like_enabled, data.heart_count, data.liked, data.target)
	row.set_meta(&"rank_like_robot_id", data.target)
	if not intro_pending:
		row.show_static()
	else:
		row.get_node("Root/CanvasGroup").modulate.a = 0.0


## 按布局状态补上该行的即时表现；虚拟列表复用不要求节点从动画开头完整播放。
func present_cell(cell: Control, binding: VirtualListBinding, item_rect: Rect2) -> void:
	cell.position.y = item_rect.position.y + presentation.get_row_offset(binding.index)
	var row: RankCell = cell as RankCell
	row.set_rank_number(presentation.get_shown_rank(binding.index, int(binding.data.shown_rank)))
	row.get_node("Root").visible = not (binding.data.is_self and presentation.player_replaced)


## 清除行与旧条目的关联，避免异步动画在回收后继续作用于新数据。
func unbind_cell(_cell: Control, binding: VirtualListBinding) -> void:
	bindings.erase(binding.index)
	_page.cancel_row_intro(binding)


func reset_cell(cell: Control) -> void:
	(cell as RankCell).reset_for_reuse()


func dispose_cell(cell: Control) -> void:
	if is_instance_valid(_page) and is_instance_valid(cell):
		_page.destroy_child(cell as UIChildWindow)
