/**
 * dsh-global-prompt — 全局提示（Host 半侧）
 *
 * 拥有 `global-prompt` 设置命名空间，并把它的内容注册成一条全局系统提示词段落。
 * 该段落以函数形式提供文本，因此每次组装提示词时都会读取当前值：在设置页保存后，
 * 从下一个模型步骤起生效，无需重启。
 *
 * 段落是全局注册的（插件挂在部署根上下文上），所以对本机所有 Agent 生效，
 * 包括子代理与后续新建的会话。
 * @module dsh-global-prompt
 */
import z from '@deepseek-ai/schemastery'

/** Cordis 插件名。 */
export const name = 'global-prompt'

/** 依赖的宿主服务：设置存储与系统提示词注册表。 */
export const inject = ['settings', 'systemPrompt']

/**
 * 组合行配置：既能给出初始全局提示，也能调整段落在提示词中的位置。
 * `text` 同时作为设置命名空间的 base 层——设置页的“还原默认”会回到这个值。
 */
export const Config = z.object({
  text: z.string().default(''),
  order: z.number().default(100),
})

/** 设置命名空间；客户端设置页按同一个名字读写。 */
const NAMESPACE = 'global-prompt'

/** 段落名独立命名，避免与任何随附段落相撞。 */
const SECTION = 'user:global-prompt'

/** 该命名空间对外解析出的形状。 */
const PromptSchema = z.object({ text: z.string().default('') })

/**
 * 注册设置命名空间与全局提示词段落。
 * @param ctx - 插件上下文（部署根作用域）。
 * @param config - 组合行配置。
 */
export function apply(ctx, config) {
  const order = Number.isFinite(config?.order) ? config.order : 100

  const scope = ctx.settings.register(NAMESPACE, PromptSchema, {
    base: { text: typeof config?.text === 'string' ? config.text : '' },
  })

  ctx.effect(() => ctx.systemPrompt.section({
    name: SECTION,
    order,
    text: () => {
      const value = scope.get()
      return typeof value?.text === 'string' ? value.text.trim() : ''
    },
  }), 'global-prompt: system-prompt section')

  console.log(`[dsh-global-prompt] 全局提示已就绪：段落 ${SECTION}（order ${order}），内容 ${scope.get()?.text ? '已配置' : '为空'}`)
}
