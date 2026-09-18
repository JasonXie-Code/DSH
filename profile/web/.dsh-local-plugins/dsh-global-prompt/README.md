# dsh-global-prompt

给 DeepSeek Harness 的设置面板加一个**全局提示**页：写一段话，它对本机所有会话生效。

## 它做了什么

- **Host 半侧**（`lib/index.js`）注册设置命名空间 `global-prompt`，并把它的内容注册为一条全局系统提示词段落（段落名 `user:global-prompt`，默认 order 100，位于部署人设之后）。段落文本按函数提供，每次组装提示词时读取当前值，所以保存后从下一个模型步骤起生效，不需要重启。
- **客户端半侧**（`client/client.js`）在 `settings.section` 槽位注册「全局提示」页面，读写同一个设置命名空间。留空表示不注入任何内容。

内容是全局注册的（插件挂在部署根上下文），因此对主会话、子代理以及之后新建的会话都生效。

## 存储位置

值写在 `$DSH_HOME/settings.yaml` 的 `global-prompt` 段里（由 `dsh-settings-file` 提供方持久化）：

```yaml
global-prompt:
  text: |
    始终用中文回答，先给结论再给理由。
```

也可以直接编辑该文件，设置页会跟随刷新。

## 安装位置

| 位置 | 作用 |
| --- | --- |
| `profiles/web/.dsh-local-plugins/dsh-global-prompt/` | 插件源码（本目录，可直接改） |
| `profiles/web/node_modules/dsh-global-prompt` | 指向源码的目录联接，供宿主解析 |
| `profiles/web/package.json` → `dependencies` | `link:` 依赖，保证 pnpm 重新安装时不会被清掉 |
| `profiles/web/cordis.patch.yml` | 插入一行 loader 条目，把插件挂进组合树 |

改完源码后刷新浏览器页面即可看到 UI 变化；改动 Host 半侧（`lib/index.js`）时，profile 的 `patchReload: live` 会让组合自动重载，必要时重启一次 DSH。

## 配置（可选）

在 `profiles/web/cordis.patch.yml` 的那一行上加 `config`：

```yaml
- insert:
    - id: global-prompt
      name: 'dsh-global-prompt'
      config:
        text: 预置文本        # 作为设置页的 base 层；“还原默认”回到这里
        order: 100           # 提示词段落位置，越小越靠前
```

## 卸载

1. 删除 `profiles/web/cordis.patch.yml` 里 `id: global-prompt` 的那一行（或整段 `insert`）。
2. 删除 `profiles/web/node_modules/dsh-global-prompt` 联接与 `profiles/web/package.json` 里的 `dsh-global-prompt` 依赖。
3. 删除本目录，并按需清掉 `$DSH_HOME/settings.yaml` 里的 `global-prompt` 段。
