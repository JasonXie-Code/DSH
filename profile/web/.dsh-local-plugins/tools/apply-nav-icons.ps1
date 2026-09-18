<#
  给设置面板左侧导航的三个入口换图标：
    global-prompt（全局提示） → 消息气泡
    cost-meter   （费用）     → ¥ 符号
    market       （插件市场） → 店铺

  背景：本版本 DSH 的设置外壳把导航图标按 section id 写死在
  @deepseek-ai/dsh-client-ui-settings-general/lib/client.js 的 navIcon() 里，
  而且 settings.section 的注册项只有 id/order/label，没有 icon 选项，
  外部插件无法自行提供图标。因此只能在安装目录里给外壳打一个最小补丁。

  ⚠️ 该文件属于 DSH Desktop 安装目录，应用升级后会被覆盖。
     图标会退回默认齿轮（不会报错），重跑本脚本即可恢复。

  用法：
    pwsh -File apply-nav-icons.ps1
    pwsh -File apply-nav-icons.ps1 -AppDir "D:\其他安装路径\resources\app"
    pwsh -File apply-nav-icons.ps1 -Revert      # 从备份还原
#>
[CmdletBinding()]
param(
  [string]$AppDir = 'C:\Users\Administrator\AppData\Local\Programs\DSH Desktop\resources\app',
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'

$target = Join-Path $AppDir 'node_modules\@deepseek-ai\dsh-client-ui-settings-general\lib\client.js'
$backup = "$target.orig"

if (-not (Test-Path -LiteralPath $target)) {
  throw "找不到设置外壳 bundle：$target`n请用 -AppDir 指定 DSH Desktop 的 resources\app 目录。"
}

if ($Revert) {
  if (-not (Test-Path -LiteralPath $backup)) { throw "没有找到备份 $backup，无法还原。" }
  Copy-Item -LiteralPath $backup -Destination $target -Force
  Write-Host "已还原：$target"
  exit 0
}

$marker = 'dsh-nav-icons:start'
$content = Get-Content -LiteralPath $target -Raw -Encoding UTF8

if ($content.Contains($marker)) {
  Write-Host "已是补丁后的状态，无需重复应用：$target"
  exit 0
}

# 图标定义：与设计系统同风格（16x16、stroke=currentColor、圆头圆角）。
$iconDefs = @'
		/* dsh-nav-icons:start —— 本地补丁：为「全局提示 / 费用 / 插件市场」提供导航图标。
		   由 profiles/web/.dsh-local-plugins/tools/apply-nav-icons.ps1 注入；应用升级后重跑该脚本即可。 */
		const dshNavIconProps = (size, className) => ({
			width: size,
			height: size,
			className,
			viewBox: "0 0 16 16",
			fill: "none",
			xmlns: "http://www.w3.org/2000/svg",
			stroke: "currentColor",
			strokeWidth: 1.2,
			strokeLinecap: "round",
			strokeLinejoin: "round"
		});
		/** 消息气泡。 */
		const IconNavBubble16 = ({ size = 16, className }) => (0, react_jsx_runtime.jsx)("svg", Object.assign(dshNavIconProps(size, className), {
			children: (0, react_jsx_runtime.jsx)("path", {
				d: "M3.6 2.6H12.4A2 2 0 0 1 14.4 4.6V9A2 2 0 0 1 12.4 11H6.7L3.9 13.4 3.6 11A2 2 0 0 1 1.6 9V4.6A2 2 0 0 1 3.6 2.6Z"
			})
		}));
		/** 人民币符号。 */
		const IconNavYuan16 = ({ size = 16, className }) => (0, react_jsx_runtime.jsx)("svg", Object.assign(dshNavIconProps(size, className), {
			children: (0, react_jsx_runtime.jsx)("path", {
				d: "M4.1 3.3 8 7.4 11.9 3.3M8 7.4V13M5.3 9.1H10.7M5.3 11.1H10.7"
			})
		}));
		/** 店铺（插件市场）。 */
		const IconNavStore16 = ({ size = 16, className }) => (0, react_jsx_runtime.jsx)("svg", Object.assign(dshNavIconProps(size, className), {
			children: (0, react_jsx_runtime.jsx)("path", {
				d: "M2.1 6.4 3.3 2.9H12.7L13.9 6.4M2.1 6.4H13.9M3.5 6.4V13.1H12.5V6.4M6.7 13.1V10.6H9.3V13.1"
			})
		}));
		/* dsh-nav-icons:end */
'@

# 三个分支：插到默认齿轮之前，因此默认回退行为不变。
$branches = @'
			if (id === "global-prompt") return (0, react_jsx_runtime.jsx)(IconNavBubble16, {
				className: SettingsRoot_module_css_default.navIcon,
				size: 16
			});
			if (id === "cost-meter") return (0, react_jsx_runtime.jsx)(IconNavYuan16, {
				className: SettingsRoot_module_css_default.navIcon,
				size: 16
			});
			if (id === "market") return (0, react_jsx_runtime.jsx)(IconNavStore16, {
				className: SettingsRoot_module_css_default.navIcon,
				size: 16
			});
'@

$anchorDef = 'function navIcon(id) {'
# 优先插在 navIcon 的说明注释之前，让注释仍紧贴 navIcon；注释被上游改写时退回函数锚点。
$anchorDoc = '/** Nav glyph by section id; unknown ids fall back to the settings gear. */'
$anchorDefault = 'return (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconSettingsOutline16, {'

foreach ($a in @($anchorDef, $anchorDefault)) {
  $count = ([regex]::Matches($content, [regex]::Escape($a))).Count
  if ($count -ne 1) {
    throw "锚点定位失败（出现 $count 次，期望 1 次）：$a`n外壳代码可能已变化，请重新核对 navIcon() 的实现。"
  }
}
$insertBefore = if (([regex]::Matches($content, [regex]::Escape($anchorDoc))).Count -eq 1) { $anchorDoc } else { $anchorDef }

Copy-Item -LiteralPath $target -Destination $backup -Force
Write-Host "已备份原始文件：$backup"

$patched = $content.Replace($insertBefore, $iconDefs + $insertBefore)
$patched = $patched.Replace($anchorDefault, $branches + "`t`t`t" + $anchorDefault)

if (-not $patched.Contains($marker)) { throw '补丁未写入，未修改任何文件。' }

# 用 .NET 写入：保持 UTF-8 无 BOM（Set-Content -Encoding UTF8 在 Windows
# PowerShell 5.1 下会写入 BOM，bundle 是直接下发给浏览器的 JS，不引入 BOM）。
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, $patched, $utf8NoBom)

# 语法校验：用 DSH 自带的 node 解析补丁后的 bundle（只检查语法，不执行）。
$node = Join-Path $env:DSH_HOME '.desktop-bin\node.cmd'
if (Test-Path -LiteralPath $node) {
  & $node --check $target
  if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $target -Force
    throw '补丁后语法校验失败，已自动还原。'
  }
  Write-Host '语法校验通过。'
} else {
  Write-Host "未找到 $node，跳过语法校验（如需还原请加 -Revert）。"
}

Write-Host "补丁完成：$target"
Write-Host '刷新浏览器页面后生效；应用升级后重跑本脚本。'
