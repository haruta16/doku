## 真实页面测试用：模拟搭盘明确失败，旧盘即使仍完整也不能当成本次入场成功。
extends "res://products/meowdoku/gameplay/presentation/board/board_view.gd"

var reject_setup: bool = false
var rejected_setups: int = 0


func setup(puzzle_size: int, regions: Array, color_map: Array[int], pattern_regions: Array = [], recycle_reused: bool = false) -> bool:
	if reject_setup:
		rejected_setups += 1
		return false
	return super.setup(puzzle_size, regions, color_map, pattern_regions, recycle_reused)
