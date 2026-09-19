# 第三方组件与许可说明（NOTICE）

本仓库整体采用根目录的 **MIT License**（Copyright (c) 2026 Jason Xie）。
该许可**不覆盖**下列第三方内容，它们各自按其原有许可提供。

---

## 一、随本仓库发布的第三方内容

### `config/skills/html-to-pptx/` — MIT

| 项 | 内容 |
| --- | --- |
| 上游 | <https://github.com/Hasasasa/html-to-editable-pptx> |
| 许可 | MIT License，Copyright (c) 2026 Phil |
| 许可全文 | `config/skills/html-to-pptx/LICENSE` |

本仓库按原样收录该技能，另加了本机环境适配说明 `DSH-LOCAL.md`（自有内容）。
再分发时保留上游 `LICENSE` 与版权声明即可。

---

## 二、运行依赖（不随本仓库分发，按需安装）

| 组件 | 许可 | 说明 |
| --- | --- | --- |
| `python-pptx` | MIT，Copyright (c) 2013 Steve Canny | `pptx-toolkit` 的核心依赖 |
| `lxml` | BSD 3-Clause，Copyright (c) 2004 Infrae | `python-pptx` 的依赖 |
| `openxml-audit` | MIT，Copyright (c) 2026 Bram Alkema | `pptx-toolkit check_deck.py --deep` 的可选依赖；Microsoft Open XML SDK 校验逻辑的纯 Python 实现（上游 `dotnet/Open-XML-SDK` 为 MIT / .NET Foundation） |
| `pywin32` | PSF | `render.py` 走 Windows COM 渲染时的可选依赖 |
| `pypdfium2` | Apache-2.0 / BSD-3 | `render.py` 光栅化 PDF 的可选依赖 |
| `dsh-ppt` / `dsh-ppt-composer` | MIT，Copyright (c) 2026 DeepSeek and WorkBuddy PPT contributors | 随 DSH Desktop 安装（`resources\app\node_modules\dsh-ppt`），本仓库不复制其任何文件；其模板来源与第三方署名见该包内 `THIRD_PARTY_NOTICES.md` |
| `dshmarket`、`dsh-cost-meter` | 各自许可 | 由 `restore.ps1 -InstallPlugins` 在目标机器上从 npm 现装；本仓库只记录版本号与 lockfile |
| `@deepseek-ai/*` harness 包 | 各自许可 | 随 DSH Desktop 分发，本仓库不复制 |

---

## 三、仅被引用、未被收录的内容

- **ECMA-376 / ISO/IEC 29500（Office Open XML）** 架构文件：本仓库**不收录**任何 XSD，
  改为通过 `openxml-audit`（MIT）做等价的 schema 级校验，避免再分发条款带来的复杂度。
- **DSH Desktop**：<https://github.com/dataelement/dsh-desktop>。本仓库是配置快照，
  不是其分发副本。

---

## 四、本仓库自有内容

除上述第三方内容外，`restore.ps1`、`README.md`、`NOTICE.md`、`LICENSE`、
`manifest.json`、`docs/`、`config/settings.yaml`、`config/skills/pptx-toolkit/`、
`config/skills/tun-fakeip-fetch/`、`profile/web/` 下的配置与本地插件
（`dsh-global-prompt`、`tools/apply-nav-icons.ps1`）等均为本项目自有内容，按 MIT 授权。
