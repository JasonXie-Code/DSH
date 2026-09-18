<#
  把本目录里的一套 DSH 配置与插件复刻到本机。

  前置条件：目标机器已经装好 DSH Desktop，并且至少启动过一次
  （首次启动会生成 %APPDATA%\dsh-desktop\harness 与 profiles\web 骨架）。

  用法：
    powershell -ExecutionPolicy Bypass -File restore.ps1
    powershell -ExecutionPolicy Bypass -File restore.ps1 -InstallPlugins
    powershell -ExecutionPolicy Bypass -File restore.ps1 -WithCredentials
    powershell -ExecutionPolicy Bypass -File restore.ps1 -DryRun        # 只打印要做什么

  参数：
    -DshHome          目标 harness 目录，默认 %APPDATA%\dsh-desktop\harness
    -AppDir           DSH Desktop 的 resources\app 目录，图标补丁用；默认自动探测
    -WithCredentials  若 config\credentials.yaml 存在，一并恢复 API 凭据
    -InstallPlugins   用 profile 自带的 pnpm 安装第三方插件（dshmarket / dsh-cost-meter）
    -SkipIconPatch    不打导航图标补丁
    -DryRun           只打印动作，不写任何文件

  脚本可反复运行：每次都先备份被覆盖的文件（*.bak-<时间戳>）。
#>
[CmdletBinding()]
param(
  [string]$DshHome,
  [string]$AppDir,
  [switch]$WithCredentials,
  [switch]$InstallPlugins,
  [switch]$SkipIconPatch,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:actions = 0

function Say($text)  { Write-Host $text }
function Step($text) { Write-Host ''; Write-Host "== $text" }
function Warn($text) { Write-Host "!! $text" -ForegroundColor Yellow }

function Backup-IfExists([string]$path) {
  if (Test-Path -LiteralPath $path) {
    $backup = "$path.bak-$stamp"
    if ($DryRun) { Say "  [dry] 备份 $path -> $backup" }
    else { Copy-Item -LiteralPath $path -Destination $backup -Force }
  }
}

function Copy-Tree([string]$from, [string]$to) {
  if (-not (Test-Path -LiteralPath $from)) { Warn "源目录不存在，跳过：$from"; return }
  if ($DryRun) { Say "  [dry] 复制目录 $from -> $to"; return }
  if (-not (Test-Path -LiteralPath $to)) { $null = New-Item -ItemType Directory -Force -Path $to }
  $null = robocopy $from $to /E /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) { throw "复制失败（robocopy 退出码 $LASTEXITCODE）：$from -> $to" }
  $script:actions++
}

function Copy-One([string]$from, [string]$to) {
  if (-not (Test-Path -LiteralPath $from)) { Warn "源文件不存在，跳过：$from"; return }
  Backup-IfExists $to
  if ($DryRun) { Say "  [dry] 复制文件 $from -> $to"; return }
  $parent = Split-Path -Parent $to
  if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
  Copy-Item -LiteralPath $from -Destination $to -Force
  $script:actions++
}

# ── 1. 定位目标 harness ────────────────────────────────────────
if (-not $DshHome) { $DshHome = Join-Path $env:APPDATA 'dsh-desktop\harness' }
if (-not (Test-Path -LiteralPath $DshHome)) {
  throw "找不到目标 harness 目录：$DshHome`n请先安装并启动一次 DSH Desktop，或用 -DshHome 指定路径。"
}
Say "目标 harness：$DshHome"

# ── 2. 定位 DSH Desktop 安装目录（图标补丁用）─────────────────
if (-not $AppDir) {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop\resources\app'),
    (Join-Path $env:ProgramFiles 'DSH Desktop\resources\app'),
    (Join-Path ${env:ProgramFiles(x86)} 'DSH Desktop\resources\app')
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { $AppDir = $c; break }
  }
}
if ($AppDir -and (Test-Path -LiteralPath $AppDir)) { Say "DSH Desktop：$AppDir" }
else { Warn '没有找到 DSH Desktop 安装目录，将跳过导航图标补丁（可用 -AppDir 指定）' }

if ($DryRun) { Warn 'DryRun 模式：只打印动作，不写入任何文件' }

# ── 3. 用户设置 ────────────────────────────────────────────────
Step '用户设置'
Copy-One (Join-Path $root 'config\settings.yaml') (Join-Path $DshHome 'settings.yaml')

Step '自定义技能（skills）'
Copy-Tree (Join-Path $root 'config\skills') (Join-Path $DshHome 'skills')

if ($WithCredentials) {
  Step 'API 凭据'
  $cred = Join-Path $root 'config\credentials.yaml'
  if (Test-Path -LiteralPath $cred) {
    Copy-One $cred (Join-Path $DshHome '.credentials.yaml')
  } else {
    Warn "没有 $cred；请把它放到 config\credentials.yaml 后重跑，或在新机器的 设置 → 模型 里重新填 Key。"
  }
}

# ── 4. profile 配置与本地插件 ──────────────────────────────────
Step 'web profile 配置与本地插件'
$profileWeb = Join-Path $DshHome 'profiles\web'
Copy-Tree (Join-Path $root 'profile\web') $profileWeb

# ── 5. 本地插件的 node_modules 联接 ────────────────────────────
Step '本地插件链接'
$pluginSrc = Join-Path $profileWeb '.dsh-local-plugins\dsh-global-prompt'
$nodeModules = Join-Path $profileWeb 'node_modules'
$link = Join-Path $nodeModules 'dsh-global-prompt'
if (-not (Test-Path -LiteralPath (Join-Path $root 'profile\web\.dsh-local-plugins\dsh-global-prompt'))) {
  Warn "备份包里没有本地插件（跳过）：$pluginSrc"
} else {
  if ($DryRun) {
    Say "  [dry] 删除旧链接（若存在）：$link"
    Say "  [dry] 建立目录联接 $link -> $pluginSrc"
  } else {
    if (-not (Test-Path -LiteralPath $nodeModules)) { $null = New-Item -ItemType Directory -Force -Path $nodeModules }
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Recurse -Force }
    $null = New-Item -ItemType Junction -Path $link -Target $pluginSrc
    Say "  已建立联接：$link"
    $script:actions++
  }
}

# ── 6. 第三方插件安装 ──────────────────────────────────────────
Step '第三方插件'
if ($InstallPlugins) {
  $pnpm = Join-Path $DshHome '.desktop-bin\pnpm.cmd'
  if (-not (Test-Path -LiteralPath $pnpm)) {
    Warn "没有找到 $pnpm（DSH Desktop 启动后会生成它）。"
    Warn '请先启动一次 DSH Desktop，再重跑本脚本；或在 插件市场 里手动安装 dshmarket 与 dsh-cost-meter。'
  } elseif ($DryRun) {
    Say "  [dry] 在 $profileWeb 执行：pnpm install --no-frozen-lockfile"
  } else {
    Say "  安装中（dshmarket、dsh-cost-meter 从 npm 拉取，需要联网）…"
    Push-Location $profileWeb
    try {
      & $pnpm install --no-frozen-lockfile
      if ($LASTEXITCODE -ne 0) { Warn "pnpm install 退出码 $LASTEXITCODE，可能没装全，请检查上面的输出。" }
      else { Say '  插件依赖安装完成。'; $script:actions++ }
    } finally { Pop-Location }
  }
} else {
  Say '  已跳过（未指定 -InstallPlugins）。安装方式二选一：'
  Say '    a) 重跑本脚本并加 -InstallPlugins（需要联网）'
  Say '    b) 启动 DSH Desktop 后在 插件市场 里安装 dshmarket 1.45.1 与 dsh-cost-meter 1.7.23'
}

# ── 7. 启动安全检查 ────────────────────────────────────────────
# dsh.profile.bundles 里列了却解析不到的包会让 DSH 启动直接失败（fail loud），
# cordis.patch.yml 指向不存在的插件同理。所以启动前先自检一次，
# 把暂时装不上的东西摘出去，保证无论如何都进得去。
Step '启动安全检查'
$manifestPath = Join-Path $profileWeb 'package.json'
$patchFile = Join-Path $profileWeb 'cordis.patch.yml'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$optional = @('dshmarket', 'dsh-cost-meter')
$present = @()
$absent = @()
foreach ($p in $optional) {
  if (Test-Path -LiteralPath (Join-Path $profileWeb "node_modules\$p\package.json")) { $present += $p } else { $absent += $p }
}

if ($absent.Count -eq 0) {
  Say "  第三方插件已就位：$($present -join '、')"
} else {
  if ($DryRun) {
    Say "  [dry] 从 dsh.profile.bundles 移除未安装的：$($absent -join '、')"
  } elseif (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.dsh.profile.bundles = @(@('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app') + $present)
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)
  }
  Warn "未安装：$($absent -join '、') —— 已暂时从 profile bundles 摘除，否则 DSH 启动会直接报错。"
  Warn '装法：重跑本脚本并加 -InstallPlugins（联网），或启动后在 插件市场 里安装。'
}

if (Test-Path -LiteralPath (Join-Path $pluginSrc 'package.json')) {
  Say '  本地插件 dsh-global-prompt 已就位'
} elseif (Test-Path -LiteralPath $patchFile) {
  if ($DryRun) {
    Say '  [dry] 本地插件缺失，清空 cordis.patch.yml 的补丁层'
  } else {
    $emptyPatch = "# 本地插件缺失，补丁层暂时清空；重跑 restore.ps1 可恢复。`r`n[]`r`n"
    [System.IO.File]::WriteAllText($patchFile, $emptyPatch, $utf8NoBom)
  }
  Warn '本地插件缺失，已清空 cordis.patch.yml（设置页的「全局提示」会暂时消失）。'
}

# ── 8. 导航图标补丁 ────────────────────────────────────────────
Step '导航图标补丁'
$iconScript = Join-Path $profileWeb '.dsh-local-plugins\tools\apply-nav-icons.ps1'
if ($SkipIconPatch) {
  Say '  已跳过（-SkipIconPatch）'
} elseif (-not $AppDir) {
  Say '  跳过：没有定位到 DSH Desktop 安装目录'
} elseif (-not (Test-Path -LiteralPath $iconScript)) {
  Warn "找不到 $iconScript（跳过）"
} elseif ($DryRun) {
  Say "  [dry] 运行 $iconScript -AppDir `"$AppDir`""
} else {
  $env:DSH_HOME = $DshHome
  & $iconScript -AppDir $AppDir
}

# ── 9. 收尾 ────────────────────────────────────────────────────
Step '完成'
Say "共执行 $script:actions 项写入操作。接下来："
Say '  1) 完全退出并重新启动 DSH Desktop（配置与插件在启动时加载）'
Say '  2) 打开 设置：应能看到「全局提示」页，内容与来源机器一致'
Say '  3) 若没带凭据：到 设置 → 模型 填一次 API Key'
Say '  4) 图标补丁在 DSH Desktop 升级后会被覆盖，届时重跑：'
Say "     powershell -ExecutionPolicy Bypass -File `"$iconScript`""
if (-not $DryRun) { Say "被覆盖的文件都留了 *.bak-$stamp 备份，可随时回滚。" }
