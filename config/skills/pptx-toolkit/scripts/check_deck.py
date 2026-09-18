#!/usr/bin/env python3
"""检查 .pptx 的结构与合规性，给出可执行的修复建议。

做三层检查：
  1. 包层：ZIP 是否完整、必需的 OOXML 部件与 [Content_Types].xml 是否齐全。
  2. 引用层：每个 .rels 指向的目标是否真的存在（悬空引用是"文件打不开"的头号原因）。
  3. 语义层：python-pptx 能否解析每一页、文本框是否有溢出风险、是否残留占位符。

用法：
    python check_deck.py deck.pptx
    python check_deck.py deck.pptx --json
退出码：0 = 全部通过；1 = 有问题；2 = 用法错误。
"""

from __future__ import annotations

import argparse
import json
import posixpath
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pptx_common import (
    EXIT_FAIL,
    EXIT_OK,
    emit_json,
    ensure_utf8_stdout,
    iter_shapes,
    load_presentation,
    notes_text,
    shape_text,
)

REQUIRED_PARTS = ("[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml")

# 明显的占位符残留（内容 QA 用）
PLACEHOLDER_HINTS = ("lorem", "ipsum", "todo", "tbd", "xxxx", "[insert", "click to add")

# 一页里文本量超过这个阈值就提示人工核对是否溢出
DENSE_TEXT_CHARS = 1200


def check_package(path: Path) -> tuple[list[str], list[str]]:
    """返回 (errors, warnings)：ZIP 完整性与必需部件。"""
    errors: list[str] = []
    warnings: list[str] = []

    if not zipfile.is_zipfile(path):
        return [f"不是合法的 ZIP/OOXML 包：{path.name}"], warnings

    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())

        broken = zf.testzip()
        if broken is not None:
            errors.append(f"ZIP 内容损坏，首个坏条目：{broken}")

        for part in REQUIRED_PARTS:
            if part not in names:
                errors.append(f"缺少必需部件：{part}")

        # 逐条 .rels 检查引用目标是否存在
        for name in sorted(n for n in names if n.endswith(".rels")):
            base = posixpath.dirname(posixpath.dirname(name))
            try:
                payload = zf.read(name).decode("utf-8", errors="replace")
            except KeyError:
                continue
            if "Relationships" not in payload and "Relationship" not in payload:
                continue
            for target in _relationship_targets(payload):
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                resolved = posixpath.normpath(posixpath.join(base, target.lstrip("/")))
                if resolved not in names:
                    errors.append(f"{name} 指向不存在的目标：{target}")

    return errors, warnings


def _relationship_targets(xml_text: str) -> list[str]:
    """从 Relationships XML 里抠出 Target 属性（不引入额外 XML 依赖）。"""
    import re

    targets = []
    for match in re.finditer(r'Target\s*=\s*"([^"]+)"', xml_text):
        target = match.group(1)
        if target and not target.startswith("{"):
            targets.append(target)
    return targets


def check_semantics(path: Path) -> tuple[dict, list[str], list[str]]:
    """返回 (summary, errors, warnings)：python-pptx 能否解析、内容层面的提示。"""
    errors: list[str] = []
    warnings: list[str] = []

    prs = load_presentation(str(path))
    slides_summary = []

    for index, slide in enumerate(prs.slides, start=1):
        shapes = list(iter_shapes(slide.shapes))
        text_chars = 0
        empty_frames = 0

        for shape in shapes:
            text = shape_text(shape)
            text_chars += len(text)
            if getattr(shape, "has_text_frame", False) and not text.strip():
                empty_frames += 1
            for hint in PLACEHOLDER_HINTS:
                if hint in text.lower():
                    warnings.append(f"第 {index} 页疑似残留占位符文本：{hint!r}")
                    break

        try:
            layout_name = slide.slide_layout.name
        except (AttributeError, ValueError):
            layout_name = "?"

        if text_chars > DENSE_TEXT_CHARS:
            warnings.append(
                f"第 {index} 页文字较多（{text_chars} 字符），建议渲染后核对是否溢出"
            )
        if empty_frames:
            warnings.append(f"第 {index} 页有 {empty_frames} 个空文本框（可能是没删干净的占位符）")
        if not text_chars and not notes_text(slide).strip():
            warnings.append(f"第 {index} 页没有正文文字（纯图片页？）")

        slides_summary.append(
            {
                "index": index,
                "layout": layout_name,
                "shapes": len(shapes),
                "textChars": text_chars,
                "hasNotes": bool(notes_text(slide).strip()),
            }
        )

    summary = {
        "file": path.name,
        "slideCount": len(slides_summary),
        "slideWidthIn": round(int(prs.slide_width) / 914400, 2),
        "slideHeightIn": round(int(prs.slide_height) / 914400, 2),
        "slides": slides_summary,
    }
    return summary, errors, warnings


def check_deep(path: Path) -> tuple[list[str], list[str], str | None]:
    """用 openxml-audit 做 schema / 语义级深度校验（可选依赖）。

    返回 (errors, warnings, note)。未安装时返回提示语而不是报错——
    基础检查不依赖任何第三方校验库。
    """
    try:
        import openxml_audit as oa
    except ImportError:
        return (
            [],
            [],
            "未安装 openxml-audit，已跳过 schema 级深度校验；"
            "需要时执行 py -m pip install openxml-audit（MIT）。",
        )

    try:
        result = oa.OpenXmlValidator().validate(str(path))
    except Exception as exc:  # 校验器自身出错不应影响基础结论
        return [], [], f"openxml-audit 执行失败：{type(exc).__name__}: {exc}"

    errors: list[str] = []
    warnings: list[str] = []
    for item in getattr(result, "errors", []) or []:
        severity = str(getattr(item, "severity", "ERROR")).upper()
        kind = str(getattr(item, "error_type", "?")).split(".")[-1]
        where = getattr(item, "part_uri", "") or getattr(item, "path", "") or ""
        description = getattr(item, "description", "") or str(item)
        line = f"[{kind}] {description}" + (f"（位置：{where}）" if where else "")
        if "ERROR" in severity:
            errors.append(line)
        else:
            warnings.append(line)

    note = (
        f"openxml-audit 深度校验：{'通过' if not errors else '发现问题'}"
        f"（错误 {len(errors)}，提示 {len(warnings)}）"
    )
    return errors, warnings, note


def main(argv: list[str] | None = None) -> int:
    ensure_utf8_stdout()
    parser = argparse.ArgumentParser(description="检查 pptx 的结构与合规性")
    parser.add_argument("pptx", help="要检查的 .pptx 文件")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出结果")
    parser.add_argument(
        "--deep",
        action="store_true",
        help="额外做 schema / 语义级深度校验（需要 pip install openxml-audit）",
    )
    args = parser.parse_args(argv)

    path = Path(args.pptx)
    if not path.exists():
        print(f"[check] 文件不存在：{path}", file=sys.stderr)
        return EXIT_FAIL

    errors: list[str] = []
    warnings: list[str] = []

    pkg_errors, pkg_warnings = check_package(path)
    errors += pkg_errors
    warnings += pkg_warnings

    summary: dict = {}
    if not pkg_errors:
        try:
            summary, sem_errors, sem_warnings = check_semantics(path)
            errors += sem_errors
            warnings += sem_warnings
        except SystemExit:
            errors.append("python-pptx 无法解析该文件（见上面的错误信息）")

    deep_note = None
    if args.deep:
        deep_errors, deep_warnings, deep_note = check_deep(path)
        errors += deep_errors
        warnings += deep_warnings

    ok = not errors

    if args.json:
        emit_json(
            {
                "file": path.name,
                "passed": ok,
                "errors": errors,
                "warnings": warnings,
                "deepNote": deep_note,
                "summary": summary,
            }
        )
    else:
        print(f"检查：{path.name}")
        if summary:
            print(
                f"  页数：{summary.get('slideCount')}  "
                f"尺寸：{summary.get('slideWidthIn')}\" x {summary.get('slideHeightIn')}\""
            )
        if deep_note:
            print(f"  {deep_note}")
        if errors:
            print(f"\n错误（{len(errors)}）：")
            for item in errors:
                print(f"  ✗ {item}")
        if warnings:
            print(f"\n提示（{len(warnings)}）：")
            for item in warnings:
                print(f"  ! {item}")
        print()
        print("结论：" + ("全部通过。" if ok else "存在错误，需要修复。"))

    return EXIT_OK if ok else EXIT_FAIL


if __name__ == "__main__":
    raise SystemExit(main())
