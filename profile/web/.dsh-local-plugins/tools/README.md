# tools —— 本地补丁脚本

## apply-nav-icons.ps1

给设置面板左侧导航的三个入口换图标：

| 入口 | section id | 图标 |
| --- | --- | --- |
| 全局提示 | `global-prompt` | 消息气泡 |
| 费用 | `cost-meter` | ¥ 符号 |
| 插件市场 | `market` | 店铺 |

### 为什么要打补丁

本版本 DSH 的设置外壳把导航图标**按 section id 写死**在
`@deepseek-ai/dsh-client-ui-settings-general/lib/client.js` 的 `navIcon()` 里：

```js
function navIcon(id) {
  if (id === "models") return IconDataOutline16
  if (id === "agent-presets") return IconAgentPresetOutline16
  if (id === "plugins") return IconPersonalizationOutline16
  return IconSettingsOutline16        // 其余 id 全部落到默认齿轮
}
```

而 `settings.section` 的注册项只有 `id` / `order` / `label`，**没有 icon 选项**，
随附图标库里也没有气泡 / 货币 / 店铺这三个图形（74 个图标中最近的是对话与思考类）。
所以外部插件无法自行提供图标，只能给外壳打一个最小补丁：在 `navIcon()` 里加三个
id 分支，并在同一模块作用域内用设计系统同款风格（16×16、`stroke=currentColor`、
圆头圆角）画三个内联 SVG 图标。默认回退分支不动，未知 id 仍是原来的齿轮。

### 用法

```powershell
# 应用（默认安装路径）
powershell -ExecutionPolicy Bypass -File apply-nav-icons.ps1

# 装到别的盘/别的用户目录
powershell -ExecutionPolicy Bypass -File apply-nav-icons.ps1 -AppDir "D:\...\resources\app"

# 还原
powershell -ExecutionPolicy Bypass -File apply-nav-icons.ps1 -Revert
```

脚本是幂等的：已打过补丁会直接提示并退出；应用前会把原文件备份为
`client.js.orig`，打完用 DSH 自带的 node 做一次 `--check` 语法校验，失败会自动还原。

### ⚠️ 应用升级后会失效

补丁改的是 **DSH Desktop 安装目录**里的文件，应用升级会把它覆盖回原样。
届时三个图标会退回默认齿轮（**不会报错、不影响任何功能**），重跑一次本脚本即可恢复。

如果哪天 DSH 给 `settings.section` 加上了 icon 注册项，这个脚本就可以删掉了 ——
到时候把三个图标挪进 `dsh-global-prompt` 的客户端 bundle 更合适。
