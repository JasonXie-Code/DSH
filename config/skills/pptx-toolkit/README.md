# pptx-toolkit

对**已有** `.pptx` / `.potx` 做读取、体检、编辑与渲染预览的 DSH 技能。

从零设计新稿不归它管：HTML 已有成品走 [`html-to-pptx`](../html-to-pptx/)，按模板出稿走
DSH 内置的 `dsh-ppt`（PPTD 路线）。

## 能力

| 脚本 | 做什么 |
| --- | --- |
| `scripts/dump_text.py` | 按页导出文字（`<!-- Slide number: N -->` 分页标记），可选备注 |
| `scripts/inspect_deck.py` | 结构清单：版式、形状、位置尺寸、文字摘要、备注、媒体 |
| `scripts/check_deck.py` | 三层体检：包完整性、`.rels` 悬空引用、逐页语义；`--deep` 追加 schema 级校验 |
| `scripts/edit_deck.py` | 替换文字 / 增删页 / 复制页 / 重排页 / 写备注 |
| `scripts/render.py` | 渲染成 PNG 做视觉核对（COM / LibreOffice 两条路线） |

## 安装

```powershell
py -m pip install -r requirements.txt
```

必需依赖只有 `python-pptx`（MIT）。可选：`pywin32`（Windows COM 渲染）、
`openxml-audit`（`--deep` 深度校验）、`pypdfium2`（纯 Python 的 PDF 光栅化）。

## 快速开始

```powershell
py scripts\check_deck.py deck.pptx                  # 先确认文件本身没问题
py scripts\inspect_deck.py deck.pptx                # 看结构
py scripts\dump_text.py deck.pptx -o before.txt     # 留一份改动前的内容快照
py scripts\edit_deck.py deck.pptx replace-text "2025" "2026" --in-place
py scripts\render.py deck.pptx -o preview\          # 眼见为实
```

## 测试

```powershell
py tests\smoke_test.py
```

造一份含标题页、项目符号页、表格页、图片页与备注的样例稿，依次跑通四个脚本，
并单独断言**复制页后图片的关系 ID 仍然可解析**——这是最容易出错的地方。

## 许可

MIT（Copyright (c) 2026 Jason Xie）。独立实现，只使用 Python 标准库与宽松许可的
第三方库，不含任何来自 Anthropic 授权受限技能的代码、OOXML 架构文件或提示词。
详见 [`LICENSE`](./LICENSE)。
