#!/usr/bin/env python3
"""把 .pptx 的文字按页导出成纯文本，便于检索与内容 QA。

输出沿用 `<!-- Slide number: N -->` 分页标记，方便直接用 findstr / Select-String
一类工具跨页搜索占位符（TODO、lorem、[insert 等）。

用法：
    python dump_text.py deck.pptx
    python dump_text.py deck.pptx --notes          # 连演讲者备注一起导出
    python dump_text.py deck.pptx --table-sep ","  # 表格列分隔符
    python dump_text.py deck.pptx -o deck.txt      # 写到文件（默认输出到 stdout）
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pptx_common import ensure_utf8_stdout, iter_shapes, load_presentation, notes_text, shape_text


def dump(path: str, with_notes: bool, table_sep: str) -> str:
    prs = load_presentation(path)
    chunks: list[str] = []

    for index, slide in enumerate(prs.slides, start=1):
        chunks.append(f"<!-- Slide number: {index} -->")
        for shape in iter_shapes(slide.shapes):
            text = shape_text(shape)
            if not text.strip():
                continue
            if getattr(shape, "has_table", False) and table_sep != "\t":
                text = text.replace("\t", table_sep)
            chunks.append(text)
        if with_notes:
            note = notes_text(slide).strip()
            if note:
                chunks.append(f"<!-- Notes: {index} -->")
                chunks.append(note)
        chunks.append("")

    return "\n".join(chunks).rstrip() + "\n"


def main(argv: list[str] | None = None) -> int:
    ensure_utf8_stdout()
    parser = argparse.ArgumentParser(
        description="把 pptx 的文字按页导出成纯文本",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("pptx", help="要读取的 .pptx 文件")
    parser.add_argument("--notes", action="store_true", help="同时导出演讲者备注")
    parser.add_argument(
        "--table-sep",
        default="\t",
        help="表格单元格的分隔符（默认制表符）",
    )
    parser.add_argument("-o", "--output", help="输出文件；缺省写到 stdout")
    args = parser.parse_args(argv)

    text = dump(args.pptx, args.notes, args.table_sep)

    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"已写入 {args.output}（{len(text.splitlines())} 行）", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
