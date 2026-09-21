# dsh-nav-icons

让设置面板的**导航图标补丁在 DSH Desktop 升级后自愈**的本地插件（Host 半侧，无客户端代码）。

## 它解决什么问题

设置面板左侧「全局提示 / 费用 / 插件市场」三个入口原本是默认齿轮图标。要换成
消息气泡 / ¥ / 店铺，只能给 DSH Desktop 安装目录里的外壳 bundle 打补丁：

```
<appDir>\node_modules\@deepseek-ai\dsh-client-ui-settings-general\lib\client.js
```

**为什么不能用正规插件做**：`settings.section` 的注册项只有 `id` / `order` / `label`，
**没有 `icon` 字段**（0.9.0 实测），图标在 `navIcon(id)` 里按 section id 硬编码，
外部插件无法自行提供。所以只能补文件。

**麻烦在于**：安装目录会被应用升级整体覆盖，补丁随之丢失——每次升级后图标都会退回齿轮，
需要人工重跑 `tools/apply-nav-icons.ps1`。

## 它怎么解决

本插件挂在 profile 的组合里（在 harness 目录，升级动不到），每次 DSH 启动时：

1. 找到安装目录里的 bundle；
2. **已打过补丁 → 只读一次文件就返回**，不启动任何子进程；
3. 补丁缺失（例如刚升级完）→ 调用 `tools/apply-nav-icons.ps1` 补上。

补丁内容本身只有一份（仍在 `.ps1` 里，含图标定义、锚点唯一性校验、覆盖前备份、
以及 `node --check` 语法校验失败自动还原）；本插件只负责「该跑的时候跑一下」，
不复制补丁内容，避免两处维护漂移。

失败永远不影响启动：所有异常只打印警告。补丁生效需要刷新一次页面（若刚补上）。

## 配置（都可省略）

| 组合行字段 | 环境变量 | 说明 |
| --- | --- | --- |
| `scriptPath` | — | 指定补丁脚本路径；默认相对本插件解析 |
| `bundlePath` | `DSH_DESKTOP_APP_DIR` | 指定 `resources\app` 目录；默认自动探测 LOCALAPPDATA / Program Files |
| — | `DSH_NAV_ICONS_PWSH` | 指定 PowerShell 可执行文件；默认依次尝试 `pwsh`、`powershell` |

## 卸载

删除 `cordis.patch.yml` 里 `id: nav-icons` 的那一行，然后还原安装目录：

```powershell
pwsh -File ..\tools\apply-nav-icons.ps1 -Revert
```

## 许可

MIT（Copyright (c) 2026 Jason Xie）。
