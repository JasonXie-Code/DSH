#Requires -Version 7.0
<#
.SYNOPSIS
    tun-fakeip-fetch 技能自检。
.DESCRIPTION
    验证脚本本身可用：fake-ip 判定、被劫持域名抓取、-Json / -OutFile / -BodyOnly /
    -ResolveOnly 各输出模式，以及空正文（204）不崩。
    只在"当前网络确实存在 TUN fake-ip"时才断言劫持场景，否则跳过并提示。
.EXAMPLE
    pwsh -NoProfile -File selftest.ps1
    pwsh -NoProfile -File selftest.ps1 -ProbeUrl https://api.yuelimei.cn/wulongyuan/ping
#>
[CmdletBinding()]
param(
    [string]$ProbeUrl = 'https://api.yuelimei.cn/wulongyuan/ping',
    [string]$PublicUrl = 'https://www.baidu.com/'
)

$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  [FAIL] $Name $(if ($Detail) { "-> $Detail" })" -ForegroundColor Red
    }
}

function Skip-That {
    param([string]$Name, [string]$Detail = '')
    $script:Skipped++
    Write-Host "  [SKIP] $Name $(if ($Detail) { "-> $Detail" })" -ForegroundColor Yellow
}

function Invoke-Fetch {
    param([string[]]$Arguments)
    $raw = & pwsh -NoProfile -File $script:ScriptPath @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Output = $raw; Exit = $LASTEXITCODE }
}

$script:ScriptPath = Join-Path $PSScriptRoot 'tun-fetch.ps1'
Write-Host "tun-fakeip-fetch selftest" -ForegroundColor Cyan
Write-Host "脚本: $script:ScriptPath"

if (-not (Test-Path -LiteralPath $script:ScriptPath)) {
    Write-Host "找不到 tun-fetch.ps1" -ForegroundColor Red
    exit 1
}

$probeHost = ([uri]$ProbeUrl).Host
$systemIps = @()
try {
    $systemIps = @(Resolve-DnsName -Name $probeHost -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress)
} catch { }
$hasFakeIp = [bool]($systemIps | Where-Object { $_ -like '198.18.*' -or $_ -like '198.19.*' })

Write-Host "`n环境" -ForegroundColor Cyan
Write-Host "  $probeHost 系统解析: $(if ($systemIps.Count) { $systemIps -join ', ' } else { '(无结果)' })"
Write-Host "  TUN fake-ip: $(if ($hasFakeIp) { '命中' } else { '未命中' })"

Write-Host "`n1) -ResolveOnly 输出结构" -ForegroundColor Cyan
$r = Invoke-Fetch @($ProbeUrl, '-ResolveOnly')
Assert-That 'ResolveOnly 退出码为 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
Assert-That 'ResolveOnly 给出系统解析' ($r.Output -match '系统解析') ''
Assert-That 'ResolveOnly 给出 DoH 真实IP' ($r.Output -match 'DoH 真实IP') ''
if ($hasFakeIp) {
    Assert-That 'ResolveOnly 判定命中 fake-ip' ($r.Output -match '命中 TUN fake-ip') ''
} else {
    Skip-That 'ResolveOnly 判定命中 fake-ip' '当前环境没有 fake-ip'
}

Write-Host "`n2) 抓取被劫持域名（含空正文 / 204）" -ForegroundColor Cyan
$r = Invoke-Fetch @($ProbeUrl)
Assert-That '抓取退出码为 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
Assert-That '输出带路径说明' ($r.Output -match '路径\s*:') ''
Assert-That '输出带状态码' ($r.Output -match '状态码\s*:\s*\d{3}') ''

Write-Host "`n3) -Json 模式" -ForegroundColor Cyan
$r = Invoke-Fetch @($PublicUrl, '-Json')
$json = $null
try { $json = $r.Output.Trim() | ConvertFrom-Json } catch { }
Assert-That 'JSON 可解析' ($null -ne $json -and $null -ne $json.status) ''
if ($json) {
    Assert-That 'JSON.status 为 200' ($json.status -eq 200) "status=$($json.status)"
    Assert-That 'JSON.body 非空' ($null -ne $json.body -and $json.body.Length -gt 0) ''
}

Write-Host "`n4) -BodyOnly 模式" -ForegroundColor Cyan
$body = & pwsh -NoProfile -File $script:ScriptPath $PublicUrl -BodyOnly 2>$null | Out-String
Assert-That 'BodyOnly 正文非空' ($body.Trim().Length -gt 0) ''

Write-Host "`n5) -OutFile 模式" -ForegroundColor Cyan
$outPath = Join-Path ([System.IO.Path]::GetTempPath()) "tunfetch-selftest-$([guid]::NewGuid().ToString('N')).html"
try {
    $r = Invoke-Fetch @($PublicUrl, '-OutFile', $outPath)
    Assert-That 'OutFile 退出码为 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
    Assert-That 'OutFile 文件已落盘且非空' ((Test-Path -LiteralPath $outPath) -and (Get-Item -LiteralPath $outPath).Length -gt 0) ''
} finally {
    if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n6) -PlainText 正文提取" -ForegroundColor Cyan
$plainPath = Join-Path ([System.IO.Path]::GetTempPath()) "tunfetch-plain-$([guid]::NewGuid().ToString('N')).txt"
try {
    $r = Invoke-Fetch @($PublicUrl, '-PlainText', '-OutFile', $plainPath, '-Preview', '40')
    Assert-That 'PlainText 退出码为 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
    $plain = ''
    if (Test-Path -LiteralPath $plainPath) { $plain = [System.IO.File]::ReadAllText($plainPath, [System.Text.Encoding]::UTF8) }
    Assert-That 'PlainText 得到纯文本' ($plain.Length -gt 20) "len=$($plain.Length)"
    Assert-That 'PlainText 无残留标签' (-not ($plain.Contains('<div') -or $plain.Contains('<style') -or $plain.Contains('<script'))) ''
    Assert-That 'PlainText 短于原文' ($plain.Length -lt 200000) "len=$($plain.Length)"
} finally {
    if (Test-Path -LiteralPath $plainPath) { Remove-Item -LiteralPath $plainPath -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n7) 参数校验" -ForegroundColor Cyan
$r = Invoke-Fetch @('not-a-url')
Assert-That '非法 URL 退出码为 2' ($r.Exit -eq 2) "exit=$($r.Exit)"

Write-Host "`n结果: PASS=$script:Passed FAIL=$script:Failed SKIP=$script:Skipped" -ForegroundColor Cyan
if ($script:Failed -gt 0) { exit 1 }
exit 0
