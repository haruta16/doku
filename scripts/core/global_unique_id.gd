extends RefCounted
class_name GlobalUniqueId

static var _counter: int = 0


static func next() -> int:
	_counter += 1
	return _counter
