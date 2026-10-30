## 猫咪进度条：把棋盘进度整理为槽位快照，协调颜色、装扮和错标显示。
class_name CatProgressBar
extends Control

const MAX_SLOTS: int = 12

const DESIGN_SLOT: float = 66.0

const DESIGN_SLOT_DENSE: float = 62.0

const DESIGN_PADDING: float = 24.0

const DESIGN_SLOT_GAP: float = 2.0

const DESIGN_PITCH: float = DESIGN_SLOT + DESIGN_SLOT_GAP

const DESIGN_MAX_BAR_WIDTH_MAIN: float = 760.0

const ADJACENT_SLOT: float = 68.0

const ADJACENT_PITCH: float = 69.0

const ADJACENT_PADDING: float = 56.0

const ADJACENT_BG_SIDE_INSET: float = 30.0

const ADJACENT_BG_TOP_CORNER_RADIUS: float = 40.0

const ADJACENT_BG_FILLET_RADIUS: float = 30.0

const ADJACENT_BG_FILLET_BASELINE_Y: float = 78.5


static func solve_metrics(total: int, max_bar_width: float) -> Dictionary:
	var count: int = clampi(total, 1, MAX_SLOTS)
	var ideal_width: float = DESIGN_SLOT + DESIGN_PITCH * float(count - 1) + DESIGN_PADDING * 2.0
	if max_bar_width <= 0.0 or ideal_width <= max_bar_width:
		return {
			"slot": Vector2(DESIGN_SLOT, DESIGN_SLOT),
			"pitch": DESIGN_PITCH,
			"padding": DESIGN_PADDING,
		}
	var content_width: float = max_bar_width - DESIGN_PADDING * 2.0
	var pitch: float = DESIGN_PITCH
	if count > 1:
		pitch = (content_width - DESIGN_SLOT_DENSE) / float(count - 1)
	return {
		"slot": Vector2(DESIGN_SLOT_DENSE, DESIGN_SLOT_DENSE),
		"pitch": pitch,
		"padding": DESIGN_PADDING,
	}


static func build_snapshot(
	region_order: Array[int],
	regions_with_cat: Dictionary,
	region_color_getter: Callable,
	with_tints: bool
) -> Dictionary:
	var tints: PackedColorArray = PackedColorArray()
	var revealed: Array[bool] = []
	for reg: int in region_order:
		revealed.append(regions_with_cat.has(reg))
		if not with_tints:
			continue

		var tint: Color = region_color_getter.call(reg)
		tint.a = CatProgressSlot.COLORED_SILHOUETTE_ALPHA
		tints.append(tint)
	return {"total": region_order.size(), "tints": tints, "revealed": revealed}


const SOFT_SHADOW_SIZE: int = 12
const SOFT_SHADOW_OFFSET: Vector2 = Vector2(0, 8)
const SOFT_SHADOW_ALPHA: float = 0.05

var _slots: Array[CatProgressSlot] = []
var _total: int = 0
var _tints: PackedColorArray = PackedColorArray()
var _revealed: Array[bool] = []

var _cat_costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID

var _cat_costume_on: bool = false

var _colored: bool = false

const _COMPACT_MOVE_DUR: float = 0.35

const _COMPACT_MOVE_DUR_FAR: float = 0.5
const _COMPACT_MOVE_FAR_SLOTS: float = 5.0

const _FACE_POP_DUR: float = 0.35

const _COMPACT_STAGGER: float = 0.03
var _compact: bool = false
var _found_order: Array[int] = []
var _slot_left: float = 0.0
var _slot_pitch: float = 0.0
var _slot_top: float = 0.0
var _slot_tweens: Array[Tween] = []

var _slot_target: Array[float] = []

var _first_update: bool = false


func _ready() -> void:
	_collect_slots()


func use_soft_shadow() -> void:
	var bg: Panel = get_node_or_null("Bg") as Panel
	if bg == null:
		return
	var base: StyleBox = bg.get_theme_stylebox("panel")
	if not (base is StyleBoxFlat):
		return
	var sb: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	var c: Color = sb.shadow_color
	c.a = SOFT_SHADOW_ALPHA
	sb.shadow_color = c
	sb.shadow_size = SOFT_SHADOW_SIZE
	sb.shadow_offset = SOFT_SHADOW_OFFSET
	bg.add_theme_stylebox_override("panel", sb)


func _collect_slots() -> void:
	if not _slots.is_empty():
		return
	var children: Array[Node] = get_children()
	for c: Node in children:
		if c is CatProgressSlot:
			_slots.append(c as CatProgressSlot)


func setup(total: int, slot_px: Vector2, pitch: float, padding: float) -> void:
	_collect_slots()
	for tw: Tween in _slot_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_compact = false
	_found_order.clear()
	_total = clampi(total, 0, MAX_SLOTS)
	_revealed.clear()
	_revealed.resize(_total)
	var content_w: float = slot_px.x + pitch * float(maxi(_total - 1, 0))
	var left: float = padding
	size.x = content_w + padding * 2.0
	var top: float = (size.y - slot_px.y) * 0.5
	for i in _slots.size():
		var slot: CatProgressSlot = _slots[i]
		var in_use: bool = i < _total
		slot.visible = in_use
		if not in_use:
			continue
		slot.size = slot_px
		slot.position = Vector2(left + pitch * float(i), top)
	_refresh()


func set_cat_costume(costume_id: int, use_costume: bool) -> void:
	_cat_costume_id = (
		costume_id if CostumeCatalog.is_valid(costume_id) else CostumeCatalog.DEFAULT_COSTUME_ID
	)
	_cat_costume_on = use_costume
	_collect_slots()
	for slot: CatProgressSlot in _slots:
		slot.set_cat_costume(_cat_costume_id, _cat_costume_on)


func set_colored_mode(colored: bool) -> void:
	_colored = colored
	_refresh()


func set_done_dot_mode(on: bool) -> void:
	_collect_slots()
	for slot: CatProgressSlot in _slots:
		slot.set_done_dot_mode(on)


func set_wrong_marks(flags: Array) -> void:
	_collect_slots()
	for i in _slots.size():
		_slots[i].set_wrong_mark(i < _total and i < flags.size() and bool(flags[i]))


func set_tints(tints: PackedColorArray) -> void:
	_tints = tints
	_refresh()


func set_revealed(flags: Array) -> void:
	_revealed.clear()
	_revealed.resize(_total)
	for i in mini(flags.size(), _total):
		_revealed[i] = bool(flags[i])
	_refresh()


func set_revealed_count(count: int) -> void:
	_revealed.clear()
	_revealed.resize(_total)
	var lit: int = clampi(count, 0, _total)
	for i in lit:
		_revealed[i] = true
	_refresh()


func _refresh() -> void:
	for i in _total:
		if i >= _slots.size():
			break
		_slots[i].apply_state(_revealed[i], _tint_for(i), _colored)


func _tint_for(i: int) -> Color:
	if _colored and i < _tints.size():
		return _tints[i]
	return CatProgressSlot.DESIGN_TINT


func setup_compact(
	total: int, slot_px: Vector2, pitch: float, padding: float, tints: PackedColorArray
) -> void:
	_collect_slots()
	for tw: Tween in _slot_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_compact = true
	_colored = true
	_total = clampi(total, 0, MAX_SLOTS)
	_tints = tints
	_found_order.clear()
	_first_update = true
	_revealed.clear()
	_revealed.resize(_total)
	_slot_tweens.resize(_slots.size())
	_slot_target.resize(_slots.size())
	var content_w: float = slot_px.x + pitch * float(maxi(_total - 1, 0))
	size.x = content_w + padding * 2.0
	_slot_left = padding
	_slot_pitch = pitch
	_slot_top = (size.y - slot_px.y) * 0.5
	for i in _slots.size():
		var slot: CatProgressSlot = _slots[i]
		var in_use: bool = i < _total
		slot.visible = in_use
		if not in_use:
			continue
		slot.size = slot_px
		slot.position = Vector2(_slot_left + pitch * float(i), _slot_top)
		_slot_target[i] = slot.position.x
		slot.apply_state(false, _tint_for(i), true)


func compact_found_order() -> Array[int]:
	return _found_order.duplicate()


func restore_compact(found: Array, order: Array) -> void:
	if not _compact:
		return
	_found_order.clear()
	for entry: Variant in order:
		if not (entry is int):
			continue
		var i: int = entry
		if (
			i >= 0
			and i < _total
			and i < found.size()
			and bool(found[i])
			and not _found_order.has(i)
		):
			_found_order.append(i)
	_first_update = true
	update_compact(found)


func update_compact(found: Array) -> void:
	if not _compact:
		return

	var still: Array[int] = []
	for idx: int in _found_order:
		if idx < found.size() and bool(found[idx]):
			still.append(idx)
	_found_order = still
	var has_new: bool = false
	for i in _total:
		if i < found.size() and bool(found[i]) and not _found_order.has(i):
			_found_order.append(i)
			has_new = true

	var instant: bool = _first_update
	_first_update = false

	var move_delay: float = _FACE_POP_DUR if (has_new and not instant) else 0.0

	var k: int = _found_order.size()
	var not_found_rank: int = 0

	var target_of: Array[int] = []
	target_of.resize(_slots.size())
	var found_of: Array[bool] = []
	found_of.resize(_slots.size())
	var right_movers: Array[int] = []
	for i in _total:
		if i >= _slots.size():
			break
		var is_found: bool = _found_order.has(i)
		var target_pos: int
		if is_found:
			target_pos = _found_order.find(i)
		else:
			target_pos = k + not_found_rank
			not_found_rank += 1
		target_of[i] = target_pos
		found_of[i] = is_found
		if not is_found:
			var tx: float = _slot_left + _slot_pitch * float(target_pos)
			if not is_equal_approx(_slots[i].position.x, tx):
				right_movers.append(i)

	right_movers.sort_custom(func(a: int, b: int) -> bool: return target_of[a] > target_of[b])
	var stagger_delay: Dictionary = {}
	for si in right_movers.size():
		stagger_delay[right_movers[si]] = _COMPACT_STAGGER * float(si)

	for i in _total:
		if i >= _slots.size():
			break
		if instant:
			if i < _slot_tweens.size() and _slot_tweens[i] != null and _slot_tweens[i].is_valid():
				_slot_tweens[i].kill()
			_slots[i].position.x = _slot_left + _slot_pitch * float(target_of[i])
			if i < _slot_target.size():
				_slot_target[i] = _slots[i].position.x
		else:
			var this_delay: float = move_delay
			if not found_of[i]:
				this_delay = move_delay + float(stagger_delay.get(i, 0.0))
			_tween_slot_to(i, target_of[i], this_delay)
		var fnd: bool = i < found.size() and bool(found[i])
		if i < _revealed.size():
			_revealed[i] = fnd
		_slots[i].apply_state(fnd, _tint_for(i), true)


func _tween_slot_to(i: int, target_pos: int, delay: float = 0.0) -> bool:
	var target_x: float = _slot_left + _slot_pitch * float(target_pos)
	var slot: CatProgressSlot = _slots[i]
	var tween_alive: bool = (
		i < _slot_tweens.size() and _slot_tweens[i] != null and _slot_tweens[i].is_valid()
	)

	if tween_alive and i < _slot_target.size() and is_equal_approx(_slot_target[i], target_x):
		return false
	if is_equal_approx(slot.position.x, target_x):
		if (
			tween_alive
			and i < _slot_target.size()
			and not is_equal_approx(_slot_target[i], target_x)
		):
			_slot_tweens[i].kill()
		if i < _slot_target.size():
			_slot_target[i] = target_x
		return false
	if tween_alive:
		_slot_tweens[i].kill()
		delay = 0.0

	var tw: Tween = create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)

	var span: float = absf(target_x - slot.position.x) / maxf(_slot_pitch, 1.0)
	var dur: float = _COMPACT_MOVE_DUR_FAR if span > _COMPACT_MOVE_FAR_SLOTS else _COMPACT_MOVE_DUR
	tw.tween_property(slot, "position:x", target_x, dur).set_ease(Tween.EASE_IN_OUT).set_trans(
		Tween.TRANS_SINE
	)
	if i < _slot_tweens.size():
		_slot_tweens[i] = tw
	if i < _slot_target.size():
		_slot_target[i] = target_x
	return true
