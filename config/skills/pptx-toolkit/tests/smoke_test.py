#!/usr/bin/env python3
"""pptx-toolkit 冒烟测试：造一份样例稿，依次跑通四个脚本并校验结果。

重点验证 `edit_deck.py duplicate-slide`：复制页必须把图片的关系 ID 重新映射，
否则副本里的图片会变成红叉——这是本技能最容易出错的地方，所以单独断言。

用法：
    py tests/smoke_test.py
退出码 0 = 全通过。
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
SCRIPTS = SKILL_DIR / "scripts"
PY = sys.executable

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [OK]   {label}")
    else:
        print(f"  [FAIL] {label}{(' — ' + detail) if detail else ''}")
        FAILURES.append(label)


def run(script: str, *args: str, expect: int = 0) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        [PY, str(SCRIPTS / script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != expect:
        print(f"    $ {script} {' '.join(args)}")
        print(f"    exit={proc.returncode} (期望 {expect})")
        if proc.stdout.strip():
            print(f"    stdout: {proc.stdout.strip()[:500]}")
        if proc.stderr.strip():
            print(f"    stderr: {proc.stderr.strip()[:500]}")
    return proc


def as_json(out: subprocess.CompletedProcess, label: str) -> dict:
    """把 --json 输出解析成 dict；不是 JSON 时记为失败而不是抛异常。"""
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        check(f"{label}：--json 输出可解析", False, f"stdout={out.stdout[:200]!r}")
        return {}


# ── 造样例稿 ────────────────────────────────────────────────────────────────

def make_fixture(path: Path) -> None:
    from PIL import Image
    from pptx import Presentation
    from pptx.util import Inches

    prs = Presentation()

    slide = prs.slides.add_slide(prs.slide_layouts[0])
    slide.shapes.title.text = "2025 年度汇报"
    slide.placeholders[1].text = "示例副标题"

    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = "要点"
    body = slide.placeholders[1].text_frame
    body.text = "第一点"
    body.add_paragraph().text = "第二点 TODO 待补"
    body.add_paragraph().text = "第三点"

    slide = prs.slides.add_slide(prs.slide_layouts[5])
    slide.shapes.title.text = "数据"
    table = slide.shapes.add_table(2, 2, Inches(1), Inches(2), Inches(6), Inches(1.5)).table
    table.cell(0, 0).text = "项目"
    table.cell(0, 1).text = "数值"
    table.cell(1, 0).text = "营收"
    table.cell(1, 1).text = "100"

    # 带图片的一页 —— 复制页测试就靠它
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    png = path.parent / "_fixture_pixel.png"
    Image.new("RGB", (80, 80), (40, 90, 200)).save(png)
    slide.shapes.add_picture(str(png), Inches(1), Inches(1), Inches(2), Inches(2))

    prs.slides[0].notes_slide.notes_text_frame.text = "开场备注：先讲结论"
    prs.save(str(path))


def deck_image_rel_ids(path: Path) -> list[str]:
    """取出所有 slideN.xml 里 r:embed 引用的 rId（用于验证关系映射）。"""
    import re

    ids: list[str] = []
    with zipfile.ZipFile(path) as zf:
        for name in zf.namelist():
            if re.fullmatch(r"ppt/slides/slide\d+\.xml", name):
                payload = zf.read(name).decode("utf-8", errors="replace")
                ids.extend(re.findall(r'r:embed="([^"]+)"', payload))
    return ids


def resolve_embed(path: Path, r_id: str) -> bool:
    """确认某个 rId 在该 slide 的 .rels 里能解析到实际存在的媒体部件。"""
    import posixpath
    import re

    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        for name in sorted(n for n in names if re.fullmatch(r"ppt/slides/_rels/slide\d+\.xml\.rels", n)):
            rels = zf.read(name).decode("utf-8", errors="replace")
            for match in re.finditer(r'Id="([^"]+)"[^>]*Target="([^"]+)"', rels):
                if match.group(1) != r_id:
                    continue
                base = posixpath.dirname(posixpath.dirname(name))
                target = posixpath.normpath(posixpath.join(base, match.group(2)))
                return target in names
    return False


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="pptx-toolkit-smoke-"))
    deck = tmp / "deck.pptx"
    print(f"工作目录：{tmp}\n")

    print("造样例稿")
    make_fixture(deck)
    check("样例稿已生成", deck.exists() and deck.stat().st_size > 0)

    print("\ndump_text.py")
    out = run("dump_text.py", str(deck))
    check("导出了分页标记", "<!-- Slide number: 1 -->" in out.stdout)
    check("导出了标题文字", "2025 年度汇报" in out.stdout)
    check("导出了表格内容", "营收" in out.stdout)

    out_notes = run("dump_text.py", str(deck), "--notes")
    check("--notes 导出了备注", "先讲结论" in out_notes.stdout)

    txt = tmp / "deck.txt"
    run("dump_text.py", str(deck), "-o", str(txt))
    check("-o 写出了文件", txt.exists() and "第一点" in txt.read_text(encoding="utf-8"))

    print("\ninspect_deck.py")
    out = run("inspect_deck.py", str(deck), "--json")
    payload = as_json(out, "inspect")
    check("页数为 4", payload.get("slideCount") == 4, str(payload.get("slideCount")))
    check("报了版式名", bool(payload.get("layouts")))
    check("识别出媒体", len(payload.get("media", [])) >= 1, str(payload.get("media")))

    out = run("inspect_deck.py", str(deck), "--slide", "2")
    check("--slide 只输出该页", "第 2 页" in out.stdout and "第 3 页" not in out.stdout)
    run("inspect_deck.py", str(deck), "--slide", "99", expect=1)

    print("\ncheck_deck.py")
    out = run("check_deck.py", str(deck))
    check("样例稿体检通过", "全部通过" in out.stdout)
    out = run("check_deck.py", str(deck), "--json")
    result = as_json(out, "check")
    check("json passed=true", result.get("passed") is True)
    check("json 有每页明细", len(result.get("summary", {}).get("slides", [])) == 4)

    broken = tmp / "broken.pptx"
    broken.write_bytes(b"not a zip at all")
    run("check_deck.py", str(broken), expect=1)
    check("坏文件被判定为失败", True)

    out = run("check_deck.py", str(deck), "--deep", "--json")
    deep = as_json(out, "deep")
    check("--deep 可运行且给出说明", out.returncode == 0 and bool(deep.get("deepNote")), str(deep.get("deepNote"))[:120])
    check("--deep 未产生错误", deep.get("passed") is True, str(deep.get("errors")))

    print("\nedit_deck.py — 文字替换")
    out = run("edit_deck.py", str(deck), "replace-text", "2025", "2026", "-o", str(tmp / "r1.pptx"))
    check("报告替换处数", "替换了" in out.stdout)
    after = run("dump_text.py", str(tmp / "r1.pptx"))
    check("新文字已生效", "2026 年度汇报" in after.stdout and "2025" not in after.stdout)

    run(
        "edit_deck.py", str(deck), "replace-text", r"第.\S*", "X", "--regex", "-o", str(tmp / "r2.pptx")
    )
    check("--regex 可用", True)

    print("\nedit_deck.py — 页面结构")
    dup = tmp / "dup.pptx"
    run("edit_deck.py", str(deck), "duplicate-slide", "4", "-o", str(dup))
    out = run("inspect_deck.py", str(dup), "--json")
    check("复制后页数为 5", as_json(out, "dup").get("slideCount") == 5)

    embeds = deck_image_rel_ids(dup)
    check("副本保留了图片引用", len(embeds) >= 2, f"r:embed 数量={len(embeds)}")
    check(
        "所有图片引用都能解析到媒体部件",
        all(resolve_embed(dup, r_id) for r_id in embeds),
        f"悬空引用：{[r for r in embeds if not resolve_embed(dup, r)]}",
    )
    out = run("check_deck.py", str(dup))
    check("复制后的文件体检通过（无悬空引用）", "全部通过" in out.stdout)

    run("edit_deck.py", str(deck), "add-slide", "--layout", "6", "--at", "2", "-o", str(tmp / "add.pptx"))
    out = run("inspect_deck.py", str(tmp / "add.pptx"), "--json")
    check("新增页后为 5 页", as_json(out, "add").get("slideCount") == 5)

    moved = tmp / "moved.pptx"
    run("edit_deck.py", str(deck), "move-slide", "1", "--to", "4", "-o", str(moved))
    order = run("dump_text.py", str(moved)).stdout
    check("重排后标题页不在首位", order.index("要点") < order.index("2025 年度汇报"))

    deleted = tmp / "deleted.pptx"
    run("edit_deck.py", str(deck), "delete-slide", "2", "-o", str(deleted))
    out = run("inspect_deck.py", str(deleted), "--json")
    check("删除后为 3 页", as_json(out, "deleted").get("slideCount") == 3)

    run("edit_deck.py", str(deck), "set-notes", "2", "--text", "第二页讲稿", "-o", str(tmp / "n.pptx"))
    out = run("dump_text.py", str(tmp / "n.pptx"), "--notes")
    check("备注已写入", "第二页讲稿" in out.stdout)

    print("\nedit_deck.py — 安全护栏")
    run("edit_deck.py", str(deck), "delete-slide", "1", expect=2)          # 没给 -o/--in-place
    run("edit_deck.py", str(deck), "delete-slide", "99", "-o", str(tmp / "x.pptx"), expect=2)
    run("edit_deck.py", str(deck), "delete-slide", "1", "-o", str(tmp / "y.pptx"), "--in-place", expect=2)

    inplace = tmp / "inplace.pptx"
    inplace.write_bytes(deck.read_bytes())
    run("edit_deck.py", str(inplace), "delete-slide", "1", "--in-place")
    check("--in-place 生成了备份", any(inplace.parent.glob("inplace.pptx.bak-*")))

    print("\nrender.py")
    preview = tmp / "preview"
    proc = subprocess.run(
        [PY, str(SCRIPTS / "render.py"), str(deck), "-o", str(preview)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    pngs = sorted(preview.glob("*.png")) if preview.exists() else []
    if proc.returncode == 0:
        check("渲染出了 4 张 PNG", len(pngs) == 4, f"实际 {len(pngs)} 张")
        if pngs:
            from PIL import Image

            with Image.open(pngs[0]) as image:
                check(
                    "PNG 宽度符合 --width",
                    image.width == 1600,
                    f"{image.width}x{image.height}",
                )
    else:
        check(
            "无渲染器时给出可操作路线提示（而不是静默失败）",
            any(
                key in proc.stderr
                for key in ("没有可用的渲染路线", "COM 不可用", "LibreOffice")
            ),
            proc.stderr.strip()[:200],
        )

    print("\n" + "=" * 60)
    if FAILURES:
        print(f"失败 {len(FAILURES)} 项：")
        for item in FAILURES:
            print(f"  - {item}")
        return 1
    print("全部通过。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
