#!/usr/bin/env python3
"""把幻灯片渲染成 PNG，用于视觉核对（排版、溢出、图表是否正常）。

三条路线，按可用性自动选择，也可以 --via 强制指定：

  com      PowerPoint / WPS 的 COM 接口（最接近用户实际打开的效果；仅 Windows）
  soffice  LibreOffice 转 PDF，再光栅化成 PNG（跨平台，需装 LibreOffice）
  (DSH)    DSH 内置的 PPTD 渲染路线不在这里——它是 agent 工具调用，见 SKILL.md

本脚本不内置任何渲染器；找不到可用路线时会明确说明缺什么，而不是静默失败。

用法：
    python render.py deck.pptx -o preview/
    python render.py deck.pptx -o preview/ --via soffice --width 1600
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pptx_common import EXIT_FAIL, ensure_utf8_stdout, load_presentation


def slide_size_inches(path: Path) -> tuple[float, float]:
    prs = load_presentation(str(path))
    return int(prs.slide_width) / 914400, int(prs.slide_height) / 914400


# ── 路线 1：COM（PowerPoint / WPS）───────────────────────────────────────────

def has_com() -> bool:
    if sys.platform != "win32":
        return False
    try:
        import win32com.client  # noqa: F401
    except ImportError:
        return False
    return True


def render_via_com(path: Path, out_dir: Path, width: int) -> list[Path]:
    import win32com.client

    width_in, height_in = slide_size_inches(path)
    height = int(width * height_in / width_in) if width_in else width

    app = None
    deck = None
    produced: list[Path] = []
    try:
        app = win32com.client.Dispatch("PowerPoint.Application")
        # 有些版本（含 WPS）不接受 WithWindow=False，失败就退回默认
        try:
            deck = app.Presentations.Open(str(path.resolve()), WithWindow=False)
        except Exception:
            deck = app.Presentations.Open(str(path.resolve()))

        for index in range(1, deck.Slides.Count + 1):
            target = out_dir / f"slide-{index:02d}.png"
            deck.Slides(index).Export(str(target.resolve()), "PNG", width, height)
            produced.append(target)
    finally:
        if deck is not None:
            try:
                deck.Close()
            except Exception:
                pass
        if app is not None:
            try:
                app.Quit()
            except Exception:
                pass
    return produced


# ── 路线 2：LibreOffice → PDF → PNG ─────────────────────────────────────────

def find_soffice() -> str | None:
    for name in ("soffice", "soffice.exe", "libreoffice"):
        found = shutil.which(name)
        if found:
            return found
    for candidate in (
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/usr/bin/soffice",
    ):
        if Path(candidate).exists():
            return candidate
    return None


def rasterize_pdf(pdf: Path, out_dir: Path, width: int) -> list[Path]:
    """把 PDF 每页转成 PNG。优先 pdftoppm，其次 pypdfium2。"""
    pdftoppm = shutil.which("pdftoppm")
    if pdftoppm:
        prefix = out_dir / "slide"
        subprocess.run(
            [pdftoppm, "-png", "-r", "150", str(pdf), str(prefix)],
            check=True,
            capture_output=True,
        )
        return sorted(out_dir.glob("slide-*.png")) + sorted(out_dir.glob("slide*.png"))

    try:
        import pypdfium2 as pdfium
    except ImportError:
        raise RuntimeError(
            "PDF 已生成，但缺少光栅化工具：装 pdftoppm（poppler）或 pip install pypdfium2。"
        )

    produced = []
    doc = pdfium.PdfDocument(str(pdf))
    for index in range(len(doc)):
        page = doc[index]
        scale = width / page.get_width()
        image = page.render(scale=scale).to_pil()
        target = out_dir / f"slide-{index + 1:02d}.png"
        image.save(target)
        produced.append(target)
    return produced


def render_via_soffice(path: Path, out_dir: Path, width: int, soffice: str) -> list[Path]:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [soffice, "--headless", "--convert-to", "pdf", "--outdir", tmp, str(path.resolve())],
            check=True,
            capture_output=True,
            timeout=300,
        )
        pdfs = list(Path(tmp).glob("*.pdf"))
        if not pdfs:
            raise RuntimeError("LibreOffice 没有产出 PDF（文件可能损坏或格式不被支持）。")
        return rasterize_pdf(pdfs[0], out_dir, width)


def main(argv: list[str] | None = None) -> int:
    ensure_utf8_stdout()
    parser = argparse.ArgumentParser(description="把 pptx 渲染成 PNG 以便视觉核对")
    parser.add_argument("pptx", help="要渲染的 .pptx 文件")
    parser.add_argument("-o", "--out", required=True, help="输出目录（不存在会自动创建）")
    parser.add_argument("--via", choices=("com", "soffice"), help="强制指定渲染路线")
    parser.add_argument("--width", type=int, default=1600, help="输出宽度像素（默认 1600）")
    args = parser.parse_args(argv)

    path = Path(args.pptx)
    if not path.exists():
        print(f"[render] 文件不存在：{path}", file=sys.stderr)
        return EXIT_FAIL

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    soffice = find_soffice()
    route = args.via
    if route is None:
        if has_com():
            route = "com"
        elif soffice:
            route = "soffice"
        else:
            print(
                "[render] 没有可用的渲染路线。三选一：\n"
                "  1) 安装 pywin32 并确保本机有 PowerPoint 或 WPS（最接近实际打开效果）\n"
                "  2) 安装 LibreOffice（跨平台）\n"
                "  3) 走 DSH 内置 PPTD 渲染路线（见 SKILL.md，无需额外安装）",
                file=sys.stderr,
            )
            return EXIT_FAIL

    print(f"[render] 路线：{route}")
    try:
        if route == "com":
            if not has_com():
                print(
                    "[render] COM 不可用：需要 Windows + pywin32，且本机装有 PowerPoint 或 WPS。",
                    file=sys.stderr,
                )
                return EXIT_FAIL
            produced = render_via_com(path, out_dir, args.width)
        else:
            if not soffice:
                print("[render] 找不到 LibreOffice（soffice）。", file=sys.stderr)
                return EXIT_FAIL
            produced = render_via_soffice(path, out_dir, args.width, soffice)
    except Exception as exc:
        print(f"[render] 渲染失败：{type(exc).__name__}: {exc}", file=sys.stderr)
        return EXIT_FAIL

    print(f"[render] 已输出 {len(produced)} 张 PNG 到 {out_dir}")
    for item in produced[:5]:
        print(f"  - {item.name}")
    if len(produced) > 5:
        print(f"  … 另有 {len(produced) - 5} 张")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
