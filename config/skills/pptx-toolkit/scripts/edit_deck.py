#!/usr/bin/env python3
"""编辑已有 .pptx：改文字、增删页、复制页、重排页、写备注。

设计原则：**不改动没有被要求改的东西**。python-pptx 会原样保留它不理解的 XML，
所以本脚本只做外科式改动，其余部件保持字节级不变。

用法（子命令）：
    python edit_deck.py deck.pptx replace-text "旧文字" "新文字" -o new.pptx
    python edit_deck.py deck.pptx replace-text "第\\d+页" "PAGE" --regex --in-place
    python edit_deck.py deck.pptx add-slide --layout 6 --at 3 -o new.pptx
    python edit_deck.py deck.pptx duplicate-slide 2 --at 5 -o new.pptx
    python edit_deck.py deck.pptx delete-slide 4 --in-place
    python edit_deck.py deck.pptx move-slide 5 --to 2 --in-place
    python edit_deck.py deck.pptx set-notes 1 --text "讲稿……" -o new.pptx

输出：-o 写新文件；--in-place 覆盖原文件（先自动备份成 *.bak-<时间戳>）。
两者必须给一个，避免误覆盖。
"""

from __future__ import annotations

import argparse
import copy
import datetime
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pptx_common import (
    EXIT_USAGE,
    ensure_utf8_stdout,
    iter_shapes,
    load_presentation,
    notes_text,
)

# Office Open XML 的关系命名空间：r:embed / r:link / r:id 都挂在这里
REL_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


# ── 文字替换 ────────────────────────────────────────────────────────────────

def _replace_in_paragraph(para, pattern: re.Pattern, replacement: str) -> int:
    """先按 run 替换；跨 run 的情况回退到整段重写（保留首个 run 的格式）。"""
    count = 0

    for run in para.runs:
        new_text, n = pattern.subn(replacement, run.text)
        if n:
            run.text = new_text
            count += n

    if count:
        return count

    # 跨 run：把整段文字拼起来判断，命中才重写，避免破坏格式
    full = "".join(run.text for run in para.runs)
    if not full:
        return 0
    new_full, n = pattern.subn(replacement, full)
    if not n:
        return 0

    para.runs[0].text = new_full
    for run in para.runs[1:]:
        run.text = ""
    return n


def _replace_in_shape(shape, pattern: re.Pattern, replacement: str) -> int:
    count = 0
    if getattr(shape, "has_text_frame", False):
        for para in shape.text_frame.paragraphs:
            count += _replace_in_paragraph(para, pattern, replacement)
    if getattr(shape, "has_table", False):
        for row in shape.table.rows:
            for cell in row.cells:
                for para in cell.text_frame.paragraphs:
                    count += _replace_in_paragraph(para, pattern, replacement)
    return count


def cmd_replace_text(prs, args) -> int:
    if args.regex:
        try:
            pattern = re.compile(args.old)
        except re.error as exc:
            print(f"[edit] 正则无效：{exc}", file=sys.stderr)
            return EXIT_USAGE
    else:
        pattern = re.compile(re.escape(args.old))

    total = 0
    for index, slide in enumerate(prs.slides, start=1):
        for shape in iter_shapes(slide.shapes):
            total += _replace_in_shape(shape, pattern, args.new)
        if args.notes:
            try:
                if slide.has_notes_slide:
                    for para in slide.notes_slide.notes_text_frame.paragraphs:
                        total += _replace_in_paragraph(para, pattern, args.new)
            except (AttributeError, ValueError):
                pass
    print(f"替换了 {total} 处。")
    return 0


# ── 页面结构操作 ────────────────────────────────────────────────────────────

def _slide_id_list(prs):
    return prs.slides._sldIdLst  # python-pptx 没有公开 API，这是社区通行做法


def _relocate(prs, element, target_index: int) -> None:
    """把某个 sldId 元素挪到指定位置（0 基）。"""
    sld_id_lst = _slide_id_list(prs)
    sld_id_lst.remove(element)
    sld_id_lst.insert(target_index, element)


def cmd_add_slide(prs, args) -> int:
    layouts = list(prs.slide_layouts)
    if not 0 <= args.layout < len(layouts):
        print(
            f"[edit] 版式下标 {args.layout} 不存在；可用 0..{len(layouts) - 1}："
            + ", ".join(f"{i}={layout.name}" for i, layout in enumerate(layouts)),
            file=sys.stderr,
        )
        return EXIT_USAGE

    slide = prs.slides.add_slide(layouts[args.layout])
    if args.at is not None:
        _relocate(prs, _slide_id_list(prs)[-1], max(0, args.at - 1))
    print(f"已新增第 {args.at if args.at else len(prs.slides)} 页（版式 {layouts[args.layout].name}）。")
    return 0


def _clone_slide(prs, source):
    """复制一页，并把图片/超链接等关系 ID 重新映射到新页。"""
    dest = prs.slides.add_slide(source.slide_layout)

    # 去掉新版式自动带进来的占位符，之后整页按源页内容重建
    for shape in list(dest.shapes):
        shape._element.getparent().remove(shape._element)

    id_map = {}
    for r_id, rel in source.part.rels.items():
        if rel.is_external:
            id_map[r_id] = dest.part.rels.get_or_add_ext_rel(rel.reltype, rel.target_ref)
        else:
            id_map[r_id] = dest.part.rels.get_or_add(rel.reltype, rel._target)

    for shape in source.shapes:
        new_element = copy.deepcopy(shape._element)
        _remap_rel_ids(new_element, id_map)
        dest.shapes._spTree.insert_element_before(new_element, "p:extLst")

    note = notes_text(source).strip()
    if note:
        dest.notes_slide.notes_text_frame.text = note

    return dest


def _remap_rel_ids(element, id_map: dict) -> None:
    """把克隆出来的 XML 里所有 r:* 引用换成新页的 rId。"""
    for node in element.iter():
        for attr, value in list(node.attrib.items()):
            if attr.startswith(REL_NS) and value in id_map:
                node.set(attr, id_map[value])


def cmd_duplicate_slide(prs, args) -> int:
    total = len(prs.slides)
    if not 1 <= args.index <= total:
        print(f"[edit] 页码 {args.index} 越界（共 {total} 页）", file=sys.stderr)
        return EXIT_USAGE

    source = prs.slides[args.index - 1]
    _clone_slide(prs, source)
    if args.at is not None:
        _relocate(prs, _slide_id_list(prs)[-1], max(0, args.at - 1))
    print(f"已复制第 {args.index} 页。")
    return 0


def cmd_delete_slide(prs, args) -> int:
    total = len(prs.slides)
    if not 1 <= args.index <= total:
        print(f"[edit] 页码 {args.index} 越界（共 {total} 页）", file=sys.stderr)
        return EXIT_USAGE

    sld_id_lst = _slide_id_list(prs)
    element = list(sld_id_lst)[args.index - 1]
    r_id = element.get(f"{REL_NS}id")
    if r_id:
        prs.part.drop_rel(r_id)
    sld_id_lst.remove(element)
    print(f"已删除第 {args.index} 页，现在剩 {len(prs.slides)} 页。")
    return 0


def cmd_move_slide(prs, args) -> int:
    total = len(prs.slides)
    if not 1 <= args.index <= total:
        print(f"[edit] 页码 {args.index} 越界（共 {total} 页）", file=sys.stderr)
        return EXIT_USAGE
    if not 1 <= args.to <= total:
        print(f"[edit] 目标位置 {args.to} 越界（共 {total} 页）", file=sys.stderr)
        return EXIT_USAGE

    element = list(_slide_id_list(prs))[args.index - 1]
    _relocate(prs, element, args.to - 1)
    print(f"已把第 {args.index} 页移到第 {args.to} 页。")
    return 0


def cmd_set_notes(prs, args) -> int:
    total = len(prs.slides)
    if not 1 <= args.index <= total:
        print(f"[edit] 页码 {args.index} 越界（共 {total} 页）", file=sys.stderr)
        return EXIT_USAGE

    slide = prs.slides[args.index - 1]
    text = args.text
    if args.from_file:
        text = Path(args.from_file).read_text(encoding="utf-8")
    if text is None:
        print("[edit] 需要 --text 或 --from-file", file=sys.stderr)
        return EXIT_USAGE

    slide.notes_slide.notes_text_frame.text = text
    print(f"已写入第 {args.index} 页备注（{len(text)} 字符）。")
    return 0


# ── 入口 ────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    # 输出选项同时挂在主解析器和每个子命令上（default=SUPPRESS 保证互不覆盖），
    # 这样 `-o` 写在子命令之前或之后都能识别。
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "-o", "--output", default=argparse.SUPPRESS, help="输出到新文件"
    )
    common.add_argument(
        "--in-place",
        action="store_true",
        default=argparse.SUPPRESS,
        help="覆盖原文件（先备份）",
    )

    parser = argparse.ArgumentParser(
        description="编辑已有 pptx（改文字 / 增删页 / 复制页 / 重排页 / 写备注）",
        parents=[common],
    )
    parser.add_argument("pptx", help="源 .pptx 文件")

    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("replace-text", parents=[common], help="全文替换文字")
    p.add_argument("old", help="要查找的文字（或正则）")
    p.add_argument("new", help="替换成什么")
    p.add_argument("--regex", action="store_true", help="把 old 当正则表达式")
    p.add_argument("--notes", action="store_true", help="连演讲者备注一起替换")

    p = sub.add_parser("add-slide", parents=[common], help="新增一页")
    p.add_argument("--layout", type=int, default=6, help="版式下标（默认 6，通常是空白版式）")
    p.add_argument("--at", type=int, help="插到第几页（默认追加到末尾）")

    p = sub.add_parser("duplicate-slide", parents=[common], help="复制一页")
    p.add_argument("index", type=int, help="要复制的页码（从 1 开始）")
    p.add_argument("--at", type=int, help="副本放到第几页（默认末尾）")

    p = sub.add_parser("delete-slide", parents=[common], help="删除一页")
    p.add_argument("index", type=int, help="要删除的页码（从 1 开始）")

    p = sub.add_parser("move-slide", parents=[common], help="重排一页")
    p.add_argument("index", type=int, help="要移动的页码（从 1 开始）")
    p.add_argument("--to", type=int, required=True, help="移到第几页")

    p = sub.add_parser("set-notes", parents=[common], help="写入演讲者备注")
    p.add_argument("index", type=int, help="页码（从 1 开始）")
    p.add_argument("--text", help="备注正文")
    p.add_argument("--from-file", help="从 UTF-8 文本文件读备注")

    return parser


HANDLERS = {
    "replace-text": cmd_replace_text,
    "add-slide": cmd_add_slide,
    "duplicate-slide": cmd_duplicate_slide,
    "delete-slide": cmd_delete_slide,
    "move-slide": cmd_move_slide,
    "set-notes": cmd_set_notes,
}


def main(argv: list[str] | None = None) -> int:
    ensure_utf8_stdout()
    args = build_parser().parse_args(argv)

    output = getattr(args, "output", None)
    in_place = getattr(args, "in_place", False)

    if not output and not in_place:
        print("[edit] 需要 -o <输出文件> 或 --in-place 之一。", file=sys.stderr)
        return EXIT_USAGE
    if output and in_place:
        print("[edit] -o 与 --in-place 不能同时给。", file=sys.stderr)
        return EXIT_USAGE

    source = Path(args.pptx)
    prs = load_presentation(str(source))

    code = HANDLERS[args.command](prs, args)
    if code != 0:
        return code

    if in_place:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = source.with_suffix(source.suffix + f".bak-{stamp}")
        shutil.copy2(source, backup)
        prs.save(str(source))
        print(f"已写回 {source.name}（备份：{backup.name}）")
    else:
        prs.save(output)
        print(f"已保存 {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
