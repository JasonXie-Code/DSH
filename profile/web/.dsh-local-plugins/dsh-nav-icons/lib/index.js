/**
 * dsh-nav-icons — 让「导航图标补丁」在 DSH Desktop 升级后自愈（Host 半侧）。
 *
 * 为什么需要它：设置面板的导航图标在 `dsh-client-ui-settings-general` 的
 * `navIcon(id)` 里按 section id 硬编码，而 `settings.section` 只接受
 * id / order / label，**没有 icon 字段**，外部插件无法自行提供图标。
 * 因此只能在安装目录里给外壳打一个最小补丁——而安装目录会被应用升级整体覆盖，
 * 补丁随之丢失。
 *
 * 本插件在每次 DSH 启动时检查补丁是否在位，缺失就地重新打上，于是升级后无需人工干预。
 * 补丁内容本身仍然只有一份：`tools/apply-nav-icons.ps1`（含图标定义、锚点校验、
 * 备份与 `node --check` 语法校验失败自动还原）。本插件只负责「该跑的时候跑一下」，
 * 不复制补丁内容，避免两处维护漂移。
 *
 * 设计约束：**任何失败都不允许影响 DSH 启动**——所有异常只记警告。
 * 已打过补丁时只读一次文件就返回，不启动子进程。
 * @module dsh-nav-icons
 */

import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/** Cordis 插件名。 */
export const name = 'nav-icons'

/** 补丁写入的标记；同时是「已打过补丁」的判据。 */
const MARKER = 'dsh-nav-icons:start'

/** 被打补丁的外壳 bundle，相对 `<appDir>`。 */
const BUNDLE_REL = join(
  'node_modules',
  '@deepseek-ai',
  'dsh-client-ui-settings-general',
  'lib',
  'client.js',
)

/** `client.js` 到 `<appDir>` 需要上溯的层数。 */
const BUNDLE_DEPTH = 5

/**
 * 候选的 DSH Desktop `resources\app` 目录，顺序即优先级。
 * @returns {string[]} 候选路径（可能为空串，调用方需过滤）。
 */
function candidateAppDirs() {
  const dirs = [process.env.DSH_DESKTOP_APP_DIR]
  if (process.env.LOCALAPPDATA) {
    dirs.push(join(process.env.LOCALAPPDATA, 'Programs', 'DSH Desktop', 'resources', 'app'))
  }
  for (const key of ['ProgramFiles', 'ProgramFiles(x86)']) {
    if (process.env[key]) dirs.push(join(process.env[key], 'DSH Desktop', 'resources', 'app'))
  }
  return dirs.filter((dir) => typeof dir === 'string' && dir.length > 0)
}

/**
 * 找到实际存在的外壳 bundle。
 * @returns {string | null} bundle 绝对路径；找不到返回 null。
 */
function locateBundle() {
  for (const appDir of candidateAppDirs()) {
    const target = join(appDir, BUNDLE_REL)
    if (existsSync(target)) return target
  }
  return null
}

/**
 * 定位补丁脚本。
 *
 * 默认相对本插件自身解析：插件位于
 * `<profile>\node_modules\dsh-nav-icons\lib\index.js`（node_modules 下是指向
 * `.dsh-local-plugins\dsh-nav-icons` 的目录联接，Node 解析出的仍是联接这一侧），
 * 上溯三层即 profile 目录，再进 `.dsh-local-plugins\tools`。
 * @param {string} explicit 组合行显式配置的脚本路径。
 * @returns {string | null} 脚本绝对路径；找不到返回 null。
 */
function locateScript(explicit) {
  if (typeof explicit === 'string' && explicit.length > 0 && existsSync(explicit)) {
    return explicit
  }

  const here = dirname(fileURLToPath(import.meta.url))
  const fromPlugin = resolve(here, '..', '..', '..', '.dsh-local-plugins', 'tools', 'apply-nav-icons.ps1')
  if (existsSync(fromPlugin)) return fromPlugin

  if (process.env.DSH_HOME) {
    const fromHome = join(
      process.env.DSH_HOME,
      'profiles',
      'web',
      '.dsh-local-plugins',
      'tools',
      'apply-nav-icons.ps1',
    )
    if (existsSync(fromHome)) return fromHome
  }
  return null
}

/**
 * 找到可用的 PowerShell。
 * @returns {string | null} 可执行文件名；找不到返回 null。
 */
function locatePowerShell() {
  const override = process.env.DSH_NAV_ICONS_PWSH
  if (override) return override
  for (const candidate of ['pwsh', 'powershell']) {
    const probe = spawnSync(candidate, ['-NoProfile', '-Command', 'exit 0'], {
      stdio: 'ignore',
      timeout: 20_000,
      windowsHide: true,
    })
    if (!probe.error && probe.status === 0) return candidate
  }
  return null
}

/**
 * 确保补丁在位；缺失则调用补丁脚本补上。
 * @param {object | undefined} config 组合行配置（可选 `scriptPath` / `bundlePath`）。
 * @returns {string} 结果说明，用于日志。
 */
export function ensurePatched(config) {
  const target =
    typeof config?.bundlePath === 'string' && config.bundlePath.length > 0
      ? config.bundlePath
      : locateBundle()
  if (!target || !existsSync(target)) {
    return '未找到 DSH Desktop 安装目录，跳过（可用 DSH_DESKTOP_APP_DIR 指定）'
  }

  // 快速路径：已打过补丁就只读一次文件，不启动任何子进程。
  if (readFileSync(target, 'utf8').includes(MARKER)) {
    return '补丁已在位，无需处理'
  }

  const script = locateScript(config?.scriptPath)
  if (!script) return '找不到 apply-nav-icons.ps1，跳过（应用升级后请手动重跑）'

  const shell = locatePowerShell()
  if (!shell) return '找不到 pwsh / powershell，跳过（应用升级后请手动重跑）'

  const appDir = resolve(target, ...Array(BUNDLE_DEPTH).fill('..'))
  const result = spawnSync(
    shell,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-AppDir', appDir],
    { encoding: 'utf8', timeout: 120_000, windowsHide: true },
  )

  if (result.error) return `调用补丁脚本失败：${result.error.message}`
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim().split('\n').slice(-3).join(' / ')
    return `补丁脚本退出码 ${result.status}：${detail}`
  }

  const applied = existsSync(target) && readFileSync(target, 'utf8').includes(MARKER)
  return applied
    ? '检测到补丁缺失，已重新打上（刷新页面后生效）'
    : '脚本执行完成但未检出补丁标记，请手动检查'
}

/**
 * 注册自愈动作。插件不依赖任何服务，装载即生效。
 * @param {import('@deepseek-ai/cordis').Context} ctx 插件上下文。
 * @param {object | undefined} config 组合行配置。
 */
export function apply(ctx, config) {
  ctx.effect(() => {
    let summary
    try {
      summary = ensurePatched(config)
    } catch (error) {
      summary = `自愈失败（不影响启动）：${error?.message ?? error}`
    }
    console.log(`[dsh-nav-icons] ${summary}`)
  }, 'nav-icons: ensure patched')
}
