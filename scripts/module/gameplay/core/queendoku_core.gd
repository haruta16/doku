class_name QueendokuCore
extends RefCounted






enum Rule{NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3}




static func find_conflicts(board: Array, size: int, regions: Array) -> Dictionary:
    var errors: Dictionary = {}

    var pieces: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                pieces.append(Vector2i(r, c))

    for i in range(pieces.size()):
        for j in range(i + 1, pieces.size()):
            var a: Vector2i = pieces[i]
            var b: Vector2i = pieces[j]
            var conflict: = false

            if a.x == b.x:
                conflict = true
            elif a.y == b.y:
                conflict = true
            elif abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
                conflict = true
            elif regions[a.x][a.y] == regions[b.x][b.y]:
                conflict = true

            if conflict:
                errors["%d,%d" % [a.x, a.y]] = true
                errors["%d,%d" % [b.x, b.y]] = true

    return errors



static func _classify_pair(a: Vector2i, b: Vector2i, regions: Array) -> int:
    if regions[a.x][a.y] == regions[b.x][b.y]:
        return Rule.SAME_COLOR
    if a.x == b.x or a.y == b.y:
        return Rule.SAME_LINE
    if abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
        return Rule.NO_TOUCH
    return Rule.NONE





static func classify_violation(r: int, c: int, placed_cats: Array, regions: Array) -> int:
    var here: = Vector2i(r, c)
    var best: int = Rule.NONE
    for cat: Vector2i in placed_cats:
        var k: int = _classify_pair(here, cat, regions)

        if k != Rule.NONE and (best == Rule.NONE or k < best):
            best = k

            if best == Rule.SAME_COLOR:
                return best
    return best






static func find_conflicting_cats(r: int, c: int, placed_cats: Array, regions: Array) -> Array[Vector2i]:
    var here: = Vector2i(r, c)
    var result: Array[Vector2i] = []
    for cat: Vector2i in placed_cats:
        if _classify_pair(here, cat, regions) != Rule.NONE:
            result.append(cat)
    return result






static func cells_excluded_by_cat(cat: Vector2i, size: int, regions: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if _classify_pair(Vector2i(r, c), cat, regions) != Rule.NONE:
                out.append(Vector2i(r, c))
    return out






static func constraint_cells_for_cat(cat: Vector2i, size: int, regions: Array) -> Array:
    var row_cells: Array[Vector2i] = []
    var col_cells: Array[Vector2i] = []
    var nbr_cells: Array[Vector2i] = []
    var reg_cells: Array[Vector2i] = []
    var cat_region: int = int(regions[cat.x][cat.y])
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            var p: = Vector2i(r, c)
            if r == cat.x:
                row_cells.append(p)
            if c == cat.y:
                col_cells.append(p)
            if abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1:
                nbr_cells.append(p)
            if int(regions[r][c]) == cat_region:
                reg_cells.append(p)
    return [row_cells, col_cells, nbr_cells, reg_cells]





static func cells_excluded_by_cat_no_region(cat: Vector2i, size: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if r == cat.x or c == cat.y or (abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1):
                out.append(Vector2i(r, c))
    return out


static func is_complete(board: Array, size: int, regions: Array) -> bool:
    var piece_count: = 0
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                piece_count += 1
    if piece_count != size:
        return false
    return find_conflicts(board, size, regions).is_empty()








static func validate_solution_entry(entry: Dictionary, size: int) -> bool:
    var regions: Array = entry.get("regionMap", [])
    var solution: Array = entry.get("solution", [])
    if regions.size() != size or solution.size() != size:
        return false

    var board: Array = []
    for r: int in range(size):
        var row: Array = []
        row.resize(size)
        row.fill(CellState.EMPTY)
        board.append(row)
    for r: int in range(size):
        var c: int = int(solution[r])
        if c < 0 or c >= size:
            return false
        board[r][c] = CellState.CAT
    return is_complete(board, size, regions)
