"""Exercise development-service build branches in disposable Godot projects.

The editor binary cannot become a release template. Only the build predicate is
replaced in copied scripts; these checks do not claim a real release export.
"""
from pathlib import Path
import json
import os
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from run_validation import run

ENGINE = os.environ.get("DOKU_GODOT") or "godot"
SERVICES = {
    "input.gd": "addons/godot_mcp/mcp_input_service.gd",
    "inspector.gd": "addons/godot_mcp/mcp_game_inspector_service.gd",
    "screenshot.gd": "addons/godot_mcp/mcp_screenshot_service.gd",
    "hotkey.gd": "addons/screenshot_tool/screenshot_hotkey.gd",
}

HARNESS = '''extends SceneTree
var checks := 0
var failures := 0
var keys := []

class InputObserver extends Node:
    var keys: Array
    func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.keycode == KEY_A:
            keys.append(event.pressed)

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var enabled := OS.get_cmdline_user_args()[0] == "true"
    var host := Node.new()
    root.add_child(host)
    current_scene = host
    var observer := InputObserver.new()
    observer.keys = keys
    host.add_child(observer)
    var services := []
    for path: String in ["input.gd", "inspector.gd", "screenshot_probe.gd", "hotkey_probe.gd"]:
        var node: Node = load("res://" + path).new()
        host.add_child(node)
        services.append(node)
        _check(node.process_mode == (Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_DISABLED), path + " process mode")
    for index in range(3):
        _check(services[index].is_processing() == enabled, "polling follows build kind")
    _check(services[3].is_processing_input() == enabled, "shortcut input follows build kind")

    _write("mcp_input_commands", JSON.stringify({"type": "key", "keycode": "A", "pressed": true}))
    _write("mcp_game_request", JSON.stringify({"command": "get_scene_tree", "params": {}}))
    _write("mcp_screenshot_request", "1")
    for frame in range(6):
        await process_frame
    for name: String in ["mcp_input_commands", "mcp_game_request", "mcp_screenshot_request"]:
        _check(FileAccess.file_exists("user://" + name) != enabled, name + " consumed only in development")
    _check(FileAccess.file_exists("user://mcp_game_response") == enabled, "inspector response only in development")
    if enabled:
        var response: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://mcp_game_response"))
        _check(response is Dictionary and not response.has("error"), "inspector handles a real harmless request")
    _check(keys.has(true) == enabled, "MCP keyboard command dispatched only in development")
    _check(services[2].captures == (1 if enabled else 0), "screenshot dispatch only in development")

    var shortcut := InputEventKey.new()
    shortcut.keycode = KEY_T
    shortcut.pressed = true
    shortcut.ctrl_pressed = true
    shortcut.shift_pressed = true
    Input.parse_input_event(shortcut)
    await process_frame
    await process_frame
    _check(services[3].captures == (1 if enabled else 0), "screenshot hotkey dispatched only in development")
    host.queue_free()
    await process_frame
    await process_frame
    print("DEVELOPMENT TOOLS TESTS: %d assertions, %d failures; simulated_debug=%s" % [checks, failures, enabled])
    quit(0 if failures == 0 else 1)

func _write(name: String, content: String) -> void:
    var file := FileAccess.open("user://" + name, FileAccess.WRITE)
    file.store_string(content)
    file.close()

func _check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("TEST_FAILED: " + message)
'''


class DevelopmentToolsTests(unittest.TestCase):
    def test_services_use_the_real_build_predicate(self):
        for path in SERVICES.values():
            with self.subTest(path=path):
                text = (ROOT / path).read_text()
                self.assertEqual(text.count("if not OS.is_debug_build():"), 1)

    @unittest.skipUnless(shutil.which(ENGINE), "matching Godot binary unavailable")
    def test_non_debug_services_leave_requests_and_input_untouched(self):
        self._run_build_branch(False)

    @unittest.skipUnless(shutil.which(ENGINE), "matching Godot binary unavailable")
    def test_debug_services_still_handle_requests_and_shortcuts(self):
        self._run_build_branch(True)

    def _run_build_branch(self, enabled: bool):
        with tempfile.TemporaryDirectory(prefix="doku-development-tools-") as directory:
            work = Path(directory)
            data = work / "userdata"
            data.mkdir()
            # No product Autoload, assets or save paths are copied into this project.
            (work / "project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            for target, source in SERVICES.items():
                text = (ROOT / source).read_text()
                text = text.replace("OS.is_debug_build()", "true" if enabled else "false")
                (work / target).write_text(text.replace("user://", data.as_posix() + "/"))
            # Keep the actual polling and input routes; replace only GPU capture
            # effects so a headless check can observe whether they were invoked.
            screenshot = 'extends "res://screenshot.gd"\nvar captures := 0\nfunc _take_screenshot() -> void:\n\tcaptures += 1\n\tDirAccess.remove_absolute(REQUEST_PATH)\n'
            hotkey = 'extends "res://hotkey.gd"\nvar captures := 0\nfunc _capture() -> void:\n\tcaptures += 1\n'
            (work / "screenshot_probe.gd").write_text(screenshot)
            (work / "hotkey_probe.gd").write_text(hotkey)
            (work / "test.gd").write_text(HARNESS.replace("user://", data.as_posix() + "/"))
            result = run(ENGINE, work, work / "run.log", ["--script", "res://test.gd", "--", str(enabled).lower()], 30)
            self.assertTrue(result["ok"], json.dumps(result, ensure_ascii=False, indent=2))
            self.assertIn("DEVELOPMENT TOOLS TESTS:", result["summary"])
            print(result["summary"])


if __name__ == "__main__":
    unittest.main()
