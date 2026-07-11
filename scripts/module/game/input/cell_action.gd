class_name CellAction
extends RefCounted

enum Kind {
	SET_STATE,
	DOUBLE_TAP,
	SET_DRAFT,
}

var kind: int = Kind.SET_STATE
var row: int = -1
var col: int = -1
var state: int = CellState.EMPTY
var before: int = CellState.EMPTY
var play_anim: bool = true
var show_cat_visual: bool = true
var record: bool = true
var vibrate: int = -1
var source: int = BoardView.ChangeSource.USER_ACTION


static func set_cell(
	r: int,
	c: int,
	before_state: int,
	target: int,
	vib: int = -1,
	do_record: bool = true,
	src: int = BoardView.ChangeSource.USER_ACTION
) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.SET_STATE
	a.row = r
	a.col = c
	a.before = before_state
	a.state = target
	a.vibrate = vib
	a.record = do_record
	a.source = src
	return a


static func double_tap(r: int, c: int) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.DOUBLE_TAP
	a.row = r
	a.col = c
	return a


static func set_draft(r: int, c: int, mark: int) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.SET_DRAFT
	a.row = r
	a.col = c
	a.state = mark
	return a
