#!/usr/bin/env python3
"""查看 .pptx 的结构清单：页面、版式、形状、尺寸、备注、媒体。

用于回答"这份稿子到底有哪些页、每页放了什么、用的是哪个版式"这类问题，
改稿前先跑一次可以避免瞎猜。

用法：
    python inspect_deck.py deck.pptx
    python inspect_deck.py deck.pptx --json
    python inspect_deck.py deck.pptx --slide 3      # 只看第 3 页
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pptx_common import (
    emit_json,
    emu_to_inches,
    ensure_utf8_stdout,
    iter_shapes,
    load_presentation,
    notes_text,
    shape_text,
)


def collect_media(path: Path) -> list[dict]:
    """列出包里的媒体资源（图片/音视频）。"""
    media = []
    try:
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if "/media/" in info.filename:
                    media.append(
                        {
                            "part": info.filename,
                            "kb": round(info.file_size / 1024, 1),
                        }
                    )
    except zipfile.BadZipFile:
        pass
    return sorted(media, key=lambda m: m["part"])


def describe_slide(slide) -> dict:
    shapes = []
    for shape in iter_shapes(slide.shapes):
        text = shape_text(shape)
        entry = {
            "name": shape.name,
            "type": str(getattr(shape, "shape_type", "?")).split(" (")[0],
            "x": emu_to_inches(getattr(shape, "left", 0)),
            "y": emu_to_inches(getattr(shape, "top", 0)),
            "w": emu_to_inches(getattr(shape, "width", 0)),
            "h": emu_to_inches(getattr(shape, "height", 0)),
        }
        if text.strip():
            entry["text"] = text if len(text) <= 120 else text[:117] + "..."
        if getattr(shape, "has_table", False):
            entry["table"] = f"{len(shape.table.rows)}x{len(shape.table.columns)}"
        shapes.append(entry)

    try:
        layout = slide.slide_layout.name
    except (AttributeError, ValueError):
        layout = "?"

    note = notes_text(slide).strip()
    return {
        "layout": layout,
        "shapeCount": len(shapes),
        "shapes": shapes,
        "notes": note if len(note) <= 200 else note[:197] + "...",
    }


def main(argv: list[str] | None = None) -> int:
    ensure_utf8_stdout()
    parser = argparse.ArgumentParser(description="查看 pptx 的结构清单")
    parser.add_argument("pptx", help="要查看的 .pptx 文件")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出")
    parser.add_argument("--slide", type=int, help="只看指定页码（从 1 开始）")
    args = parser.parse_args(argv)

    path = Path(args.pptx)
    prs = load_presentation(str(path))
    total_slides = len(prs.slides)

    if args.slide and not 1 <= args.slide <= total_slides:
        print(f"[inspect] 没有第 {args.slide} 页（共 {total_slides} 页）", file=sys.stderr)
        return 1

    slides = []
    for index, slide in enumerate(prs.slides, start=1):
        if args.slide and index != args.slide:
            continue
        slides.append({"index": index, **describe_slide(slide)})

    payload = {
        "file": path.name,
        "sizeKb": round(path.stat().st_size / 1024, 1),
        "slideWidthIn": emu_to_inches(prs.slide_width),
        "slideHeightIn": emu_to_inches(prs.slide_height),
        "slideCount": total_slides,
        "layouts": [layout.name for layout in prs.slide_layouts],
        "media": collect_media(path),
        "slides": slides,
    }

    if args.json:
        emit_json(payload)
        return 0

    print(f"文件：{payload['file']}（{payload['sizeKb']} KB）")
    print(f"尺寸：{payload['slideWidthIn']}\" x {payload['slideHeightIn']}\"   页数：{payload['slideCount']}")
    print(f"版式：{', '.join(payload['layouts'])}")
    if payload["media"]:
        total = round(sum(m["kb"] for m in payload["media"]), 1)
        print(f"媒体：{len(payload['media'])} 个，共 {total} KB")

    for slide in payload["slides"]:
        print()
        print(f"第 {slide['index']} 页 · 版式 {slide['layout']} · {slide['shapeCount']} 个形状")
        for shape in slide["shapes"]:
            pos = f"{shape['x']},{shape['y']} {shape['w']}x{shape['h']}in"
            label = shape.get("text") or shape.get("table") or ""
            label = label.replace("\n", " / ")
            print(f"  - [{shape['type']}] {shape['name']}  ({pos})  {label}")
        if slide["notes"]:
            print(f"  ~ 备注：{slide['notes']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
