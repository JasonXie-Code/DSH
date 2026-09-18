---
name: pptx-toolkit
description: 需要读取、检查、修改或预览**已有的** .pptx/.potx 时触发——"把这份 ppt 的文字导出来"、"这页写了什么"、"文件打不开了/是不是坏了"、"帮我加一页/删掉第 3 页/把第 5 页挪到第 2 页"、"批量替换 PPT 里的公司名"、"加个演讲备注"、"把每页导成图片看看排版"。基于 python-pptx 做外科式改动，不重排版式、不动没被要求改的内容。**从零设计新稿不要用它**：HTML 已有成品走 html-to-pptx，按模板出稿走 DSH 内置 dsh-ppt（PPTD）。
---

# pptx-toolkit

对**已有** PowerPoint 文件做读取、体检、编辑与渲染预览。定位是"稳、可控、说得清"：
只改你点名的东西，其余部件原样保留。

## 何时用 / 何时不用

| 场景 | 用什么 |
| --- | --- |
| 已有 .pptx，要读文字、查结构 | **本技能** `dump_text.py` / `inspect_deck.py` |
| 已有 .pptx，怀疑损坏或不合规 | **本技能** `check_deck.py` |
| 已有 .pptx，要增删页 / 复制页 / 重排 / 替换文字 / 写备注 | **本技能** `edit_deck.py` |
| 要看排版效果，或核对是否溢出 | **本技能** `render.py` |
| 手里是 HTML 幻灯片，要变成 pptx | `html-to-pptx` 技能 |
| 从零按模板出稿、要 16 套设计模板 | DSH 内置 `dsh-ppt`（PPTD 路线，`pptd_*` 工具） |

本技能**不做**视觉设计：它不会替你重排版式、配色或字体。要"重新设计一版"，请先用
`html-to-pptx` 或 `dsh-ppt` 出稿，再用本技能做核对与微调。

## 安装

```powershell
py -m pip install -r requirements.txt
```

只依赖 `python-pptx`（MIT）。渲染是可选能力，缺什么 `render.py` 会直说，不会静默失败。

## 四个脚本

### 1. `scripts/dump_text.py` — 提取文字

```powershell
py scripts\dump_text.py deck.pptx                    # 输出到终端
py scripts\dump_text.py deck.pptx --notes             # 连备注
py scripts\dump_text.py deck.pptx -o deck.txt         # 写到文件
```

输出带 `<!-- Slide number: N -->` 分页标记，方便跨页检索：

```powershell
Select-String -Path deck.txt -Pattern 'lorem|TODO|\[insert|xxxx'
```

### 2. `scripts/inspect_deck.py` — 看结构

```powershell
py scripts\inspect_deck.py deck.pptx                  # 人读的清单
py scripts\inspect_deck.py deck.pptx --json           # 交给程序
py scripts\inspect_deck.py deck.pptx --slide 3        # 只看第 3 页
```

给出每页的版式、形状类型/名称/位置尺寸、文字摘要、备注，以及媒体资源清单。

### 3. `scripts/check_deck.py` — 体检

```powershell
py scripts\check_deck.py deck.pptx
```

三层检查：ZIP 与必需 OOXML 部件、`.rels` 是否有悬空引用（"打不开"的头号原因）、
python-pptx 能否逐页解析，并提示文字过密（可能溢出）、空文本框、疑似残留占位符。
退出码 0 = 通过，1 = 有问题 —— 可直接用于流水线。

加 `--deep` 会再做一遍 schema / 语义级校验（需要 `openxml-audit`，MIT，纯 Python）；
没装它会打印一句提示并跳过，不影响基础结论。

### 4. `scripts/edit_deck.py` — 改文件

```powershell
# 替换文字（默认字面量，--regex 走正则；--notes 连备注一起改）
py scripts\edit_deck.py deck.pptx replace-text "旧公司名" "新公司名" -o new.pptx

# 增删页、复制页、重排页
py scripts\edit_deck.py deck.pptx add-slide --layout 6 --at 3 -o new.pptx
py scripts\edit_deck.py deck.pptx duplicate-slide 2 --at 5 -o new.pptx
py scripts\edit_deck.py deck.pptx delete-slide 4 --in-place
py scripts\edit_deck.py deck.pptx move-slide 5 --to 2 --in-place

# 写演讲者备注
py scripts\edit_deck.py deck.pptx set-notes 1 --text "开场：先讲结论" -o new.pptx
```

输出二选一：`-o 新文件` 或 `--in-place`（覆盖前自动备份成 `*.bak-<时间戳>`）。
两个都不给会直接报错，避免误覆盖。

**复制页是完整复制**：`duplicate-slide` 会把形状 XML 深拷贝，并把图片、超链接等
关系 ID 重新映射到新页（python-pptx 没有这个 API，这是本技能的实现要点），
否则副本里的图片会变成红叉。

### 5. `scripts/render.py` — 导出预览图（可选）

```powershell
py scripts\render.py deck.pptx -o preview\ --width 1600
```

按可用性自动选路线：`com`（PowerPoint / WPS，最接近用户实际看到的效果）→
`soffice`（LibreOffice 转 PDF 再光栅化）。都没有时会明确列出三个补救选项。

**DSH 里还有一条零安装路线**：用内置 PPTD 工具把 pptx 转成工程再截图 ——
`pptd_import(pptx_path=..., output_directory=...)`，然后
`node "<DSH app>\node_modules\dsh-ppt\lib\bin.js" screenshot <dir> -o <预览目录> --json`，
产出 `<预览目录>\pages\page-N.png`。

## 典型工作流

**改一版别人给的稿子**

```powershell
py scripts\check_deck.py deck.pptx                   # 先确认文件本身没问题
py scripts\inspect_deck.py deck.pptx                 # 搞清有哪些页、每页结构
py scripts\dump_text.py deck.pptx -o before.txt      # 留下改动前的内容快照
py scripts\edit_deck.py deck.pptx replace-text "2025" "2026" --in-place
py scripts\dump_text.py deck.pptx -o after.txt
Compare-Object (Get-Content before.txt) (Get-Content after.txt)   # 确认只改了该改的
py scripts\render.py deck.pptx -o preview\           # 眼见为实
```

**排查"这份 ppt 打不开"**

先 `check_deck.py`：多数情况是 `.rels` 指向了不存在的部件（比如从别处复制形状时
把图片引用带了过来）。报告会直接点名是哪个文件引用了哪个不存在的目标。

## 环境注意事项

- **中文 Windows 的 GBK 控制台**：脚本启动时会把 stdout/stderr 切成 UTF-8，
  不会因为打印 `→`、emoji 或生僻字而崩。
- **编码**：读写的文本一律 UTF-8；给 `-o` 的输出建议也按 UTF-8 处理。
- **python 命令**：本机 `python` 可能指向 Microsoft Store 的占位程序。用 `py`
  启动器更可靠（`py scripts\dump_text.py ...`），或用完整路径。
- **不要用 pip 装 `pptx`**：那个包与本技能无关，正确名字是 `python-pptx`。

## 已知边界

- **不支持批注（review comments）**：`ppt/comments/*.xml` 未处理。需要读写批注时
  要另外实现，别指望本技能。
- **不做视觉设计**：不会替你改配色、字体或版式。需要重新设计请先出稿再回来核对。
- **`.potx` 可读可改**（与 `.pptx` 同为 OPC 包），但**不会**把它当模板批量套用——
  那是 `dsh-ppt` / `html-to-pptx` 的活。
- **`render.py` 依赖外部渲染器**：本机没有 PowerPoint/WPS 也没有 LibreOffice 时，
  它会明确报出三条补救路线，而不是产出一张空白图。

## 许可

MIT（Copyright (c) 2026 Jason Xie）。本技能为独立实现，只使用 Python 标准库与
python-pptx（MIT），**不含**任何来自 Anthropic 授权受限技能的代码、OOXML 架构文件
或提示词。详见同目录 `LICENSE`。
