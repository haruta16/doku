## 仅供隔离测试：模拟搭盘中途失败，不修改真实棋盘的构建逻辑。
extends BoardView


func setup(_size: int, _regions: Array, _colors: Array[int], _patterns: Array = [], _recycle: bool = false) -> bool:
	return false
