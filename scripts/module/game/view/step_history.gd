class_name StepHistory
extends RefCounted


class StepRecord:

    var cells: Array[Dictionary] = []

    var is_cat_placement: bool = false

    var is_wrong_guess: bool = false

var _history: Array[StepRecord] = []

func push_step(step: StepRecord) -> void :
    if step.cells.is_empty():
        return
    _history.append(step)

func pop_last() -> StepRecord:
    if _history.is_empty():
        return null
    return _history.pop_back()

func peek_last() -> StepRecord:
    if _history.is_empty():
        return null
    return _history.back()

func peek_at(index: int) -> StepRecord:
    if index < 0 or index >= _history.size():
        return null
    return _history[index]

func has_step() -> bool:
    return not _history.is_empty()

func clear() -> void :
    _history.clear()

func size() -> int:
    return _history.size()

func serialize() -> Array:
    var result: Array = []
    for step: StepRecord in _history:
        var cells_arr: Array = []
        for entry: Dictionary in step.cells:
            cells_arr.append([entry["pos"].x, entry["pos"].y, entry["before"], entry["after"]])
        result.append({"cells": cells_arr, "cat": step.is_cat_placement, "wrong": step.is_wrong_guess})
    return result

func deserialize(data: Array) -> void :
    _history.clear()
    for item in data:
        var step: = StepRecord.new()
        step.is_cat_placement = item.get("cat", false)
        step.is_wrong_guess = item.get("wrong", false)
        for cell_arr in item.get("cells", []):
            step.cells.append({"pos": Vector2i(int(cell_arr[0]), int(cell_arr[1])), "before": int(cell_arr[2]), "after": int(cell_arr[3])})
        if not step.cells.is_empty():
            _history.append(step)
