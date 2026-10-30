## 调试命令描述：保存命令名、显示名称、默认参数和所属页签。
class_name CheatCommand
extends RefCounted

enum Tab {
	COMMAND,
	GAMEPLAY,
	ACTIVITY,
}

var name: String = ""

var label: String = ""

var default_args: String = ""

var tab: int = Tab.COMMAND
