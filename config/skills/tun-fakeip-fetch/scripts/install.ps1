#Requires -Version 7.0
<#
.SYNOPSIS
    把 tun-fakeip-fetch 技能安装/同步到 DSH 用户技能目录，使其在所有项目里可用。
.DESCRIPTION
    技能有两种发现位置：
      - 项目根 .dsh/skills/<name>/（rank 100，随项目走）
      - <DSH_HOME>/skills/<name>/（rank 400，全项目可用）

    本脚本把当前这份副本（例如 DSH 配置快照仓库里的 config/skills/<name>/）
    同步到用户级目录，使其在所有项目里可用。改完技能内容后重跑本脚本
    （或用 -WhatIf 预览差异）。
.EXAMPLE
    pwsh -NoProfile -File install.ps1
.EXAMPLE
    pwsh -NoProfile -File install.ps1 -Target 'D:\some\skills'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Target
)

$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $PSScriptRoot
$skillName = Split-Path -Leaf $source

if (-not $Target) {
    $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
    $Target = Join-Path (Join-Path $dshHome 'skills') $skillName
}

Write-Host "源目录  : $source"
Write-Host "目标目录: $Target"

if ($source -eq $Target) {
    Write-Host '源与目标相同，无需同步。'
    exit 0
}

if ($PSCmdlet.ShouldProcess($Target, '同步技能文件')) {
    if (-not (Test-Path -LiteralPath $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }
    # 只同步技能本体：SKILL.md 与 scripts/，不动目标目录里其它文件
    Copy-Item -LiteralPath (Join-Path $source 'SKILL.md') -Destination (Join-Path $Target 'SKILL.md') -Force
    $scriptsSource = Join-Path $source 'scripts'
    if (Test-Path -LiteralPath $scriptsSource) {
        $scriptsTarget = Join-Path $Target 'scripts'
        if (-not (Test-Path -LiteralPath $scriptsTarget)) {
            New-Item -ItemType Directory -Path $scriptsTarget -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $scriptsSource '*.ps1') -Destination $scriptsTarget -Force
    }
    Write-Host '已同步。技能目录变化会在下一个模型步骤刷新目录。'
}

Get-ChildItem -LiteralPath $Target -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
