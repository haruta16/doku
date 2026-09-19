# 全局自增 ID 发号器：给奖励流水这类一次性业务条目派一个进程内唯一的整数编号
extends RefCounted
class_name GlobalUniqueId

# 唯一计数源：static 属于类本身、所有调用方共用；只活在内存里，重启后归零
static var _counter: int = 0


# 取下一个编号：先自增再返回，所以首个 ID 是 1，单次运行内绝不重复
static func next() -> int:
	_counter += 1
	return _counter
