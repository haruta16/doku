## 资料编辑页；管理昵称输入、头像/头像框/服装分页、滚动选中与锁定提示。
## 真正的数据修改由 ProfileService 完成；这里还区分滚动拖拽与点击，防止滑动时误选。

extends UIFrameWindow

const AVATAR_PROFILE_CELL: PackedScene = preload(
	"res://scripts/module/profile/ui/avatar_profile_cell.tscn"
)
const AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")
const COSTUME_CELL: PackedScene = preload("res://scripts/module/profile/ui/costume_cell.tscn")

@export var tab_bg_wide: Texture2D
@export var tab_bg_narrow: Texture2D

@onready var _header_slot: Control = $Content/HeaderAvatarSlot
@onready var _name_edit: LineEdit = $Content/Nickname/NameEdit
@onready var _tab_group: Control = $Content/TabGroup
@onready var _avatar_tab: Control = $Content/TabGroup/AvatarTab
@onready var _avatar_active: Panel = $Content/TabGroup/AvatarTab/AvatarActive
@onready var _frame_tab: Control = $Content/TabGroup/FrameTab
@onready var _frame_active: Panel = $Content/TabGroup/FrameTab/FrameActive
@onready var _frame_red_dot: TextureRect = $Content/TabGroup/FrameTab/RedDot
@onready var _avatar_red_dot: TextureRect = $Content/TabGroup/AvatarTab/RedDot

@onready var _costume_tab: Control = $Content/TabGroup/CostumeTab
@onready var _costume_active: Panel = $Content/TabGroup/CostumeTab/CostumeActive
@onready var _costume_red_dot: TextureRect = $Content/TabGroup/CostumeTab/RedDot
@onready var _costume_grid: GridContainer = $Content/AvatarScroll/Content/CostumeGrid
@onready var _grid_bg: Panel = $Content/GridBg
@onready var _avatar_grid: GridContainer = $Content/AvatarScroll/Content/AvatarGrid
@onready var _lb_divider: Control = $Content/AvatarScroll/Content/LeaderboardDivider
@onready var _lb_grid: Container = $Content/AvatarScroll/Content/LeaderboardGrid

@onready var _lb_tier_margin: MarginContainer = $Content/AvatarScroll/Content/LeaderboardTierMargin
@onready
var _lb_tier_grid: Container = $Content/AvatarScroll/Content/LeaderboardTierMargin/LeaderboardTierGrid

@onready var _event_divider: Control = $Content/AvatarScroll/Content/EventDivider

@onready var _event_grid: HBoxContainer = $Content/AvatarScroll/Content/EventGrid
@onready var _classic_divider: Control = $Content/AvatarScroll/Content/ClassicDivider
@onready var _classic_grid: GridContainer = $Content/AvatarScroll/Content/ClassicGrid
@onready var _scroll: ScrollContainer = $Content/AvatarScroll
@onready var _bottom_pad: Control = $Content/AvatarScroll/Content/BottomPad
@onready var _lock_tip: Control = $Content/LockTip
@onready var _lock_tip_bubble: Control = $Content/LockTip/Bubble
@onready var _lock_tip_text: Label = $Content/LockTip/Bubble/TipText
@onready var _lock_tip_go: Button = $Content/LockTip/Bubble/GoBtn
@onready var _lock_tip_anim: AnimationPlayer = $AnimationPlayer

const _POPUP_WIDTH: float = 900.0

const _LOCK_TIP_ANIM: StringName = &"Lock"

const _LOCKED_EVENT_AVATAR_ALPHA: float = 80.0 / 255.0
const _LOCK_TIP_MARK: StringName = &"Mark"

const _LOCK_TIP_AUTO_CLOSE_SEC: float = 3.0

const _IME_RESELECT_DELAY: float = 0.1

const _LAYOUT_READY_MAX_FRAMES: int = 12

const _CELL_REVEAL_MARGIN: float = 12.0

const _FRAME_BOTTOM_PAD: float = 0.0

const _FRAME_SCROLL_TOP_DOWN: float = 0.0

const _AVATAR_SCROLL_BOTTOM_EXTEND: float = 20.0

const _FRAME_SCROLL_BOTTOM_EXTEND: float = 0.0

const _LOCK_TIP_FIXED_Y: float = 365.0

const _TIP_TEXT_RIGHT_WITH_GO: float = 540.0
const _TIP_TEXT_RIGHT_NO_GO: float = 740.0

const _TAB_LABEL_PAD: float = 14.0

enum Tab { AVATAR, FRAME, COSTUME }

var _scroll_drag: ScrollDragHelper = null

var _header: Control = null

var _scroll_orig_top: float = 0.0
var _scroll_orig_bottom: float = 0.0

var _tab_descs: Array[Dictionary] = []

var _tab_geo_base: Dictionary = {}

var _tab_group_width: float = 0.0
var _tab_gap: float = 0.0

var _red_dot_right_inset: float = 0.0
var _red_dot_size: float = 0.0

var _costume_cells: Array[CostumeCell] = []

var _costume_refreshing: bool = false

const _COMPANION_SERVICE: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
var _companion_service: RefCounted = _COMPANION_SERVICE.new()

var _show_unowned_event_rewards: bool = false

var _lock_tip_for_event: bool = false


func on_create() -> void:
	_scroll_drag = ScrollDragHelper.attach(_scroll, true)
	_scroll_orig_top = _scroll.offset_top
	_scroll_orig_bottom = _scroll.offset_bottom
	_build_tab_descs()
	_snapshot_tab_geo()

	_header = AVATAR_CELL.instantiate()
	_header_slot.add_child(_header)


var _current_tab: int = Tab.AVATAR

var _pending_avatar_id: int = 0
var _pending_frame_id: int = 0

var _pending_frame_form: int = 0

var _pending_costume_id: int = 0

var _equipped_frame_cell: Control = null

var _lock_tip_closing: bool = false

var _lock_tip_auto_close: Timer = null

var _press_scroll_v: int = 0
const _SCROLL_TAP_TOLERANCE: int = 6

const _TIER_ROW_GAP: int = 20

var _from_rank_open_guide: bool = false


func on_show(params: Dictionary = {}) -> void:
	_from_rank_open_guide = params.get("from_rank_open_guide", false)
	_show_unowned_event_rewards = _companion_service.shows_unowned_event_rewards()
	_lock_tip_for_event = false

	_name_edit.text = ProfileService.get_nickname()
	_name_edit.editable = false

	_lb_tier_margin.add_theme_constant_override(
		"margin_top",
		maxi(0, _TIER_ROW_GAP - _lb_tier_margin.get_parent().get_theme_constant("separation"))
	)

	_lb_divider.get_node("Title").text = tr("PROFILE_FRAME_GROUP_LEADERBOARD")
	_event_divider.get_node("Title").text = tr("PROFILE_FRAME_GROUP_EVENT")
	_classic_divider.get_node("Title").text = tr("PROFILE_FRAME_GROUP_CLASSIC")

	_pending_avatar_id = ProfileService.get_avatar_id()
	_pending_frame_id = ProfileService.get_frame_id()

	_pending_frame_form = (
		ProfileService.get_frame_form()
		if _is_tiered_frame(ProfileCatalog.FIRST_PLACE_FRAME_ID)
		else 0
	)
	_pending_costume_id = ProfileService.get_costume_id()
	_refresh_header()
	_lock_tip.visible = false
	_lock_tip_closing = false

	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	_apply_tab_layout()

	_current_tab = Tab.AVATAR
	_apply_tab()

	_scroll.scroll_vertical = 0

	connect_managed(ProfileService.avatar_frame_changed, _refresh_frame_red_dot)
	_refresh_frame_red_dot()

	if _has_skin_tab():
		connect_managed(ProfileService.costume_changed, _on_costume_changed)

		connect_managed(ClockTicker.second_tick, _on_costume_tick)
	_refresh_costume_red_dot()


func _refresh_header() -> void:
	if _header != null:
		_header.set_info(_pending_avatar_id, _pending_frame_id, _pending_frame_form)


func _refresh_frame_red_dot() -> void:
	if _frame_red_dot != null:
		_frame_red_dot.visible = ProfileService.has_frame_red_dot()
	if _avatar_red_dot != null:
		_avatar_red_dot.visible = ProfileService.has_avatar_red_dot()


func _on_rename_pressed() -> void:
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_RENAME)
	_name_edit.editable = true

	_name_edit.select_all()
	_name_edit.grab_focus()

	if OS.has_feature("android"):
		create_countdown(_IME_RESELECT_DELAY, _resync_ime_select_all)


func _resync_ime_select_all() -> void:
	if not _name_edit.editable or not _name_edit.has_focus():
		return
	var n: int = _name_edit.text.length()
	if n <= 0:
		return
	_name_edit.select_all()
	DisplayServer.virtual_keyboard_show(
		_name_edit.text,
		_name_edit.get_global_rect(),
		DisplayServer.KEYBOARD_TYPE_DEFAULT,
		_name_edit.max_length,
		0,
		n
	)


func _on_name_edit_gui_input(event: InputEvent) -> void:
	if _name_edit.editable:
		return
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if pressed:
		_on_rename_pressed()
		_name_edit.accept_event()


func _on_name_submitted(_new_text: String) -> void:
	_exit_name_edit()


func _on_name_focus_exited() -> void:
	if _name_edit.editable:
		_exit_name_edit()


## 统一结束昵称编辑，处理提交/取消和输入焦点，防止不同退出入口留下编辑态。
func _exit_name_edit() -> void:
	_name_edit.deselect()
	_name_edit.editable = false
	_name_edit.release_focus()


func _on_avatar_tab_pressed() -> void:
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_AVATAR_TAB)
	_switch_tab(Tab.AVATAR)


func _on_frame_tab_pressed() -> void:
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_FRAME_TAB)
	_switch_tab(Tab.FRAME)


func _on_costume_tab_pressed() -> void:
	if not _has_skin_tab():
		return
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_FRAME_TAB)
	_switch_tab(Tab.COSTUME)


## 切换资料类别并重建对应网格，同时更新分页外观、选择态和红点。
func _switch_tab(tab: int) -> void:
	if tab == _current_tab:
		return
	if tab == Tab.COSTUME and not _has_skin_tab():
		return
	_current_tab = tab
	_apply_tab()


func _has_skin_tab() -> bool:
	return ABTestManager.dc_costume.has_costume() or _has_event_skin()


func _has_event_skin() -> bool:
	if _show_unowned_event_rewards:
		return true
	var event_ids: Array[int] = CostumeCatalog.EVENT_COSTUME_IDS
	for id in event_ids:
		if ProfileService.is_costume_held(id):
			return true
	return false


func _skin_tab_ids() -> Array[int]:
	var ids: Array[int] = [CostumeCatalog.DEFAULT_COSTUME_ID]
	var event_ids: Array[int] = CostumeCatalog.EVENT_COSTUME_IDS
	for id in event_ids:
		if _show_unowned_event_rewards or ProfileService.is_costume_held(id):
			ids.append(id)
	if ABTestManager.dc_costume.has_costume():
		ids.append_array(CostumeCatalog.TRIAL_COSTUME_IDS)
	return ids


func _apply_tab() -> void:
	var is_avatar: bool = _current_tab == Tab.AVATAR
	var is_frame: bool = _current_tab == Tab.FRAME
	var is_costume: bool = _current_tab == Tab.COSTUME

	if is_frame:
		ProfileService.clear_frame_red_dot()
	if is_avatar:
		ProfileService.clear_avatar_red_dot()

	if is_costume:
		ProfileService.clear_costume_red_dot()

	_avatar_active.visible = is_avatar
	_frame_active.visible = is_frame
	_costume_active.visible = is_costume

	var grid_sb := _grid_bg.get_theme_stylebox(&"panel") as StyleBoxFlat
	if grid_sb != null:
		grid_sb.corner_radius_top_left = 0 if _current_tab == _leftmost_tab() else 30
		grid_sb.corner_radius_top_right = 0 if _current_tab == _rightmost_tab() else 30

	_avatar_grid.visible = is_avatar
	_lb_divider.visible = is_frame
	_lb_grid.visible = is_frame

	_lb_tier_margin.visible = is_frame and ABTestManager.rank_1st_frame.is_enabled()
	_classic_divider.visible = is_frame
	_classic_grid.visible = is_frame

	if not is_frame:
		_event_divider.visible = false
		_event_grid.visible = false
	_costume_grid.visible = is_costume

	_bottom_pad.custom_minimum_size.y = _FRAME_BOTTOM_PAD if is_frame else 0.0

	var scroll_top_down: float = 0.0
	var scroll_bottom_extend: float = 0.0
	if is_avatar:
		scroll_bottom_extend = _AVATAR_SCROLL_BOTTOM_EXTEND
	elif is_frame:
		scroll_top_down = _FRAME_SCROLL_TOP_DOWN
		scroll_bottom_extend = _FRAME_SCROLL_BOTTOM_EXTEND
	_scroll.offset_top = _scroll_orig_top + scroll_top_down
	_scroll.offset_bottom = _scroll_orig_bottom + scroll_bottom_extend

	if not is_costume:
		_clear_grid(_costume_grid)
		_costume_cells.clear()

	if is_avatar:
		_build_avatar_tab()
	elif is_frame:
		_build_frame_tab()

		_center_scroll_on_equipped_frame()
	else:
		_build_costume_tab()

		_scroll.scroll_vertical = 0
		_kick_scroll_range(Tab.COSTUME)

	_refresh_frame_red_dot()
	_refresh_costume_red_dot()


func _leftmost_tab() -> int:
	return Tab.COSTUME if _has_skin_tab() else Tab.AVATAR


func _rightmost_tab() -> int:
	return Tab.FRAME


func _build_tab_descs() -> void:
	_tab_descs = [
		{
			"root": _costume_tab,
			"label": _costume_tab.get_node("CostumeLab") as Control,
			"active": _costume_active,
			"active_label": _costume_active.get_node("CostumeLabActive") as Control,
			"btn": _costume_tab.get_node("CostumeTabBtn") as Control,
			"red_dot": _costume_red_dot,
		},
		{
			"root": _avatar_tab,
			"label": _avatar_tab.get_node("AvatarLab") as Control,
			"active": _avatar_active,
			"active_label": _avatar_active.get_node("AvatarLabActive") as Control,
			"btn": _avatar_tab.get_node("AvatarTabBtn") as Control,
			"red_dot": _avatar_red_dot,
		},
		{
			"root": _frame_tab,
			"label": _frame_tab.get_node("FrameLab") as Control,
			"active": _frame_active,
			"active_label": _frame_active.get_node("FrameTabActive") as Control,
			"btn": _frame_tab.get_node("FrameTabBtn") as Control,
			"red_dot": _frame_red_dot,
		},
	]


func _snapshot_tab_geo() -> void:
	_tab_group_width = _tab_group.offset_right - _tab_group.offset_left
	_tab_gap = _frame_tab.offset_left - _avatar_tab.offset_right
	var frame_tab_width: float = _frame_tab.offset_right - _frame_tab.offset_left
	_red_dot_right_inset = frame_tab_width - _frame_red_dot.offset_left
	_red_dot_size = _frame_red_dot.offset_right - _frame_red_dot.offset_left
	_tab_geo_base.clear()
	var geo_keys: Array = ["root", "label", "active", "active_label", "btn", "red_dot"]
	for desc in _tab_descs:
		for key: String in geo_keys:
			var node: Control = desc.get(key, null)
			if node != null:
				_tab_geo_base[node] = Vector2(node.offset_left, node.offset_right)


func _apply_tab_layout() -> void:
	var has_costume: bool = _has_skin_tab()
	_costume_tab.visible = has_costume
	if not has_costume:
		var base_nodes: Array = _tab_geo_base.keys()
		for node: Control in base_nodes:
			var span: Vector2 = _tab_geo_base[node]
			node.offset_left = span.x
			node.offset_right = span.y

		_apply_tab_bg(tab_bg_wide)
		return
	_apply_tab_bg(tab_bg_narrow)
	var tab_count: int = _tab_descs.size()
	var tab_width: float = (_tab_group_width - _tab_gap * float(tab_count - 1)) / float(tab_count)
	for i in tab_count:
		_layout_tab(_tab_descs[i], (tab_width + _tab_gap) * float(i), tab_width)


func _apply_tab_bg(tex: Texture2D) -> void:
	if tex == null:
		push_error("ProfilePage: 页签底图 @export 未绑定，页签贴图保持原样")
		return
	for desc in _tab_descs:
		var rect: TextureRect = desc["root"] as TextureRect
		if rect != null:
			rect.texture = tex


func _layout_tab(desc: Dictionary, x: float, width: float) -> void:
	var root: Control = desc["root"]
	root.offset_left = x
	root.offset_right = x + width
	var active: Control = desc["active"]
	active.offset_left = 0.0
	active.offset_right = width
	var btn: Control = desc["btn"]
	btn.offset_left = 0.0
	btn.offset_right = width
	var label: Control = desc["label"]
	label.offset_left = _TAB_LABEL_PAD
	label.offset_right = width - _TAB_LABEL_PAD
	var active_label: Control = desc["active_label"]
	active_label.offset_left = _TAB_LABEL_PAD
	active_label.offset_right = width - _TAB_LABEL_PAD
	var red_dot: Control = desc.get("red_dot", null)
	if red_dot != null:
		red_dot.offset_left = width - _red_dot_right_inset
		red_dot.offset_right = red_dot.offset_left + _red_dot_size


func _build_avatar_tab() -> void:
	_clear_grid(_avatar_grid)
	var include_unowned: Array[int] = (
		ProfileCatalog.EVENT_AVATAR_IDS if _show_unowned_event_rewards else ([] as Array[int])
	)
	var avatar_ids: Array = ProfileService.list_avatar_ids(include_unowned)
	for id in avatar_ids:
		var cell := _make_cell(_avatar_grid)
		cell.setup_avatar(id)

		var locked: bool = not ProfileService.is_avatar_owned(id)
		cell.set_locked(locked)
		cell.set_content_alpha(_LOCKED_EVENT_AVATAR_ALPHA if locked else 1.0)
		cell.set_selected(not locked and id == _pending_avatar_id)


func _build_frame_tab() -> void:
	_clear_grid(_lb_grid)
	_clear_grid(_lb_tier_grid)
	_clear_grid(_classic_grid)
	_clear_grid(_event_grid)
	_equipped_frame_cell = null
	var include_unowned: Array[int] = (
		ProfileCatalog.EVENT_FRAME_IDS if _show_unowned_event_rewards else ([] as Array[int])
	)
	var frame_groups: Array = ProfileService.get_frame_groups(include_unowned)
	var has_event_group: bool = false
	for group in frame_groups:
		if group.get("group", &"") == &"event":
			has_event_group = true
	_event_divider.visible = has_event_group
	_event_grid.visible = has_event_group
	for group in frame_groups:
		var grid: Container = _grid_for_group(group.get("group", &""))
		if grid == null:
			continue
		for id in group.get("ids", []):
			var forms: Array = _forms_for_frame(id)
			for form: int in forms:
				var target: Container = grid
				if form > 0 and _is_tiered_frame(id):
					target = _lb_tier_grid
				var cell := _make_cell(target)
				cell.setup_frame(id, form)
				var locked: bool = not _is_frame_form_unlocked(id, form)
				cell.set_locked(locked)

				var selected: bool = (
					not locked and id == _pending_frame_id and form == _pending_frame_form
				)
				cell.set_selected(selected)
				if selected:
					_equipped_frame_cell = cell

				if locked and _is_tiered_frame(id):
					cell.show_threshold_badge(ProfileCatalog.threshold_for_form(form))


func _forms_for_frame(id: int) -> Array:
	if _is_tiered_frame(id):
		return range(ProfileCatalog.FIRST_FRAME_FORM_COUNT)
	return [0]


func _is_tiered_frame(id: int) -> bool:
	return id == ProfileCatalog.FIRST_PLACE_FRAME_ID and ABTestManager.rank_1st_frame.is_enabled()


func _is_frame_form_unlocked(id: int, form: int) -> bool:
	if _is_tiered_frame(id):
		return ProfileCatalog.is_form_unlocked(form, ProfileService.get_first_place_wins())
	return ProfileService.is_frame_unlocked(id)


func _build_costume_tab() -> void:
	_clear_grid(_costume_grid)
	_costume_cells.clear()
	var ids: Array[int] = _skin_tab_ids()
	for id in ids:
		var cell: CostumeCell = COSTUME_CELL.instantiate()
		_costume_grid.add_child(cell)

		cell.setup(id)
		cell.cell_pressed.connect(_on_costume_cell_pressed)
		cell.cell_pressed_down.connect(_on_costume_cell_pressed_down)
		_costume_cells.append(cell)
	_refresh_costume_cells()


func _refresh_costume_cells() -> void:
	if _costume_refreshing:
		return
	_costume_refreshing = true

	if (
		_pending_costume_id != CostumeCatalog.DEFAULT_COSTUME_ID
		and not ProfileService.is_costume_held(_pending_costume_id)
	):
		_pending_costume_id = ProfileService.get_costume_id()
	for cell in _costume_cells:
		if not is_instance_valid(cell):
			continue
		var id: int = cell.get_id()
		var held: bool = ProfileService.is_costume_held(id)
		cell.set_hold_state(held, ProfileService.costume_trial_remaining_sec(id))
		cell.set_selected(held and id == _pending_costume_id)
	_costume_refreshing = false


func _on_costume_cell_pressed(id: int) -> void:
	if _is_scroll_drag_release():
		return
	if not ProfileService.is_costume_held(id):
		return
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_FRAME_SELECT)
	if id == _pending_costume_id and id != CostumeCatalog.DEFAULT_COSTUME_ID:
		_pending_costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	else:
		_pending_costume_id = id
	_refresh_costume_cells()


func _on_costume_cell_pressed_down(_id: int) -> void:
	_press_scroll_v = _scroll.scroll_vertical


func _on_costume_changed() -> void:
	_refresh_costume_red_dot()
	if _current_tab == Tab.COSTUME:
		_refresh_costume_cells()


func _on_costume_tick() -> void:
	if _current_tab != Tab.COSTUME:
		return
	_refresh_costume_cells()


func _refresh_costume_red_dot() -> void:
	if _costume_red_dot == null:
		return
	_costume_red_dot.visible = _has_skin_tab() and ProfileService.has_costume_red_dot()


func _grid_for_group(group: StringName) -> Container:
	match group:
		&"leaderboard":
			return _lb_grid
		&"event":
			return _event_grid
		&"classic":
			return _classic_grid
		_:
			return null


func _center_scroll_on_equipped_frame() -> void:
	var ready: bool = false
	for _i in range(_LAYOUT_READY_MAX_FRAMES):
		_scroll.queue_sort()
		await get_tree().process_frame
		if not is_showing() or _current_tab != Tab.FRAME:
			return
		if _v_scroll_range() > 0.0:
			ready = true
			break
	if _equipped_frame_cell == null or not is_instance_valid(_equipped_frame_cell):
		_scroll.scroll_vertical = 0
		return
	if not ready:
		return

	var cell_center: float = (
		(_equipped_frame_cell.global_position.y - _scroll.global_position.y)
		+ float(_scroll.scroll_vertical)
		+ _equipped_frame_cell.size.y * 0.5
	)

	_scroll.scroll_vertical = int(round(cell_center - _scroll.size.y * 0.5))


func _v_scroll_range() -> float:
	var vbar: VScrollBar = _scroll.get_v_scroll_bar()
	if vbar == null:
		return 0.0
	return maxf(0.0, vbar.get_max() - vbar.get_page())


func _kick_scroll_range(tab: int) -> void:
	for _i in range(_LAYOUT_READY_MAX_FRAMES):
		_scroll.queue_sort()
		await get_tree().process_frame
		if not is_showing() or _current_tab != tab:
			return
		if _v_scroll_range() > 0.0:
			return


func _make_cell(grid: Container) -> Control:
	var cell: Control = AVATAR_PROFILE_CELL.instantiate()
	grid.add_child(cell)
	cell.cell_pressed.connect(_on_cell_pressed)
	cell.cell_locked_pressed.connect(_on_frame_locked_pressed.bind(cell))
	cell.cell_pressed_down.connect(_on_cell_pressed_down)
	return cell


func _on_cell_pressed_down(_id: int, _form: int) -> void:
	_press_scroll_v = _scroll.scroll_vertical


## 区分滑动后的松手与真正点击；滚动浏览时不应误触发装备或锁定说明。
func _is_scroll_drag_release() -> bool:
	return absi(_scroll.scroll_vertical - _press_scroll_v) > _SCROLL_TAP_TOLERANCE


func _apply_lock_tip_layout() -> void:
	var go_shown: bool = (
		not _from_rank_open_guide
		and (
			_show_unowned_event_rewards if _lock_tip_for_event else RankActivityManager.is_running()
		)
	)
	_lock_tip_go.visible = go_shown
	if go_shown:
		_lock_tip_text.offset_right = _TIP_TEXT_RIGHT_WITH_GO
		_lock_tip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_lock_tip_text.offset_right = _TIP_TEXT_RIGHT_NO_GO
		_lock_tip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_frame_locked_pressed(id: int, _form: int, cell: Control) -> void:
	if _is_scroll_drag_release():
		return
	_lock_tip_for_event = (
		ProfileCatalog.EVENT_AVATAR_IDS.has(id) and _current_tab == Tab.AVATAR
		or ProfileCatalog.EVENT_FRAME_IDS.has(id) and _current_tab == Tab.FRAME
	)
	if _lock_tip_for_event:
		_lock_tip_text.text = (
			tr("PROFILE_EVENT_AVATAR_HINT")
			if _current_tab == Tab.AVATAR
			else tr("PROFILE_EVENT_FRAME_HINT")
		)
	else:
		_lock_tip_text.text = tr("PROFILE_FIRST_PLACE_FRAME_HINT")

	_scroll_cell_to_top(cell)
	_apply_lock_tip_layout()

	var bx: float = (_POPUP_WIDTH - _lock_tip_bubble.size.x) * 0.5
	_lock_tip_bubble.position = Vector2(bx, _LOCK_TIP_FIXED_Y)
	_lock_tip.visible = true
	_lock_tip_closing = false

	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_tip_anim.play_section_with_markers(_LOCK_TIP_ANIM, &"", _LOCK_TIP_MARK)

	_cancel_lock_tip_auto_close()
	_lock_tip_auto_close = create_countdown(_LOCK_TIP_AUTO_CLOSE_SEC, _close_lock_tip)


func _on_lock_tip_dismiss() -> void:
	_cancel_lock_tip_auto_close()
	_close_lock_tip()


func _on_lock_tip_go() -> void:
	_cancel_lock_tip_auto_close()
	_close_lock_tip()
	UIManager.hide_ui(UiName.PROFILE)
	if _lock_tip_for_event:
		var home: UIFrameWindow = UIManager.get_ui(UiName.HOME)
		if home != null and home.is_showing() and home.has_method("enter_main_level"):
			UIManager.hide_all_except([UiName.HOME, UiName.GAME])
			home.enter_main_level()
		return
	RankActivityManager.open_home_entry()


func _cancel_lock_tip_auto_close() -> void:
	if _lock_tip_auto_close != null and is_instance_valid(_lock_tip_auto_close):
		remove_timer(_lock_tip_auto_close)
	_lock_tip_auto_close = null


func _close_lock_tip() -> void:
	if not _lock_tip.visible or _lock_tip_closing:
		return
	_lock_tip_closing = true
	_lock_tip_anim.play_section_with_markers(_LOCK_TIP_ANIM, _LOCK_TIP_MARK, &"")
	await _lock_tip_anim.animation_finished
	if not _lock_tip_closing:
		return
	_lock_tip_closing = false
	_lock_tip.visible = false

	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP


func _clear_grid(grid: Container) -> void:
	for c in grid.get_children():
		c.queue_free()


func _on_cell_pressed(id: int, form: int) -> void:
	if _is_scroll_drag_release():
		return
	var selected_cell: Control = null
	if _current_tab == Tab.AVATAR:
		_pending_avatar_id = id
		_refresh_selection(_avatar_grid, id, form)
		selected_cell = _find_cell_in(_avatar_grid, id, form)
	else:
		_pending_frame_id = id
		_pending_frame_form = form
		_refresh_selection(_lb_grid, id, form)
		_refresh_selection(_lb_tier_grid, id, form)
		_refresh_selection(_event_grid, id, form)
		_refresh_selection(_classic_grid, id, form)
		selected_cell = _find_cell_in(_lb_grid, id, form)
		if selected_cell == null:
			selected_cell = _find_cell_in(_lb_tier_grid, id, form)
		if selected_cell == null:
			selected_cell = _find_cell_in(_event_grid, id, form)
		if selected_cell == null:
			selected_cell = _find_cell_in(_classic_grid, id, form)

	_refresh_header()

	_ensure_cell_fully_visible(selected_cell)


func _find_cell_in(grid: Container, id: int, form: int) -> Control:
	for c in grid.get_children():
		if c.get_id() == id and c.get_form() == form:
			return c
	return null


func _ensure_cell_fully_visible(cell: Control) -> void:
	if cell == null or not is_instance_valid(cell):
		return
	if _v_scroll_range() <= 0.0:
		return
	var top: float = cell.global_position.y - _scroll.global_position.y
	var bottom: float = top + cell.size.y
	var vh: float = _scroll.size.y
	var delta: float = 0.0
	if top < 0.0:
		delta = top - _CELL_REVEAL_MARGIN
	elif bottom > vh:
		delta = (bottom - vh) + _CELL_REVEAL_MARGIN
	if delta != 0.0:
		_scroll.scroll_vertical = int(round(float(_scroll.scroll_vertical) + delta))


func _scroll_cell_to_top(cell: Control) -> void:
	if cell == null or not is_instance_valid(cell):
		return
	if _v_scroll_range() <= 0.0:
		return
	var top: float = cell.global_position.y - _scroll.global_position.y
	_scroll.scroll_vertical = int(round(float(_scroll.scroll_vertical) + top - _CELL_REVEAL_MARGIN))


func _refresh_selection(grid: Container, selected_id: int, selected_form: int) -> void:
	for c in grid.get_children():
		c.set_selected(c.get_id() == selected_id and c.get_form() == selected_form)


## 完成本次资料编辑并通知保存，后续账号同步由服务层联动处理。
func _on_confirm_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.SAVE, self)
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_AVATAR_SELECT)
	ProfileService.set_nickname(_name_edit.text)
	ProfileService.set_avatar_id(_pending_avatar_id)
	ProfileService.set_frame_id(_pending_frame_id)
	ProfileService.set_frame_form(_pending_frame_form)
	if _pending_costume_id == CostumeCatalog.DEFAULT_COSTUME_ID:
		ProfileService.clear_costume_equip()
	else:
		ProfileService.set_costume_id(_pending_costume_id)
	ProfileService.notify_profile_saved()
	_name_edit.text = ProfileService.get_nickname()
	_refresh_header()
	UIManager.hide_ui(UiName.PROFILE)


func get_dlg_name() -> String:
	return Tracker.Dlg.AVATAR


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	VibrateManager.play_at(VibrateManager.Pos.PROFILE_FRAME_SELECT)
	UIManager.hide_ui(UiName.PROFILE)
