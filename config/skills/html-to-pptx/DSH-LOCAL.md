# 本机环境适配（DSH Desktop / Windows）

本文件由安装者（DSH 会话）写入，记录 `html-to-pptx` 技能在这台机器上运行所需的**环境事实**
与已验证的跑通记录。上游 `SKILL.md` 保持原样，只在其顶部加了 3 行指向本文件的提示。

环境：Windows + PowerShell 7，Python 3.13，Node 24，WPS Office（注册 PowerPoint COM），
DSH Desktop。安装日期：2026-09-18。来源：<https://github.com/Hasasasa/html-to-editable-pptx>（MIT）。

## 已安装依赖（无需再装）

| 依赖 | 状态 |
|---|---|
| `python-pptx` 1.0.2 / `lxml` 6.1.3 / `Pillow` 12.3.0 / `pywin32` 312 | 安装前已存在 |
| `fonttools` 4.65.0 / `playwright` 1.63.0 / `defusedxml` 0.7.1 | 本次安装 |
| Playwright Chromium（`chromium_headless_shell` + `winldd`） | 本次安装到 `%LOCALAPPDATA%\ms-playwright` |
| `pdf2image` | **未装**（本机没有 Poppler/pdftoppm，装了也用不上） |

## 1. 视觉 audit 走 PowerPoint COM，已实测可用

Stage 5b 需要渲染器。本机没有 LibreOffice，但 **WPS Office 注册了 `PowerPoint.Application` COM**，
`scripts/self_check.py` 的 `_try_powerpoint_com` 路径实测成功：

```
[self-check] 渲染器 PowerPoint  ·  2 页（无像素 diff 比较 — 视觉判断交 Stage 5b audit）
[audit]    2 页对比物料 → <out>_audit
```

所以 `SKILL.md` 里「两个渲染器都没装 → 必须问用户」的分支在本机**不会触发**，不用打断用户。

## 2. Python 脚本建议开 UTF-8 模式

本机区域设置是 GBK。`convert.py` 实测不设也能跑通；但为稳妥（其它脚本可能用默认编码读文件）：

```powershell
$env:PYTHONUTF8 = "1"
```

## 3. 首次运行会下载字体（一次性，约 40 MB）

HTML 含 CJK 时自动 seed `Noto Sans SC` + `Noto Serif SC`，实测首次约 **75 秒**
（含下载 variable 源 + instance 出 w400/w700）。缓存位置 `%LOCALAPPDATA%\html-to-pptx\fonts\`，
之后同名字体秒命中。`Microsoft YaHei`、`Arial` 这类 GF 没有的家族会回退到 alias 并打印提示。

## 4. 跑通记录（可作为回归基线）

```
python "<skill_dir>\convert.py" sample-deck.html
→ sample-deck.audited.html（工作副本，源 HTML 未动）
→ sample-deck.pptx（119,214 B，2 页，字体 subset 后嵌入：Noto Sans/Serif SC 各 2 个字重）
→ sample-deck_audit\（audit_contact_01_02.png、slide_NN_compare.png、audit_prompt.md）
```

`lessons-learned.md` 已按上游机制首次 seed（`references/lessons-learned.md.example` → `.md`），
后续每轮沉淀的修复经验都写进它，不会被 `git pull` 覆盖。

## 5. 首次转真实稿前仍要问用户的两项配置

`.config.local.toml` 尚未创建，两项偏好仍是缺省 `ask`，按 `SKILL.md` 的「配置确认」章节问一次后写入：

- `[fonts] auto_install` —— HTML 用了 Google Fonts 家族时才需要（本机上 `--install-user-fonts` 会写
  `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` + HKCU，让 WPS 也能正确渲染）
- `[audit] mode` —— `triage`（省 token，默认）/ `page`（最严）/ `manual`（用户自己看）

## 6. 本机实测的保真度边界（提醒，不是 bug）

快速样例（`<section class="slide">` + 纯 CSS 边框表格）转出来：文字、列表、字号层级可编辑且正确，
但**表格边框/底色没有变成 PPT 原生表格**，正文整体字号偏小。
这正是上游「audit → 按 finding 改 `audited.html` → `--only-slides` 增量重跑」循环要处理的情况；
HTML 里用 CSS 画的表格/复杂边框，在 audit 后通常要改写成显式尺寸的块结构再重转。

## 7. 与 DSH 内置 PPTD 路线的关系

- **HTML 已有成品 deck → 要 pptx**：用本技能（保矢量文字 + 装饰截图兜底）。
- **从零按模板出稿**：用 DSH 内置 PPTD 路线（`pptd_*` 工具 + 16 套模板 + `pptd_render`），
  产出同样是可在 PowerPoint / WPS 中编辑的原生元素。
