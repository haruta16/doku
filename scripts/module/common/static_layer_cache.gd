## 静态图层缓存：识别页面静止时机，把静态节点渲染到 SubViewport 并与动态节点分层显示。
extends RefCounted
class_name StaticLayerCache

const STATIC_BIT: int = 1 << 1

const DYNAMIC_NODE_NAMES: Array[StringName] = [&"CatBatchLayer"]

const AMBIENT_GROUP: StringName = &"slc_ambient"

const _CAT_IDLE_ANIM: StringName = &"CatIconIdle"

var _page: Control = null
var _vp: SubViewport = null
var _rect: TextureRect = null
var _active: bool = false
var _dirty: bool = true
var _tagged: bool = false
var _dynamic_ids: Dictionary = {}
var _keep_ids: Dictionary = {}
var _mark_dirty_cb: Callable = _mark_dirty

var refresh_count: int = 0

var toggle_count: int = 0
var last_off_reason: String = ""

var cost_tween_us: float = 0.0
var cost_quiet_us: float = 0.0

const _TRACE_MAX: int = 160
var _trace: PackedStringArray = PackedStringArray()


func trace(ev: String) -> void:
	if _trace.size() >= _TRACE_MAX:
		_trace.remove_at(0)
	_trace.append("%d@%d %s" % [Engine.get_frames_drawn(), Time.get_ticks_msec(), ev])


func trace_dump(clear: bool = true) -> PackedStringArray:
	var out: PackedStringArray = _trace.duplicate()
	if clear:
		_trace.clear()
	return out


func is_active() -> bool:
	return _active and _shown


func page() -> Control:
	return _page


const _QUIET_RECHECK_FRAMES: int = 3
var _quiet_cached: bool = false
var _quiet_countdown: int = 0


## 页面切换先销毁旧缓存；只有无 Tween 且页面静止时才开启，并在脏标记出现时重绘。
func update(page: Control, want: bool) -> void:
	if page != _page:
		_teardown()
		_page = page
	if _page == null or not is_instance_valid(_page) or not _page.is_visible_in_tree():
		_quiet_countdown = 0
		_quiet_cached = false
		_set_active(false, "no page")
		return
	if not _tagged:
		_tag_page()

	var reason: String = ""
	var t0: int = Time.get_ticks_usec()
	var tw_busy: bool = not _page.get_tree().get_processed_tweens().is_empty()
	var t1: int = Time.get_ticks_usec()
	if tw_busy:
		_quiet_cached = false
		_quiet_countdown = 0
		reason = "tween"
	else:
		_quiet_countdown -= 1
		if _quiet_countdown <= 0:
			_quiet_countdown = _QUIET_RECHECK_FRAMES
			reason = quiet_blocker()
			_quiet_cached = reason == ""
	var t2: int = Time.get_ticks_usec()
	cost_tween_us = lerpf(cost_tween_us, float(t1 - t0), 0.1)
	cost_quiet_us = lerpf(cost_quiet_us, float(t2 - t1), 0.1)
	if not want:
		reason = "not idle"
	_set_active(want and _quiet_cached, reason)

	_dirty_streak = _dirty_streak + 1 if _dirty_frame else 0
	_dirty_frame = false
	if _active and _dirty:
		_dirty = false
		refresh_count += 1
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		trace("refresh shown=%s" % str(_shown))
		if not _shown:
			_arm_frames = _ARM_FRAMES

	if _active:
		_sync_rect_z()
		_sync_rect_xform()
		if not _shown:
			_arm_frames -= 1
			if _arm_frames <= 0:
				_show(true)


const _ARM_FRAMES: int = 2
var _arm_frames: int = 0

var _shown: bool = false


func disable() -> void:
	_set_active(false, "touch/wake")


func is_page_quiet(page: Control) -> bool:
	return page != null and page == _page and _quiet_cached


## 启用时创建缓存视口并安排首帧更新，停用时恢复原显示并停止缓存渲染。
func _set_active(on: bool, reason: String = "") -> void:
	if on == _active:
		return
	toggle_count += 1
	trace("active=%s reason=%s" % [str(on), reason])
	if not on:
		last_off_reason = reason
	var root: Window = _page.get_tree().root if _page != null and is_instance_valid(_page) else null
	if on:
		_ensure_viewport()
		_dirty = true
		_arm_frames = _ARM_FRAMES
		_shown = false
	else:
		_show(false)
		if _vp != null and is_instance_valid(_vp):
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = on


func _show(on: bool) -> void:
	if on != _shown:
		trace("shown=%s" % str(on))
	var root: Window = _page.get_tree().root if _page != null and is_instance_valid(_page) else null
	if on:
		if root != null:
			root.canvas_cull_mask = 4294967295 & ~STATIC_BIT
		if _rect != null and is_instance_valid(_rect):
			_rect.modulate.a = 1.0
	else:
		if root != null:
			root.canvas_cull_mask = 4294967295
		if _rect != null and is_instance_valid(_rect):
			_rect.modulate.a = 0.0
	_lift_ambient(on)
	_shown = on


func _mark_dirty() -> void:
	if not _dirty_frame and _shown:
		trace("dirty(shown)")
	_dirty = true
	_dirty_frame = true


var _dirty_frame: bool = false


func _is_quiet() -> bool:
	return quiet_blocker() == ""


func quiet_blocker() -> String:
	if _page == null or not is_instance_valid(_page):
		return "no page"
	if not _page.get_tree().get_processed_tweens().is_empty():
		return "tweens=%d" % _page.get_tree().get_processed_tweens().size()
	for id: int in _playing.keys():
		var p: AnimationPlayer = instance_from_id(id) as AnimationPlayer
		if (
			p == null
			or not is_instance_valid(p)
			or not p.is_playing()
			or p.current_animation == _CAT_IDLE_ANIM
		):
			_playing.erase(id)
			continue
		var host: CanvasItem = p.get_parent() as CanvasItem
		if host == null or host.is_visible_in_tree():
			return "anim %s:%s" % [_page.get_path_to(p), p.current_animation]

	for id: int in _active_particles.keys():
		var e: Node = instance_from_id(id) as Node

		if (
			e == null
			or not is_instance_valid(e)
			or not e.is_processing_internal()
			or not (e as CanvasItem).is_visible_in_tree()
		):
			_active_particles.erase(id)
			continue
		return "particles %s" % _page.get_path_to(e)

	if _dirty_streak >= _DIRTY_STREAK_LIMIT:
		return "dirty_streak=%d" % _dirty_streak
	return ""


var _dirty_streak: int = 0
const _DIRTY_STREAK_LIMIT: int = 3

var _playing: Dictionary = {}

var _active_particles: Dictionary = {}


func _on_particle_draw(e: Node) -> void:
	if e.is_processing_internal() and (e as CanvasItem).is_visible_in_tree():
		_active_particles[e.get_instance_id()] = true

		_quiet_countdown = 0


func _on_anim_started(_name: StringName, p: AnimationPlayer) -> void:
	if p.current_animation != _CAT_IDLE_ANIM:
		trace(
			(
				"anim_start %s:%s"
				% [p.get_parent().name if p.get_parent() else "?", p.current_animation]
			)
		)
		_playing[p.get_instance_id()] = true

		_quiet_countdown = 0


func _watch_player(p: AnimationPlayer) -> void:
	if not p.has_meta(&"_slc_awatch"):
		p.set_meta(&"_slc_awatch", true)
		p.animation_started.connect(_on_anim_started.bind(p))
	if p.is_playing() and p.current_animation != _CAT_IDLE_ANIM:
		_playing[p.get_instance_id()] = true


func _tag_page() -> void:
	_tagged = true
	_dynamic_ids.clear()
	_keep_ids.clear()
	_playing.clear()
	_active_particles.clear()
	var dyn_z: int = 1 << 30
	for n: Node in _page.find_children("*", "", true, false):
		if StringName(n.name) in DYNAMIC_NODE_NAMES and n is CanvasItem:
			_dynamic_ids[n.get_instance_id()] = true
			dyn_z = mini(dyn_z, _abs_z(n as CanvasItem))

	if dyn_z < (1 << 30):
		for n: Node in _page.find_children("*", "CanvasItem", true, false):
			var ci: CanvasItem = n as CanvasItem
			if not _under_dynamic(ci) and _abs_z(ci) >= dyn_z:
				_dynamic_ids[ci.get_instance_id()] = true

	_ambient_ids.clear()
	for n: Node in _page.get_tree().get_nodes_in_group(AMBIENT_GROUP):
		if n is CanvasItem and _page.is_ancestor_of(n) and not _under_dynamic(n):
			_dynamic_ids[n.get_instance_id()] = true
			_ambient_ids[n.get_instance_id()] = true
	for id: int in _dynamic_ids.keys():
		var a: Node = instance_from_id(id) as Node
		a = a.get_parent() if a != null else null
		while a != null and a != _page.get_parent():
			_keep_ids[a.get_instance_id()] = true
			a = a.get_parent()

	var rect_host: Node = _rect_host()
	var h: Node = rect_host
	while h != null and h != _page.get_parent():
		_keep_ids[h.get_instance_id()] = true
		h = h.get_parent()

	if dyn_z >= (1 << 30):
		var mx: int = _abs_z(_page)
		for n: Node in _page.find_children("*", "CanvasItem", true, false):
			mx = maxi(mx, _abs_z(n as CanvasItem))
		dyn_z = mx + 1
	_tag_subtree(_page)
	if not _page.get_tree().node_added.is_connected(_on_node_added):
		_page.get_tree().node_added.connect(_on_node_added)
	_dyn_z = dyn_z
	_dyn_z_rel_page = dyn_z - _abs_z(_page)


var _dyn_z: int = 0

var _dyn_z_rel_page: int = 0


func _rect_host() -> Node:
	var host: Node = _page.get_node_or_null(^"Root")
	return host if host is CanvasItem else _page


func _tag_subtree(start: Node) -> void:
	var stack: Array[Node] = [start]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _dynamic_ids.has(n.get_instance_id()):
			continue
		if n == _rect or n == _vp:
			continue
		if n is CanvasLayer:
			_watch_subtree(n)
			continue
		if n is Viewport:
			continue
		_tag_one(n)
		for c: Node in n.get_children():
			stack.push_back(c)


func _watch_subtree(root: Node) -> void:
	for n: Node in root.find_children("*", "", true, false):
		_watch_one(n)


func _watch_one(n: Node) -> void:
	if n is AnimationPlayer:
		_watch_player(n as AnimationPlayer)
	if (n is CPUParticles2D or n is GPUParticles2D) and not _is_ambient(n):
		if n.is_processing_internal() and (n as CanvasItem).is_visible_in_tree():
			_active_particles[n.get_instance_id()] = true
		var pci: CanvasItem = n as CanvasItem

		if not pci.has_meta(&"_slc_pwatch"):
			pci.set_meta(&"_slc_pwatch", true)
			pci.draw.connect(_on_particle_draw.bind(n))


func _tag_one(n: Node) -> void:
	_watch_one(n)
	if not (n is CanvasItem):
		return
	var ci: CanvasItem = n as CanvasItem
	ci.visibility_layer = (1 | STATIC_BIT) if _keep_ids.has(ci.get_instance_id()) else STATIC_BIT
	if not ci.draw.is_connected(_mark_dirty_cb):
		ci.draw.connect(_mark_dirty_cb)
		ci.visibility_changed.connect(_mark_dirty_cb)
		if ci is Control:
			(ci as Control).item_rect_changed.connect(_mark_dirty_cb)


func _on_node_added(n: Node) -> void:
	if _page == null or not is_instance_valid(_page) or not _tagged:
		return

	if n == _rect or (_rect != null and is_instance_valid(_rect) and _rect.is_ancestor_of(n)):
		return
	if not _page.is_ancestor_of(n) or _under_dynamic(n):
		return

	if n is CanvasLayer or _under_canvas_layer(n):
		_watch_one(n)
		return
	if _under_excluded(n):
		return

	if StringName(n.name) in DYNAMIC_NODE_NAMES and n is CanvasItem:
		_tagged = false
		_set_active(false, "dynamic layer added")
		return

	if (
		n is CanvasItem
		and (n.is_in_group(AMBIENT_GROUP) or _abs_z(n as CanvasItem) >= _current_dyn_z())
	):
		_dynamic_ids[n.get_instance_id()] = true
		if n.is_in_group(AMBIENT_GROUP):
			_ambient_ids[n.get_instance_id()] = true

			if _shown:
				_lift_ambient(true)
		var a: Node = n.get_parent()
		while a != null and a != _page.get_parent():
			if not _keep_ids.has(a.get_instance_id()):
				_keep_ids[a.get_instance_id()] = true
				if a is CanvasItem:
					(a as CanvasItem).visibility_layer = 1 | STATIC_BIT
			a = a.get_parent()
		_dirty = true
		return
	_tag_one(n)
	_dirty = true


func _under_dynamic(n: Node) -> bool:
	var a: Node = n
	while a != null and a != _page:
		if _dynamic_ids.has(a.get_instance_id()):
			return true
		a = a.get_parent()
	return false


var _ambient_ids: Dictionary = {}

const _AMBIENT_Z_META: StringName = &"_slc_ambient_z"


func _lift_ambient(on: bool) -> void:
	for id: int in _ambient_ids.keys():
		var ci: CanvasItem = instance_from_id(id) as CanvasItem
		if ci == null or not is_instance_valid(ci):
			_ambient_ids.erase(id)
			continue
		if on:
			if not ci.has_meta(_AMBIENT_Z_META):
				ci.set_meta(_AMBIENT_Z_META, ci.z_index)
			var base: int = int(ci.get_meta(_AMBIENT_Z_META))

			var parent_abs: int = (
				_abs_z(ci.get_parent() as CanvasItem)
				if ci.z_as_relative and ci.get_parent() is CanvasItem
				else 0
			)
			var rect_abs: int = _current_dyn_z() - 1
			var want: int = maxi(base, rect_abs - parent_abs)
			if ci.z_index != want:
				ci.z_index = want
		elif ci.has_meta(_AMBIENT_Z_META):
			var orig: int = int(ci.get_meta(_AMBIENT_Z_META))
			ci.remove_meta(_AMBIENT_Z_META)
			if ci.z_index != orig:
				ci.z_index = orig


func _is_ambient(n: Node) -> bool:
	var a: Node = n
	while a != null and a != _page:
		if a.is_in_group(AMBIENT_GROUP):
			return true
		a = a.get_parent()
	return false


func _under_canvas_layer(n: Node) -> bool:
	var a: Node = n.get_parent()
	while a != null and a != _page:
		if a is Viewport:
			return false
		if a is CanvasLayer:
			return true
		a = a.get_parent()
	return false


func _under_excluded(n: Node) -> bool:
	var a: Node = n.get_parent()
	while a != null and a != _page:
		if a is CanvasLayer or a is Viewport:
			return true
		a = a.get_parent()
	return false


static func _abs_z(ci: CanvasItem) -> int:
	var z: int = 0
	var x: Node = ci
	while x is CanvasItem:
		z += (x as CanvasItem).z_index
		if not (x as CanvasItem).z_as_relative:
			break
		x = x.get_parent()
	return z


## 创建只绘制静态层的 SubViewport，再把纹理挂到合适的动态层宿主中。
func _ensure_viewport() -> void:
	var root: Window = _page.get_tree().root
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.name = "StaticLayerCacheVP"
		_vp.world_2d = root.world_2d
		_vp.transparent_bg = false
		_vp.canvas_cull_mask = STATIC_BIT
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

		root.add_child(_vp)
	if _rect == null or not is_instance_valid(_rect):
		_rect = TextureRect.new()
		_rect.name = "StaticLayerCacheRect"
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.stretch_mode = TextureRect.STRETCH_SCALE

		_rect.top_level = false
		_rect.z_as_relative = true
		_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_rect.visibility_layer = 1
		var dyn: Node = null
		for id: int in _dynamic_ids.keys():
			var d: Node = instance_from_id(id) as Node
			if d != null and StringName(d.name) in DYNAMIC_NODE_NAMES:
				dyn = d
				break

		var host: Node = _rect_host()
		_rect.set_meta(&"_slc_rect", true)
		host.add_child(_rect)
		host.move_child(_rect, 0)
		_rect.visibility_layer = 1
		_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rect.texture = _vp.get_texture()

		_rect.modulate.a = 0.0

	_vp.size = root.size
	_vp.canvas_transform = root.get_final_transform()
	_sync_rect_z()
	_sync_rect_xform()


func _sync_rect_xform() -> void:
	if _rect == null or not is_instance_valid(_rect):
		return
	var host: CanvasItem = _rect.get_parent() as CanvasItem

	var root: Window = _rect.get_tree().root
	var to_screen: Transform2D = (
		root.get_final_transform()
		* (host.get_global_transform_with_canvas() if host != null else Transform2D())
	)
	var inv: Transform2D = to_screen.affine_inverse()
	var sc: Vector2 = inv.get_scale()
	var pos: Vector2 = inv * Vector2.ZERO
	var sz: Vector2 = Vector2(_vp.size)

	if not _rect.position.is_equal_approx(pos):
		_rect.position = pos
	if not _rect.scale.is_equal_approx(sc):
		_rect.scale = sc
	if not _rect.size.is_equal_approx(sz):
		_rect.size = sz


func _sync_rect_z() -> void:
	if _rect == null or not is_instance_valid(_rect):
		return
	var host: CanvasItem = _rect.get_parent() as CanvasItem
	var host_abs: int = _abs_z(host) if host != null else 0
	var z: int = _current_dyn_z() - host_abs - 1

	if _rect.z_index != z:
		_rect.z_index = z


func _current_dyn_z() -> int:
	var z: int = 1 << 30
	for id: int in _dynamic_ids.keys():
		var d: Node = instance_from_id(id) as Node
		if d != null and is_instance_valid(d) and StringName(d.name) in DYNAMIC_NODE_NAMES:
			z = mini(z, _abs_z(d as CanvasItem))
	return z if z < (1 << 30) else _abs_z(_page) + _dyn_z_rel_page


## 释放缓存纹理节点和视口，清除当前页面已经标记的状态。
func _teardown() -> void:
	_set_active(false)
	if _rect != null and is_instance_valid(_rect):
		_rect.queue_free()
	if _vp != null and is_instance_valid(_vp):
		_vp.queue_free()
	_rect = null
	_vp = null
	_tagged = false
