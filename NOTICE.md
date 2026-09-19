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

## 二、因其上游许可而**未**收录的内容（重要）

### Anthropic 的 `pptx` 技能 —— 未收录

`skills/pptx`（含 `scripts/office/schemas/` 下的 ECMA-376 / ISO-IEC 29500 架构文件）
来自 Anthropic 的 Agent Skill 分发。其随附 `LICENSE.txt` 写明：

> © 2025 Anthropic, PBC. All rights reserved.
>
> ADDITIONAL RESTRICTIONS: Notwithstanding anything in the Agreement to the
> contrary, users may not:
>
> - Extract these materials from the Services or retain copies of these
>   materials outside the Services
> - Reproduce or copy these materials …
> - Create derivative works based on these materials
> - Distribute, sublicense, or transfer these materials to any third party

即禁止在 Anthropic 服务之外保留副本、复制、派生，以及分发给第三方。**GitHub 属于
第三方**，所以这些文件不随本仓库发布：它们已列入 `.gitignore`，并且不存在于本仓库的
**任何提交历史**中（收录它们的初始提交已被重写剔除）。

替代能力由 `config/skills/pptx-toolkit/`（独立实现，MIT）承担，详见 README。

---

## 三、运行依赖（不随本仓库分发，按需安装）

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

## 四、给再分发者的提醒：一批"看起来 MIT"的 pptx 技能其实是授权陷阱

挑选同类技能时请注意，下列仓库**仓库根的 LICENSE 写着 MIT，但内容里包含 Anthropic
"All rights reserved" 的材料**——MIT 标签无法重新授权别人的内容，照搬会把你一起拖进去：

| 仓库 | 问题 |
| --- | --- |
| `appautomaton/document-skills` | 根 LICENSE 声称 MIT，实为 Anthropic pptx/docx/xlsx/pdf 技能的逐字重新打包 |
| `LUNARTECH-X/superpowers` → `skills/academy-skills/pptx/` | 文件夹内 `LICENSE.txt` 仍写 `© 2025 Anthropic, PBC. All rights reserved.`，frontmatter 自述 `license: Proprietary` |
| `tristan-mcinnis/pptx-from-layouts-skill` → `alternatives/anthropics-pptx/` | 该子目录是 Anthropic 原文；仓库其余部分（`.claude/skills/`）才是 MIT 自有代码 |
| `Binaryify/open-kimi-ppt-skill` | 无许可文件，仓库因版权原因已清空 |

`anthropics/skills` 本身没有根 LICENSE：`skills/pptx`、`skills/docx` 是专有许可，
只有 `skills/theme-factory`、`skills/skill-creator` 是 Apache-2.0。

**本仓库的取舍**：与其引入一个来源可疑的"MIT"技能，不如自己写一个干净实现——
`pptx-toolkit` 只依赖 Python 标准库与宽松许可的库，来源完全可审计。

---

## 五、仅被引用、未被收录的内容

- **ECMA-376 / ISO/IEC 29500（Office Open XML）** 架构文件：Ecma 允许在**附带 Ecma
  版权声明且不作修改**的前提下再分发，但 ISO/IEC 29500 另受 ISO 版权约束。本仓库
  **不收录**任何 XSD，改为通过 `openxml-audit` 做等价校验，避免踩这条线。
- **DSH Desktop**：<https://github.com/dataelement/dsh-desktop>。本仓库是配置快照，
  不是其分发副本。

---

## 六、本仓库自有内容

除上述第三方内容外，`restore.ps1`、`README.md`、`NOTICE.md`、`LICENSE`、
`manifest.json`、`config/settings.yaml`、`config/skills/pptx-toolkit/`、
`config/skills/tun-fakeip-fetch/`、
`profile/web/` 下的配置与本地插件（`dsh-global-prompt`、`tools/apply-nav-icons.ps1`）
等均为本项目自有内容，按 MIT 授权。
