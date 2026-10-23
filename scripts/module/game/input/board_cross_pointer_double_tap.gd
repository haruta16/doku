## 跨指针双击识别：从触点槽位中消费可配对的点击，避免不同指针重复落子。
class_name BoardCrossPointerDoubleTap
extends RefCounted


static func try_consume(
	slots: Array, requester: BoardGestureRecognizer, r: int, c: int
) -> BoardTouchSlot:
	for candidate: BoardTouchSlot in slots:
		if _is_excluded(candidate, requester):
			continue
		if candidate.recognizer.try_consume_pending_tap(r, c):
			return candidate
	return null


static func has_any(slots: Array, requester: BoardGestureRecognizer, r: int, c: int) -> bool:
	for candidate: BoardTouchSlot in slots:
		if _is_excluded(candidate, requester):
			continue
		if candidate.recognizer.has_pending_tap(r, c):
			return true
	return false


static func _is_excluded(candidate: BoardTouchSlot, requester: BoardGestureRecognizer) -> bool:
	if candidate.recognizer == null or candidate.recognizer == requester:
		return true
	var still_pressing: bool = candidate.physically_down or candidate.is_owned()
	return still_pressing and candidate.recognizer.is_window_from_latest_drag_start()
