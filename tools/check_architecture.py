#!/usr/bin/env python3
"""检查显式 res:// 资源的所有权；全局类与动态依赖另由独立工程验证。"""
from __future__ import annotations

import argparse
import ast
from pathlib import Path, PurePosixPath
import posixpath
import re


ROOT = Path(__file__).resolve().parents[1]
# 仅识别字符串与注释，不尝试实现 GDScript 解析器。字符串内的 # 不会当成注释。
TOKENS = re.compile(
    r"""(?P<comment>\#[^\n]*)|(?P<string>\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"""
)


def resource_dependencies(text: str):
    for match in TOKENS.finditer(text):
        if match.lastgroup != "string":
            continue
        try:
            value = ast.literal_eval(match.group())
        except (SyntaxError, ValueError):
            continue
        if isinstance(value, str) and value.startswith("res://"):
            yield text.count("\n", 0, match.start()) + 1, PurePosixPath(posixpath.normpath(value.removeprefix("res://")))


def violation(source: PurePosixPath, dependency: PurePosixPath) -> str:
    origin, target = source.parts, dependency.parts
    # "res://" 本身用于路径前缀判断，不是一个资源依赖。
    if dependency == PurePosixPath("."):
        return ""
    # 只允许现有交付协议的动态路径模板/目录前缀，不允许固定产品包或导入资源。
    # normpath 在前，不能用 ../ 绕到产品资产。
    runtime_templates = {"content/%s/%s/%s", "content/%s/%s", ".godot/imported"}
    if origin[:3] == ("scripts", "framework", "content") and dependency.as_posix() in runtime_templates:
        return ""
    if origin[:2] == ("scripts", "framework") and target[:2] != origin[:2]:
        return "公共框架不得依赖产品脚本、资源或插件；由宿主注入"
    product_domain = len(origin) >= 4 and origin[0] == "products" and origin[2:4] == ("gameplay", "domain")
    example_domain = len(origin) >= 4 and origin[:2] == ("scripts", "examples") and origin[3] == "domain"
    if product_domain or example_domain:
        if target[:2] != ("scripts", "framework") and target[:4] != origin[:4]:
            return "纯规则只依赖自身规则和公共框架"
    if len(origin) >= 2 and origin[0] == "products":
        if len(target) >= 2 and target[0] == "products" and target[1] != origin[1]:
            return "产品之间不得互相依赖"
        if target[:2] == ("scripts", "examples"):
            return "正式产品不得依赖验证示例"
    if len(origin) >= 3 and origin[:2] == ("scripts", "examples"):
        if target[:1] == ("products",):
            return "独立示例不得依赖具体产品"
        if len(target) >= 3 and target[:2] == origin[:2] and target[2] != origin[2]:
            return "独立示例之间不得互相依赖"
    return ""


def check(source: Path) -> list[str]:
    failures = []
    for area in ("scripts/framework", "products", "scripts/examples"):
        if not (source / area).is_dir():
            failures.append(f"缺少被检查目录: {area}")
            continue
        for path in sorted((source / area).rglob("*")):
            if not path.is_file() or path.suffix not in (".gd", ".tscn", ".tres"):
                continue
            relative = PurePosixPath(path.relative_to(source).as_posix())
            for line, dependency in resource_dependencies(path.read_text(encoding="utf-8")):
                reason = violation(relative, dependency)
                if reason:
                    failures.append(f"{relative}:{line}: {reason}: {dependency}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    options = parser.parse_args()
    failures = check(options.source.resolve())
    for failure in failures:
        print("ARCHITECTURE_FAILED: " + failure)
    if not failures:
        print("ARCHITECTURE_OK: explicit res:// framework/product/example/domain boundaries (including assets and addons)")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
