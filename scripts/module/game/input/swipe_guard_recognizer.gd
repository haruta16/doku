class_name SwipeGuardRecognizer
extends BoardGestureRecognizer















var _guard: = SwipeAxisGuard.new()

func on_drag_start(pos: Vector2) -> Array[CellAction]:

    _guard.begin(board.get_puzzle_size(), BoardView.SLOT_PX, BoardView.BOARD_PADDING, BoardView.CELL_PX, 
        board.pointer_to_cell(pos.x, pos.y))
    var actions: Array[CellAction] = super (pos)
    _configure_guard()
    _push_zone()
    return actions

func on_drag_over(pos: Vector2) -> Array[CellAction]:


    var was_pending: bool = _stroke.target_pending
    var actions: Array[CellAction] = super (pos)
    if was_pending and not _stroke.target_pending:
        _guard.set_active(_guard_active_now())
    _push_zone()
    return actions

func on_drag_end() -> void :
    super ()
    _guard.end()
    board.update_swipe_protection_zone({})



func _resolve_cell(pos: Vector2) -> Vector2i:
    return _guard.process(pos.x, pos.y)




func _guard_active_now() -> bool:
    return _swipe_guard_enabled_for_level()\
and not _stroke.target_pending\
and _stroke.target_state != CellState.EMPTY


func _swipe_guard_enabled_for_level() -> bool:
    var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
    return cfg.is_enabled() and board.get_puzzle_size() >= cfg.min_size()


func _configure_guard() -> void :
    var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
    var n: int = board.get_puzzle_size()
    var threshold: int = cfg.threshold_for(n)
    var tol_px: float = cfg.tolerance_pct() * BoardView.CELL_PX
    _guard.configure(_guard_active_now(), threshold, tol_px)


func _push_zone() -> void :
    board.update_swipe_protection_zone(_guard.get_debug_lock())
