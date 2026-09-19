---
name: tun-fakeip-fetch
description: 内置网页获取（web_fetch / 网页获取）失败并报 `URL hostname "xxx" resolves to a non-public IP address`（WEB_BLOCKED_URL），或域名被 Clash / mihomo / Surge 的 TUN 模式解析成 fake-ip（198.18.x.x / 198.19.x.x）导致抓不到网页时使用——"网页获取失败""打不开这个网址""访问不了这个网站""non-public IP""fake-ip""TUN 代理""被抓取器拦了""绕过代理访问"。用 DoH 取真实 IP 直连或 `curl --doh-url` 取回网页正文，并顺带判定是解析被劫持还是站点本身故障。
whenToUse: 本机 TUN fake-ip 长期开启且已决定不改代理策略，因此 web_fetch 报 non-public IP 是常态——需要抓网页时直接用本技能，不必先试一次 web_fetch 再降级。仅当系统解析返回真实公网 IP 时，才回到内置 web_fetch。
---

# tun-fakeip-fetch

**给"网页获取被本地 TUN 代理拦住"准备的取证与绕过流程。** 一句话：内置抓取器被
fake-ip 解析挡下时，改用 `curl + DoH` 拿真实 IP 直连，把页面取回来。

## 文件位置

技能有两种被发现的位置，本技能在两者都有副本：

| 副本 | 路径 | 作用 |
| --- | --- | --- |
| 用户级 | `%DSH_HOME%\skills\tun-fakeip-fetch\` | 任何工作目录都可用；下文命令统一用 `$SkillDir` 指向这里 |
| 项目级 | `<项目根>\.dsh\skills\tun-fakeip-fetch\` | 只在该项目（其 git 根之下）可用，rank 100，优先级高于用户级 |
| 快照源 | `config\skills\tun-fakeip-fetch\`（DSH 配置快照仓库内） | 本技能随配置快照分发；`restore.ps1` 会把它还原到 `%DSH_HOME%\skills\` |

改完技能内容后，从**当前这份副本**同步到用户级；日常使用则指向用户级副本：

```powershell
# 在技能所在目录执行（例如快照仓库的 config\skills\tun-fakeip-fetch\）
pwsh -NoProfile -File scripts\install.ps1

# 日常取网页：$SkillDir 指向用户级副本
$SkillDir = Join-Path $env:DSH_HOME 'skills\tun-fakeip-fetch'
```

## 本机现状（2026-09-19 决定）

本机**保持 TUN + fake-ip 不变**：已明确决定不动代理侧的 DNS 策略，也不按域名加白名单
（fake-ip 是全局默认，逐域名放行等于给整个互联网列清单，不成立）。因此在这台机器上：

- 内置 `web_fetch` 对**几乎所有域名**都会报 `non-public IP`——这是常态，不是异常。
  要抓网页就**直接走下面的脚本**，不必先试一次 web_fetch 再降级。
- 不要再提议 `fake-ip-filter` / `enhanced-mode: redir-host`（已评估并否决，见"处置 C"）。
- 本技能是这台机器上取网页内容的**正规路径**，不是临时绕道。

## 症状

调用内置网页获取工具，返回类似：

```
Error: URL hostname "api.yuelimei.cn" resolves to a non-public IP address
```

对应错误码 `WEB_BLOCKED_URL`。**换域名、加重试都没用**——被拦的是解析结果，不是目标站点。
同一个网址用浏览器、`curl`、`Invoke-WebRequest` 打开却完全正常，这个"工具不行但浏览器行"的
反差就是本技能的典型入口。

## 根因

1. 本机 Clash Verge（内核 mihomo）开了 **TUN 模式**，系统 DNS 被指向 fake-ip 网关，
   所有域名都被解析到保留段 `198.18.0.0/15`。
2. 内置抓取器 `@deepseek-ai/dsh-web-fetch-http` 在真正发请求前，先用 `node:dns` 的
   `lookup` 解析一次域名，并要求**整组解析结果都是公网 unicast**；只要有一条不是，
   就整体拒绝（`lib/index.js` 里的 `resolvePublicAddresses` / `isPublicIpAddress`）。
3. `198.18.0.0/15` 属于保留段，于是**几乎所有域名**都会被判为"非公网地址"而拒绝。

关键认知：**fake-ip 并不影响实际上网**。TUN 会把发往 `198.18.x.x` 的连接映射回域名，
再按规则走代理或直连，所以浏览器、`curl`、`ping` 都正常。被拦下的只有带 SSRF 防护的抓取器。
因此这不是网络故障，是解析语义冲突。

## 第一步：判定（10 秒）

```powershell
Resolve-DnsName api.yuelimei.cn -Type A | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress
```

- 返回 `198.18.x.x` / `198.19.x.x` → **命中本技能**，按下面处理。
- 返回真实公网 IP → 不是 fake-ip 问题，回到 web_fetch 正常排查（站点是否 4xx/5xx、是否需要登录等）。

## 处置 A：一行 curl（最省事）

```powershell
curl.exe -sS --doh-url https://223.5.5.5/dns-query https://api.yuelimei.cn/wulongyuan/ping
```

`--doh-url` 让 curl 自己用 DoH 拿真实 IP，绕开被劫持的系统解析；Host 头与 TLS SNI 仍是域名，
证书照常校验。注意 DoH 端点要用 `/dns-query`（DNS wire format），
`https://223.5.5.5/resolve` 是 JSON API，配 `--doh-url` 会解析失败。

## 处置 B：用随附脚本（推荐，自动降级 + 说清走的是哪条路）

```powershell
# $SkillDir = Join-Path $env:DSH_HOME 'skills\tun-fakeip-fetch'
pwsh -NoProfile -File "$SkillDir\scripts\tun-fetch.ps1" <URL> [参数]
```

脚本按顺序尝试，取到第一个可用结果：

| 顺序 | 路径 | 说明 |
| --- | --- | --- |
| 1 | `proxy` | 直接 curl，走系统解析 / TUN（最贴近浏览器行为） |
| 2 | `direct` | DoH（AliDNS → Cloudflare → Google）取真实 IP，`curl --resolve` 直连 |
| 3 | `doh` | 交给 `curl --doh-url` 自己解析 |

第 1 步拿到 5xx 或失败时会自动降级到 2、3；三条路径的结论都会列在"提示"里，
方便区分**代理线路故障**和**站点真的挂了**。

常用参数：

| 参数 | 用途 |
| --- | --- |
| `-Preview 2000` | 调整正文预览长度（默认 1200 字符） |
| `-PlainText` | HTML 转纯文本：剥 script/style/head、标签与注释，还原实体，压缩空白（给模型读正文用） |
| `-BodyOnly` | 正文写 stdout、诊断写 stderr，可直接接管道 |
| `-Json` | 输出一行 JSON（mode/status/realIp/bytes/body），便于程序消费 |
| `-OutFile out.html` | 正文落盘，二进制安全（图片、PDF 也能存） |
| `-ResolveOnly` | 只对比"系统解析 vs DoH 真实 IP"，不发请求 |
| `-SkipProxy` / `-SkipDirect` | 只走直连 / 只走系统解析，用于定位问题出在哪一段 |
| `-Header 'Authorization: Bearer x'` | 附加请求头，可重复 |
| `-Method POST -Body '{...}'` | 发 POST |

输出解读：

- **路径**：`proxy`（TUN 正常）、`direct（DoH 真实 IP 直连）`（系统解析被劫持但直连可用）、
  `curl-doh`（前两者都不行时兜底）。
- **真实IP/节点**：`remote_ip`，是**最后一跳**的地址；发生跨域重定向后可能又是 fake-ip，
  这不代表直连失败。
- 退出码：`0` 成功、`1` 三条路径全失败、`3` 拿到 4xx/5xx 响应（响应本身取到了，只是状态码是错误码）。

示例：

```powershell
# 取一个被 fake-ip 劫持的接口
pwsh -NoProfile -File "$SkillDir\scripts\tun-fetch.ps1" https://api.yuelimei.cn/wulongyuan/ping

# 只要正文，接管道
$html = pwsh -NoProfile -File "$SkillDir\scripts\tun-fetch.ps1" https://www.baidu.com/ -BodyOnly 2>$null

# 先看解析情况再决定
pwsh -NoProfile -File "$SkillDir\scripts\tun-fetch.ps1" https://wly.yuelimei.cn/ -ResolveOnly

# 读网页正文（纯文本，省 token）
pwsh -NoProfile -File "$SkillDir\scripts\tun-fetch.ps1" https://www.baidu.com/ -PlainText -Preview 800
```

## 处置 C：根治——让域名不再走 fake-ip（**本机已否决**）

> 本机**不采用**本节方案：fake-ip 是 TUN 的全局默认，逐域名白名单等于给整个互联网列清单；
> 整机改 DNS 策略又会影响代理分流，已决定保持现状、由本技能兜底。以下留作备查，
> 除非将来整机调整 DNS 策略，否则不要在本机执行。

若要让内置 `web_fetch` 本身恢复（换机器或将来改主意时），就在 Clash Verge 的配置里把域名
排除出 fake-ip 段（Clash Verge → 订阅/配置 → 右键"编辑文件"或全局扩展配置）：

```yaml
dns:
  fake-ip-filter:
    - "*.yuelimei.cn"      # 换成你要放行的域名
    - "+.lan"
    - "*.local"
```

写入后重载配置，`Resolve-DnsName` 应返回真实公网 IP，此时内置网页获取工具本身就能用了。
代价是这些域名的 DNS 解析不再由代理统一调度，按需选择。

其他可选手段（都更重，非必要不用）：

- **临时关 TUN**：Clash Verge 关掉"Tun 模式"，系统解析恢复真实 IP；缺点是全局流量不再被代理接管。
- **写 hosts**：把真实 IP 写进 `C:\Windows\System32\drivers\etc\hosts`，需要管理员权限，
  且 CDN 换 IP 后会失效，只适合临时救急。

## 禁忌与边界

- **不要 `curl -k` / 关闭证书校验**：`--resolve` 与 `--doh-url` 都保持域名做 SNI，证书本来就能过。
- **不要把 fake-ip（198.18.x.x）写进 hosts、配置或代码**：它只在本机 TUN 会话内有意义。
- **不要把 URL 里的域名直接换成 IP 去访问**：虚拟主机 / SNI / 重定向都会错，必须用
  `--resolve` 或 `--doh-url` 保留域名。
- **DoH 结果是解析器视角的**：AliDNS 给的是境内线路 IP，可能与其它机器不同；不要把它当"唯一正确 IP"固化。
- **继续用内置工具而不是到处绕过**：这个技能只为"解析被劫持"这一种失败兜底。web_fetch 没有报
  `non-public IP` 时，优先用它，别习惯性改用 curl。
- 既有 HTTP 代理环境变量（`HTTP_PROXY` 等）时，curl 会走代理；脚本不修改这些变量，
  需要直连时自行在调用前清空。

## 本机事实（换机器先复核）

| 项 | 值 | 复核命令 |
| --- | --- | --- |
| TUN 网卡 | `Mihomo`（Meta Tunnel） | `Get-NetAdapter \| Where-Object Name -eq Mihomo` |
| 代理进程 | `clash-verge` / `verge-mihomo` | `Get-Process *mihomo*,*clash*` |
| 系统 DNS | `198.18.0.2` | `Get-DnsClientServerAddress -AddressFamily IPv4` |
| fake-ip 段 | `198.18.0.0/15` | `Resolve-DnsName <任意域名> -Type A` |
| curl | `C:\WINDOWS\system32\curl.exe`（8.21.0，支持 `--doh-url` / `--resolve`） | `curl.exe --version` |
| 拦截代码 | `@deepseek-ai/dsh-web-fetch-http/lib/index.js` 的 `resolvePublicAddresses` | — |

## 自检

```powershell
pwsh -NoProfile -File "$SkillDir\scripts\selftest.ps1"
```

自检会验证：fake-ip 判定是否命中、被劫持域名能否取回、`-Json` / `-OutFile` / `-ResolveOnly`
是否正常，以及脚本在空正文（204）下不崩。
