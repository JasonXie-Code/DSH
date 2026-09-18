# DSH 配置与插件副本

这是 **一份 DSH（DeepSeek Harness / DSH Desktop）配置与插件的可复刻快照**：
把 `settings.yaml`、自定义技能、web profile 的组合与本地插件打包在一起，
用一条脚本还原到另一台机器上，得到同一套环境。

采集时间：**2026-09-18**　采集时版本：DSH Desktop **0.8.2** · Harness **0.1.2-rc.1**
第三方插件：dshmarket **1.45.1** / dsh-cost-meter **1.7.23** / 本地插件 dsh-global-prompt **0.1.0**

本仓库采用 **MIT 许可**；其中第三方内容的授权情况见 [`NOTICE.md`](./NOTICE.md)。

---

## 一、新机器上怎么用（三步）

前置：目标机器**已安装 DSH Desktop，并且启动过一次**（首次启动会生成
`%APPDATA%\dsh-desktop\harness` 与 `profiles\web` 骨架，本包只覆盖配置，不提供运行时）。

```powershell
# 1) 把整个快照目录拷到新机器（U 盘 / 网盘 / git clone 都行）

# 2) 先看一眼要做什么（不写任何文件）
pwsh -ExecutionPolicy Bypass -File .\restore.ps1 -DryRun

# 3) 正式复刻
pwsh -ExecutionPolicy Bypass -File .\restore.ps1 -InstallPlugins
```

`-InstallPlugins` 会用 profile 自带的 pnpm 从 npm 装回两个第三方插件（需要联网）。
不想联网就先把包拷过去，启动 DSH Desktop 后在 **插件市场** 里装 `dshmarket 1.45.1`
与 `dsh-cost-meter 1.7.23`，效果一样。

最后**完全退出并重新启动 DSH Desktop**，配置与插件在启动时加载。

### 启动安全检查（脚本自动做）

DSH 对 `dsh.profile.bundles` 里解析不到的包是 **fail loud**：启动直接失败，而不是忽略。
所以脚本在收尾前会自检一次，把暂时装不上的东西摘出去，保证新机器无论如何都进得去：

- 第三方插件没装 → 从 `package.json` 的 `dsh.profile.bundles` 里暂时摘除并提示；
  之后装了插件再重跑一次脚本（或让插件市场自己写回）即可恢复。
- 本地插件 `dsh-global-prompt` 目录缺失 → 把 `cordis.patch.yml` 清空成 `[]` 并提示，
  重跑脚本即可恢复「全局提示」页。

---

## 二、包里有什么

```
.
├─ restore.ps1                 一键复刻脚本（可反复运行，覆盖前自动备份）
├─ README.md                   本文件
├─ NOTICE.md                   第三方组件与许可说明（再分发前请读）
├─ LICENSE                     MIT
├─ manifest.json               采集元数据
├─ docs\
│  └─ windows-ppt-environment.md   Windows/DSH 下做 PPT 的环境事实（GBK、COM 渲染、PPTD 路线）
├─ config\
│  ├─ settings.yaml            用户设置：默认模型、权限模式、界面偏好、全局提示…
│  └─ skills\                  自定义技能
│     ├─ pptx-toolkit\         读写/体检/编辑/预览已有的 pptx（本仓库自带，MIT）
│     └─ html-to-pptx\         HTML 幻灯片 → 可编辑 pptx（上游 MIT）
└─ profile\web\                web profile 的配置
   ├─ package.json             依赖与组合 bundles（已清洗，见下）
   ├─ cordis.yml               组合根（空列表，树由 patch 层拼出来）
   ├─ cordis.patch.yml         用户补丁层：这里挂着本地插件 dsh-global-prompt
   ├─ pnpm-workspace.yaml      nodeLinker: hoisted 等安装约定
   ├─ pnpm-lock.yaml           第三方插件的锁定版本
   ├─ .npmrc                   pnpm 设置
   ├─ .dsh-market\state.json   插件市场状态（区域等）
   └─ .dsh-local-plugins\      本地自研插件
      ├─ dsh-global-prompt\    设置面板「全局提示」页 + 全局系统提示词段落
      └─ tools\                导航图标补丁脚本（全局提示/费用/插件市场 三个图标）
```

### 关键内容说明

| 内容 | 做了什么 |
| --- | --- |
| `settings.yaml` | 默认模型 `deepseek-v4-flash`、推理强度 max、权限模式 `danger-full-access`、Enter 行为「插话发送」、语言中文，以及 **`global-prompt`：全局提示正文**（对所有会话生效的系统提示词段落） |
| `dsh-global-prompt` | 本地插件：给设置面板加了「全局提示」页，保存即写入 `settings.yaml` 的 `global-prompt.text`，从下一个模型步骤起对所有会话（含子代理）生效 |
| `tools\apply-nav-icons.ps1` | 把设置面板导航里「全局提示 / 费用 / 插件市场」三个图标换成 消息气泡 / ¥ / 店铺。改的是安装目录里的外壳文件，**应用升级后要重跑**（未指定 `-AppDir` 时自动探测安装位置） |
| `skills\` | 自定义技能，直接落盘即可被 DSH 识别 |

### 技能：三种出稿路线怎么分工

| 需求 | 用什么 |
| --- | --- |
| 已有 `.pptx`，要读文字、查结构、体检、增删页、替换文字、导出预览图 | `pptx-toolkit`（本仓库自带，MIT，独立实现） |
| 手里是 HTML 幻灯片，要变成可编辑 pptx | `html-to-pptx`（上游 MIT，保留矢量文字 + 字体嵌入） |
| 从零按模板出稿 | DSH 内置的 `dsh-ppt`（PPTD 路线 + `pptd_*` 工具 + 16 套模板，随 DSH Desktop 安装，MIT） |

`pptx-toolkit` 需要 Python 依赖，装一次即可：

```powershell
py -m pip install -r config\skills\pptx-toolkit\requirements.txt
py config\skills\pptx-toolkit\tests\smoke_test.py     # 自检，26 项断言
```

> **注意**：`skills\pptx\`（Anthropic 的 pptx 技能）**不包含在本仓库内**。
> 它的 `LICENSE.txt` 禁止在 Anthropic 服务之外保留副本与再分发，因此已从仓库与
> 全部提交历史中剔除，替代能力由 `pptx-toolkit` 提供。详见 [`NOTICE.md`](./NOTICE.md)。

---

## 三、包里**没有**什么（以及为什么）

| 没有 | 原因 / 需要时怎么办 |
| --- | --- |
| `.credentials.yaml`（API Key） | 属于凭据，默认不复制、也不提交 Git。要用就把它放到 `config\credentials.yaml` 再跑 `restore.ps1 -WithCredentials`；或在新机器上到 **设置 → 模型** 重新填一次 Key |
| `skills\pptx\`（Anthropic pptx 技能） | 上游许可禁止再分发，见 [`NOTICE.md`](./NOTICE.md)；替代见 `pptx-toolkit` |
| `sessions\`、`attachments\` | 会话历史与附件，属于私有数据 |
| `storages\` | 运行期数据（费用账本、投影缓存等）。想要历史费用账本，手动拷 `harness\storages\cost-meter\ledger.json` 即可 |
| `kimi-ppt\` | PPT 插件的按会话工作目录与缓存 |
| `node_modules\`、`.generations\` | 运行时依赖，目标机器自己装（脚本或插件市场） |
| `desktop-storage.json` | 桌面端界面状态，含本机会话/工作区 ID，换机无意义 |

`profile\web\package.json` 相对原机器做了两处清洗，去掉机器相关状态：

- 删除 `dsh.desktop.generationProjection`（桌面端记录的插件代际信息）
- 删除 `pnpm.overrides` 里指向 `profiles\.generations\live\...` 的 `link:` 覆盖

这样在新机器上 `pnpm install` 会正常从 npm 安装 `dsh-cost-meter@1.7.23`，
而不是去一个不存在的本地代际目录找文件。

---

## 四、复刻之后该看到什么

1. 设置面板左侧：**通用设置 / 模型 / 插件 / Agent 预设 / 全局提示 / 费用 / 插件市场**，
   最后三个的图标分别是 气泡 / ¥ / 店铺。
2. **全局提示**页里有你原来那段内容，文本框可编辑，保存后写回 `settings.yaml`。
3. 模型列表里有 `DeepSeek-V4-Flash`（contextWindow 1000000，支持图片输入）。
4. 技能列表里有 `pptx-toolkit` 与 `html-to-pptx`。

## 五、版本与升级

本快照基于 DSH Desktop **0.8.2** / harness **0.1.2-rc.1**。上游已有更新版本，升级时注意：

1. 升级前先跑一次 `restore.ps1 -DryRun` 记录当前会被覆盖的文件，升级后如需回退可对照。
2. DSH Desktop 升级会**覆盖安装目录**，导航图标补丁随之失效（图标退回默认齿轮，
   不会报错）——重跑 `profile\web\.dsh-local-plugins\tools\apply-nav-icons.ps1` 即可。
3. 本地插件 `dsh-global-prompt` 与 profile 配置在 harness 目录里，**不受应用升级影响**。
4. 升级后若设置项被新版迁移或补了默认值，属正常现象；重新采集一份快照对比即可。

## 六、回滚

`restore.ps1` 每次覆盖前都会把原文件备份成 `<原文件名>.bak-<时间戳>`，
在目标 harness 目录里按文件名找回即可。
图标补丁单独回滚：`apply-nav-icons.ps1 -Revert`（从 `client.js.orig` 还原）。

`.gitignore` 已排除凭据、备份文件与授权受限的技能目录，避免误提交。

## 七、许可

本仓库自有内容采用 **MIT License**（Copyright (c) 2026 Jason Xie），见 [`LICENSE`](./LICENSE)。

随仓库分发的第三方内容与**有意排除**的内容，逐项列在 [`NOTICE.md`](./NOTICE.md)，
其中包括一份"看起来是 MIT、实为 Anthropic 专有材料的 pptx 技能"清单——
再分发或挑选同类技能前建议先读一遍。
