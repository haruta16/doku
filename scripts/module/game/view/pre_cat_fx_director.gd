## 预放猫特效导演：选择表现变体、管理猫的暂时隐藏，并在完成或超时后收尾。
class_name PreCatFxDirector
extends RefCounted

signal fx_finished

const _OVERLAY_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/fx/pre_cat_fx_overlay.tscn"
)

const _VARIANTS: Dictionary = {
	PreCatFxConfig.VALUE_WAVE:
	{
		"scene": "res://scripts/module/game/ui/fx/pre_cat_fx1_cat_wave.tscn",
		"hides_cat": true,
	},
	PreCatFxConfig.VALUE_SPOTLIGHT:
	{
		"scene": "res://scripts/module/game/ui/fx/pre_cat_fx2_spotlight.tscn",
		"hides_cat": true,
	},
	PreCatFxConfig.VALUE_CAT_APPEAR:
	{
		"scene": "res://scripts/module/game/ui/fx/pre_cat_fx3_cat_appear.tscn",
		"hides_cat": true,
	},
	PreCatFxConfig.VALUE_ROW_SWEEP:
	{
		"scene": "res://scripts/module/game/ui/fx/pre_cat_fx4_row_sweep.tscn",
		"hides_cat": true,
	},
}

const _TIMEOUT_SLACK: float = 3.0

const _TIMEOUT_FLOOR_SEC: float = 0.5

var _host: Node = null
var _board: BoardView = null
var _overlay: CanvasLayer = null
var _variant: PreCatFxVariant = null

var _entry: Dictionary = {}
var _level: int = 0
var _kind: int = LevelKind.MAIN
var _cat_cell: Vector2i = Vector2i(-1, -1)
var _playing: bool = false
var _cat_revealed: bool = false

var _run_gen: int = 0


func _init(host: Node, board: BoardView) -> void:
	_host = host
	_board = board


func prepare(
	level: int, cat_cell: Vector2i, is_endgame_restore: bool, kind: int = LevelKind.MAIN
) -> void:
	_entry = {}
	_level = level
	_kind = kind
	_cat_cell = cat_cell
	_cat_revealed = false
	if level <= 0 or cat_cell.x < 0:
		return

	if is_endgame_restore:
		return

	if GameState.is_pre_cat_fx_played(level, kind):
		return
	var cfg: AbConfigBase = ABTestManager.pre_cat_fx
	if cfg.is_debug_disabled():
		return
	var group: int = int(ABTestManager.pre_cat_fx.value())
	if not _VARIANTS.has(group):
		return
	_entry = _VARIANTS[group]


func wants_cat_hidden() -> bool:
	return not _entry.is_empty() and bool(_entry.get("hides_cat", false))


func cat_cell() -> Vector2i:
	return _cat_cell


func is_playing() -> bool:
	return _playing


func is_pending() -> bool:
	return not _entry.is_empty()


func run() -> void:
	if _entry.is_empty() or _playing:
		return
	if (
		_host == null
		or not is_instance_valid(_host)
		or _board == null
		or not is_instance_valid(_board)
	):
		return
	var scene: PackedScene = load(str(_entry.get("scene", "")))
	if scene == null:
		push_error("[pre_cat_fx] variant scene load failed: %s" % str(_entry.get("scene", "")))
		_reveal_cat()
		return
	var inst: Node = scene.instantiate()
	if not (inst is PreCatFxVariant):
		push_error(
			"[pre_cat_fx] variant root is not PreCatFxVariant: %s" % str(_entry.get("scene", ""))
		)
		inst.queue_free()
		_reveal_cat()
		return

	GameState.mark_pre_cat_fx_played(_level, _kind)
	var gen: int = _run_gen
	_playing = true
	_variant = inst as PreCatFxVariant
	_ensure_overlay()
	_overlay.add_child(_variant)
	_variant.setup(_build_context())

	await _await_play_with_timeout()

	if gen != _run_gen:
		return

	_reveal_cat()
	if _variant != null and is_instance_valid(_variant):
		_variant.queue_free()
	_variant = null
	_playing = false
	_entry = {}
	fx_finished.emit()


func cancel() -> void:
	_run_gen += 1
	if _variant != null and is_instance_valid(_variant):
		_variant.queue_free()
	_variant = null
	_playing = false
	_entry = {}


func _await_play_with_timeout() -> void:
	var state: Dictionary = {"done": false, "expired": false}
	var runner: Callable = func() -> void:
		await _variant.play()
		state.done = true
	runner.call()
	var nominal: float = _variant.nominal_duration_sec()
	var timeout_sec: float = maxf(_TIMEOUT_FLOOR_SEC, nominal * _TIMEOUT_SLACK)
	var timer: SceneTreeTimer = _host.get_tree().create_timer(timeout_sec)
	timer.timeout.connect(func() -> void: state.expired = true)
	while not state.done and not state.expired:
		if _variant == null or not is_instance_valid(_variant):
			return
		await _host.get_tree().process_frame
	if state.expired and not state.done:
		push_warning(
			"[pre_cat_fx] variant play() timed out after %.2fs, force finishing" % timeout_sec
		)


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _OVERLAY_SCENE.instantiate() as CanvasLayer
	_host.add_child(_overlay)


func _build_context() -> PreCatFxContext:
	var ctx: PreCatFxContext = PreCatFxContext.for_board(_board, _cat_cell)
	ctx.group = int(ABTestManager.pre_cat_fx.value())
	ctx.reveal_cat = _reveal_cat
	return ctx


func _reveal_cat(
	with_particles: bool = false, with_halo: bool = false, appear_anim: String = "CatIconAppear"
) -> void:
	if _cat_revealed:
		return
	_cat_revealed = true
	if _board == null or not is_instance_valid(_board) or _cat_cell.x < 0:
		return
	_board.reveal_hidden_cat(_cat_cell.x, _cat_cell.y, appear_anim, with_particles, with_halo)


func _transform_rect(rect: Rect2, xform: Transform2D) -> Rect2:
	var p0: Vector2 = xform * rect.position
	var p1: Vector2 = xform * Vector2(rect.end.x, rect.position.y)
	var p2: Vector2 = xform * rect.end
	var p3: Vector2 = xform * Vector2(rect.position.x, rect.end.y)
	var min_pos := Vector2(
		minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	)
	var max_pos := Vector2(
		maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	)
	return Rect2(min_pos, max_pos - min_pos)
