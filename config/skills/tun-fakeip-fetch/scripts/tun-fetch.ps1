#Requires -Version 7.0
<#
.SYNOPSIS
    绕过 Clash/mihomo TUN 的 fake-ip 解析，抓取网页内容。

.DESCRIPTION
    内置网页抓取（web_fetch）在发请求前会用系统 DNS 解析一次域名，解析结果
    不落在公网 unicast 就直接拒绝，报：
        URL hostname "xxx" resolves to a non-public IP address  (WEB_BLOCKED_URL)

    本机 Clash Verge(mihomo) 开了 TUN，系统 DNS 被劫持到 fake-ip 段
    198.18.0.0/15，于是所有走系统解析的域名都会被上面这条规则拦下。
    fake-ip 本身并不影响上网（TUN 会把 198.18.x.x 映射回域名走代理），
    所以 curl / 浏览器都正常，只有带 SSRF 防护的抓取器会被挡。

    本脚本按下面的顺序自动降级，取到第一个可用结果：
      1. proxy  —— 直接 curl，用系统解析（走 TUN，最贴近浏览器行为）
      2. direct —— DoH(AliDNS/Cloudflare/Google) 拿真实 IP，curl --resolve 直连
      3. doh    —— 交给 curl --doh-url 自己用 DoH 解析
    出口会写明实际用了哪条路径、真实 IP、状态码和耗时；proxy 与 direct
    结果不一致时（例如代理线路 502 而直连正常）会同时给出两条路径的结论。

.PARAMETER Url
    要抓取的完整 URL，例如 https://api.yuelimei.cn/wulongyuan/ping

.PARAMETER Method
    GET / HEAD / POST，默认 GET。

.PARAMETER Body
    POST 请求体（配合 -Method POST）。

.PARAMETER Header
    附加请求头，可重复，例如 -Header 'Authorization: Bearer x'

.PARAMETER OutFile
    把响应正文写入该文件（二进制安全）。

.PARAMETER MaxTime
    单次请求超时秒数，默认 30。

.PARAMETER Preview
    未指定 -OutFile 时，标准输出里预览的正文长度上限（字符），默认 1200。

.PARAMETER PlainText
    把 HTML 转成纯文本再输出：剥掉 script/style/head、注释与所有标签，还原实体、压缩空白。
    拿网页正文给模型阅读时用；配合 -OutFile 落盘的是 .txt 内容。

.PARAMETER BodyOnly
    只把正文写到标准输出，诊断信息写到 stderr，便于管道处理。

.PARAMETER Json
    输出一行 JSON（含 mode/status/realIp/body 等字段），便于程序消费。

.PARAMETER ResolveOnly
    只打印系统解析结果与 DoH 真实 IP，不发请求。

.PARAMETER SkipProxy
    跳过第 1 步，只走 DoH 真实 IP 直连。

.PARAMETER SkipDirect
    跳过第 2、3 步，只走系统解析（用来复现"只有代理线路能用"的情况）。

.EXAMPLE
    pwsh -NoProfile -File tun-fetch.ps1 https://api.yuelimei.cn/wulongyuan/ping

.EXAMPLE
    pwsh -NoProfile -File tun-fetch.ps1 https://wly.yuelimei.cn/ -Json

.EXAMPLE
    pwsh -NoProfile -File tun-fetch.ps1 https://example.com/ -ResolveOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Url,
    [ValidateSet('GET', 'HEAD', 'POST')][string]$Method = 'GET',
    [string]$Body,
    [string[]]$Header = @(),
    [string]$OutFile,
    [int]$MaxTime = 30,
    [int]$Preview = 1200,
    [switch]$PlainText,
    [switch]$BodyOnly,
    [switch]$Json,
    [switch]$ResolveOnly,
    [switch]$SkipProxy,
    [switch]$SkipDirect
)

$ErrorActionPreference = 'Stop'
$script:CurlExe = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $script:CurlExe) { $script:CurlExe = 'curl.exe' }
$script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$script:DohEndpoints = @(
    'https://223.5.5.5/resolve?name={0}&type={1}',        # AliDNS
    'https://1.1.1.1/dns-query?name={0}&type={1}',        # Cloudflare
    'https://8.8.8.8/resolve?name={0}&type={1}'           # Google
)

function Write-Diag([string]$Message) {
    if ($BodyOnly -or $Json) { [Console]::Error.WriteLine($Message) } else { Write-Host $Message }
}

# ── IP 分类 ────────────────────────────────────────────────────────────────
function Get-IpKind([string]$Ip) {
    if ([string]::IsNullOrWhiteSpace($Ip)) { return 'unknown' }
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$parsed)) { return 'unknown' }
    $b = $parsed.GetAddressBytes()
    if ($b.Length -eq 16) {
        if ($parsed.IsIPv4MappedToIPv6) { $b = $parsed.MapToIPv4().GetAddressBytes() } else { return 'public' }
    }
    if ($b[0] -eq 198 -and ($b[1] -eq 18 -or $b[1] -eq 19)) { return 'fake-ip' }   # Clash/mihomo fake-ip 段
    if ($b[0] -eq 127 -or $b[0] -eq 10 -or $b[0] -eq 0) { return 'loopback' }
    if ($b[0] -eq 192 -and $b[1] -eq 168) { return 'private' }
    if ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) { return 'private' }
    if ($b[0] -eq 169 -and $b[1] -eq 254) { return 'link-local' }
    if ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) { return 'cgnat' }
    if ($b[0] -ge 224) { return 'reserved' }
    return 'public'
}

function Get-SystemIps([string]$HostName) {
    $ips = @()
    try {
        $ips = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress)
    } catch { }
    if ($ips.Count -eq 0) {
        try {
            $ips = @(Resolve-DnsName -Name $HostName -Type AAAA -ErrorAction Stop |
                Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress)
        } catch { }
    }
    return $ips
}

function Get-DohIps([string]$HostName, [int]$Timeout = 8) {
    foreach ($type in @('A', 'AAAA')) {
        foreach ($tpl in $script:DohEndpoints) {
            $endpoint = $tpl -f $HostName, $type
            $raw = ''
            try {
                $raw = (& $script:CurlExe -sS --max-time $Timeout -H 'Accept: application/dns-json' $endpoint 2>$null | Out-String).Trim()
            } catch { continue }
            if ([string]::IsNullOrWhiteSpace($raw) -or $raw[0] -ne '{') { continue }
            try { $doc = $raw | ConvertFrom-Json } catch { continue }
            if (-not $doc.Answer) { continue }
            $wanted = if ($type -eq 'A') { 1 } else { 28 }
            $found = @($doc.Answer | Where-Object { $_.type -eq $wanted } | ForEach-Object { $_.data })
            if ($found.Count -gt 0) { return @($found | Select-Object -Unique) }
        }
    }
    return @()
}

# ── HTML → 纯文本 ──────────────────────────────────────────────────────────
function ConvertTo-PlainText([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $s = $Html
    # 两轮：页面里常嵌一层被转义的 HTML（如 &lt;style&gt;…），只在"剥标签 → 解实体"
    # 之后才会露成真标签，所以解完实体必须再剥一轮，否则整段 CSS/脚本会留在正文里。
    for ($pass = 0; $pass -lt 2; $pass++) {
        $s = [regex]::Replace($s, '(?is)<(script|style|noscript|svg|head)\b[^>]*>.*?</\1\s*>', ' ')
        $s = [regex]::Replace($s, '(?is)<!--.*?-->', ' ')
        $s = [regex]::Replace($s, '(?i)<(br|/p|/div|/li|/tr|/h[1-6]|/section|/article)\b[^>]*>', "`n")
        $s = [regex]::Replace($s, '(?s)<[^>]+>', ' ')
        $s = [System.Net.WebUtility]::HtmlDecode($s)
    }
    $s = [regex]::Replace($s, '[ \t\u00a0\u3000]+', ' ')
    $s = [regex]::Replace($s, '(\r?\n[ \t]*){2,}', "`n")
    return $s.Trim()
}

# ── 抓取 ──────────────────────────────────────────────────────────────────
function Invoke-CurlFetch {
    param(
        [string]$Target,
        [string]$ResolveSpec,
        [string]$DohUrl,
        [string]$OutPath
    )
    $cargs = @(
        '-sS', '--max-time', "$MaxTime", '-L', '--max-redirs', '5',
        '-o', $OutPath,
        '-w', '%{http_code}|%{remote_ip}|%{size_download}|%{time_total}|%{url_effective}',
        '-A', $script:UserAgent
    )
    if ($Method -ne 'GET') { $cargs += @('-X', $Method) }
    if ($Body) { $cargs += @('--data-raw', $Body) }
    if ($ResolveSpec) { $cargs += @('--resolve', $ResolveSpec) }
    if ($DohUrl) { $cargs += @('--doh-url', $DohUrl) }
    foreach ($h in $Header) { $cargs += @('-H', $h) }
    $cargs += $Target

    $meta = ''
    $err = ''
    try {
        $out = (& $script:CurlExe @cargs 2>&1 | Out-String).Trim()
        $lines = @($out -split "`r?`n" | Where-Object { $_ -ne '' })
        if ($lines.Count -gt 0) {
            $meta = $lines[-1]
            if ($lines.Count -gt 1) { $err = ($lines[0..($lines.Count - 2)] -join ' ').Trim() }
        }
    } catch {
        $err = $_.Exception.Message
    }
    $exit = $LASTEXITCODE

    $status = 0; $ip = ''; $bytes = 0; $seconds = 0; $effective = ''
    if ($meta -match '^(\d{3})\|([^|]*)\|([^|]*)\|([^|]*)\|(.*)$') {
        $status = [int]$Matches[1]
        $ip = $Matches[2]
        $bytes = [int64]($Matches[3] -replace '^$', '0')
        $seconds = [double]($Matches[4] -replace '^$', '0')
        $effective = $Matches[5]
    }
    return [pscustomobject]@{
        Exit      = $exit
        Status    = $status
        Ip        = $ip
        Bytes     = $bytes
        Seconds   = [math]::Round($seconds, 3)
        Effective = $effective
        Error     = $err
        Out       = $OutPath
    }
}

# ── 主流程 ────────────────────────────────────────────────────────────────
$uri = $null
try { $uri = [uri]$Url } catch { }
# 这里不能用 Write-Error：$ErrorActionPreference='Stop' 会让它先抛异常，拿不到预期的退出码
if (-not $uri -or -not $uri.Host) { Write-Diag "无法解析 URL: $Url"; exit 2 }
if ($uri.Scheme -notin @('http', 'https')) { Write-Diag "只支持 http/https: $Url"; exit 2 }

$hostName = $uri.Host
$port = if ($uri.Port -gt 0) { $uri.Port } else { if ($uri.Scheme -eq 'https') { 443 } else { 80 } }

$systemIps = Get-SystemIps $hostName
$systemKinds = @($systemIps | ForEach-Object { "$_($(Get-IpKind $_))" })

if ($ResolveOnly) {
    $dohIps = Get-DohIps $hostName
    Write-Diag "域名      : $hostName"
    Write-Diag "系统解析  : $(if ($systemIps.Count) { $systemKinds -join ', ' } else { '(无结果)' })"
    Write-Diag "DoH 真实IP: $(if ($dohIps.Count) { (@($dohIps | ForEach-Object { "$_($(Get-IpKind $_))" }) -join ', ') } else { '(未取到)' })"
    if ($systemIps | Where-Object { (Get-IpKind $_) -eq 'fake-ip' }) {
        Write-Diag "结论      : 命中 TUN fake-ip，内置 web_fetch 会被 SSRF 防护拦下，请用本脚本或 curl --doh-url。"
    } else {
        Write-Diag "结论      : 系统解析看起来是公网地址，web_fetch 通常可直接用。"
    }
    exit 0
}

$tempFiles = New-Object System.Collections.Generic.List[string]
$result = $null
$mode = ''
$notes = New-Object System.Collections.Generic.List[string]
$proxyResult = $null

function New-TempOut {
    $p = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "tunfetch-$([guid]::NewGuid().ToString('N')).tmp")
    $tempFiles.Add($p) | Out-Null
    return $p
}

try {
    # 1) 系统解析（走 TUN / 代理）
    if (-not $SkipProxy) {
        $proxyResult = Invoke-CurlFetch -Target $Url -OutPath (New-TempOut)
        if ($proxyResult.Exit -eq 0 -and $proxyResult.Status -lt 500) {
            $result = $proxyResult
            $mode = 'proxy（系统解析 / TUN）'
        } else {
            $why = if ($proxyResult.Exit -ne 0) { "curl 退出码 $($proxyResult.Exit) $($proxyResult.Error)" } else { "HTTP $($proxyResult.Status)" }
            $notes.Add("系统解析路径失败：$why") | Out-Null
        }
    }

    # 2) DoH 真实 IP + --resolve 直连
    if (-not $result -and -not $SkipDirect) {
        $dohIps = Get-DohIps $hostName
        if ($dohIps.Count -eq 0) { $notes.Add('DoH 未取到真实 IP（DoH 出口可能也被拦）') | Out-Null }
        foreach ($ip in $dohIps) {
            $addr = if ($ip.Contains(':')) { "[$ip]" } else { $ip }
            $spec = "$hostName`:$port`:$addr"
            $attempt = Invoke-CurlFetch -Target $Url -ResolveSpec $spec -OutPath (New-TempOut)
            if ($attempt.Exit -eq 0 -and $attempt.Status -lt 500) {
                $result = $attempt
                $mode = "direct（DoH 真实 IP $ip 直连）"
                break
            }
            $why = if ($attempt.Exit -ne 0) { "curl 退出码 $($attempt.Exit) $($attempt.Error)" } else { "HTTP $($attempt.Status)" }
            $notes.Add("直连 $ip 失败：$why") | Out-Null
        }
    }

    # 3) 交给 curl 自己做 DoH
    if (-not $result -and -not $SkipDirect) {
        $attempt = Invoke-CurlFetch -Target $Url -DohUrl 'https://223.5.5.5/dns-query' -OutPath (New-TempOut)
        if ($attempt.Exit -eq 0 -and $attempt.Status -lt 500) {
            $result = $attempt
            $mode = 'curl-doh（curl --doh-url 解析）'
        } else {
            $why = if ($attempt.Exit -ne 0) { "curl 退出码 $($attempt.Exit) $($attempt.Error)" } else { "HTTP $($attempt.Status)" }
            $notes.Add("curl --doh-url 失败：$why") | Out-Null
        }
    }

    # 4) 兜底：保留系统解析路径的响应（哪怕 5xx），至少让调用方看到真实错误
    if (-not $result -and $proxyResult) {
        $result = $proxyResult
        $mode = 'proxy（仅拿到错误响应）'
    }

    if (-not $result) {
        Write-Diag "抓取失败：$Url"
        foreach ($n in $notes) { Write-Diag "  - $n" }
        exit 1
    }

    # 正文（注意：PowerShell 的 if 语句会把空数组展开成 $null，这里必须显式赋值）
    [byte[]]$bytes = [byte[]]::new(0)
    if (Test-Path -LiteralPath $result.Out) {
        $read = [System.IO.File]::ReadAllBytes($result.Out)
        if ($null -ne $read) { $bytes = [byte[]]$read }
    }
    $isBinary = $false
    $sniffLength = [Math]::Min(512, $bytes.Length)
    for ($i = 0; $i -lt $sniffLength; $i++) { if ($bytes[$i] -eq 0) { $isBinary = $true; break } }
    $text = ''
    if (-not $isBinary -and $bytes.Length -gt 0) { $text = [System.Text.Encoding]::UTF8.GetString($bytes) }
    if ($PlainText -and -not $isBinary) { $text = ConvertTo-PlainText $text }

    if ($OutFile) {
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($PlainText -and -not $isBinary) {
            [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            [System.IO.File]::WriteAllBytes($OutFile, $bytes)
        }
    }

    $summary = [ordered]@{
        url       = $Url
        mode      = $mode
        status    = $result.Status
        realIp    = $result.Ip
        bytes     = $result.Bytes
        seconds   = $result.Seconds
        effective = $result.Effective
        outFile   = $OutFile
        binary    = $isBinary
        notes     = @($notes)
    }

    if ($BodyOnly) {
        foreach ($n in $notes) { [Console]::Error.WriteLine("note: $n") }
        [Console]::Error.WriteLine("mode: $mode | status: $($result.Status) | ip: $($result.Ip) | bytes: $($result.Bytes)")
        [Console]::Out.Write($text)
        exit 0
    }

    if ($Json) {
        $summary['body'] = if ($isBinary) { $null } else { $text }
        $summary | ConvertTo-Json -Depth 4 -Compress
        exit 0
    }

    Write-Diag "URL      : $Url"
    Write-Diag "路径     : $mode"
    Write-Diag "状态码   : $($result.Status)   真实IP/节点: $($result.Ip)   字节: $($result.Bytes)   耗时: $($result.Seconds)s"
    if ($result.Effective -and $result.Effective -ne $Url) { Write-Diag "最终地址 : $($result.Effective)" }
    if ($OutFile) { Write-Diag "已保存   : $OutFile" }
    foreach ($n in $notes) { Write-Diag "提示     : $n" }
    if ($systemIps | Where-Object { (Get-IpKind $_) -eq 'fake-ip' }) {
        Write-Diag "说明     : 系统解析为 fake-ip（$($systemKinds -join ', ')），内置 web_fetch 会拒绝该域名，请以本结果为准。"
    }
    Write-Diag ''
    if ($isBinary) {
        Write-Diag "（正文是二进制，已省略预览；用 -OutFile 落盘）"
    } elseif ($text.Length -gt 0) {
        # 注意：PowerShell 变量名不区分大小写，这里不能用 $preview —— 它会撞上 [int] 类型的 $Preview 参数
        $bodyPreview = if ($text.Length -gt $Preview) { $text.Substring(0, $Preview) + "`n...（截断，共 $($text.Length) 字符，用 -OutFile 或 -Preview 调整）" } else { $text }
        Write-Diag $bodyPreview
    } else {
        Write-Diag '（正文为空）'
    }
    if ($result.Status -ge 400) { exit 3 }
    exit 0
} finally {
    foreach ($p in $tempFiles) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
}
