#!/usr/bin/env python3
"""用 gdtoolkit 4.5.0 整理恢复源码；启用语法树、注释和幂等性检查。"""

from __future__ import annotations

import argparse
import importlib
import importlib.metadata
import json
import re
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--layout-repairs", type=Path, default=Path(__file__).resolve().parents[1] / "docs/recovery/1.22.0/lambda_layout_repairs.json")
    args = parser.parse_args()

    from gdtoolkit.formatter import check_formatting_safety, format_code

    # 4.5.0 将单行 lambda 内的裸 return 当成带表达式的 return，访问空 children。
    # 仅修补本进程的字符串输出，不改本机安装包或任何 GDScript 语义。
    statement = importlib.import_module("gdtoolkit.formatter.function_statement_to_str")
    expression = importlib.import_module("gdtoolkit.formatter.expression_to_str")
    original = statement.function_statement_to_str

    def statement_to_string(tree):
        if tree.data == "return_stmt" and not tree.children:
            return "return"
        return original(tree)

    statement.function_statement_to_str = statement_to_string
    expression.function_statement_to_str = statement_to_string

    layout_repairs = json.loads(args.layout_repairs.read_text()) if args.layout_repairs.exists() else []
    results = {"formatter": "gdtoolkit " + importlib.metadata.version("gdtoolkit"), "line_length": 100, "indent": "tab", "preserved_lambda_layout": layout_repairs, "formatted": [], "unchanged": [], "failures": []}
    for folder in ("scripts", "addons", "assets"):
        for path in sorted((args.root / folder).rglob("*.gd")):
            relative = path.relative_to(args.root).as_posix()
            code = path.read_text(encoding="utf-8")
            try:
                formatted = format_code(code, 100)
                preserve = [item for item in layout_repairs if item["path"] == relative]
                for item in preserve:
                    pattern = r"^func " + re.escape(item["function"]) + r"\(.*?(?=^(?:##[^\n]*\n)*(?:static )?func |\Z)"
                    original_function = re.search(pattern, code, re.M | re.S)
                    if original_function is None:
                        raise ValueError("Missing preserved function: " + item["function"])
                    block = original_function[0]
                    # These five known functions have no multiline string literals.
                    if '\"\"\"' in block or "'''" in block:
                        raise ValueError("Review multiline string before indentation conversion")
                    block = re.sub(r"^( +)", lambda match: "\t" * (len(match[1]) // 4) + " " * (len(match[1]) % 4), block, flags=re.M)
                    formatted, count = re.subn(pattern, lambda _: block, formatted, flags=re.M | re.S)
                    if count != 1:
                        raise ValueError("Cannot preserve function: " + item["function"])
                if preserve:
                    # gdformat's own stability rule would reintroduce the known invalid layout.
                    from gdtoolkit.formatter import check_tree_invariant, check_comment_persistence
                    check_tree_invariant(code, formatted)
                    check_comment_persistence(code, formatted)
                else:
                    check_formatting_safety(code, formatted, 100)
                if code != formatted:
                    path.write_text(formatted, encoding="utf-8")
                    results["formatted"].append(relative)
                else:
                    results["unchanged"].append(relative)
            except Exception as error:
                results["failures"].append({"path": relative, "error": type(error).__name__, "detail": str(error)[:2000]})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: len(results[key]) for key in ("formatted", "unchanged", "failures")}))
    for failure in results["failures"]:
        print(failure["path"] + ": " + failure["error"])
    return bool(results["failures"])


if __name__ == "__main__":
    raise SystemExit(main())
