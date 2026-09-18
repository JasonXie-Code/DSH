/**
 * dsh-global-prompt — 全局提示（Web 客户端半侧）
 *
 * 在设置面板里注册一个「全局提示」页面：一个文本框，写入 dsh-global-prompt 的
 * `global-prompt` 设置命名空间。Host 半侧把该命名空间的内容作为一条全局系统提示词
 * 段落注入，因此保存后对所有会话生效。
 *
 * 本文件是构建产物格式（lazy CJS factory），与 dsh-market / dsh-cost-meter 的
 * client bundle 同构：`window.__ModuleLoader__.load({ id, factory })`，factory 内只
 * require 平台种子表里的模块（react），没有其他外部依赖。
 */
window.__ModuleLoader__.load({ id: "dsh-global-prompt", factory: (require) => {
	var module = { exports: {} };
	var exports = module.exports;

	var react = require("react");
	var h = react.createElement;

	/** 与 Host 半侧共用的设置命名空间。 */
	var NAMESPACE = "global-prompt";

	/** 导航位置：排在「Agent 预设」(20) 与「费用」(30) 之间。 */
	var NAV_ORDER = 25;

	var COLOR = {
		primary: "var(--dsw-alias-label-primary)",
		secondary: "var(--dsw-alias-label-secondary)",
		border: "var(--dsw-alias-border-l1)",
		layer: "var(--dsw-alias-bg-layer-2)",
		brand: "var(--dsw-alias-brand-primary)",
		error: "var(--dsw-alias-state-error-primary)",
		success: "var(--dsw-alias-state-success-primary)",
	};

	var buttonBase = {
		font: "inherit",
		fontSize: "13px",
		lineHeight: "20px",
		padding: "6px 16px",
		borderRadius: "8px",
		cursor: "pointer",
		border: "1px solid " + COLOR.border,
		background: "transparent",
		color: COLOR.primary,
	};

	/**
	 * 把命名空间快照折成「用户当前写下的文本」。
	 * 解析不出形状时返回 undefined，让页面渲染自己的缺失状态而不是半解码的值。
	 * @param value - `settings.describe` 里该命名空间的解析值。
	 * @returns `{ text }`，或 undefined。
	 */
	function decodePrompt(value) {
		if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
		return { text: typeof value.text === "string" ? value.text : "" };
	}

	/** 订阅一个已绑定的 settings scope。 */
	function useScopeSnapshot(scope) {
		var pair = react.useState(function () { return scope.getSnapshot(); });
		var snapshot = pair[0];
		var setSnapshot = pair[1];
		react.useEffect(function () {
			setSnapshot(scope.getSnapshot());
			return scope.subscribe(function () { setSnapshot(scope.getSnapshot()); });
		}, [scope]);
		return snapshot;
	}

	/** 一行说明文字。 */
	function hint(text, color) {
		return h("div", {
			style: {
				fontSize: "12.5px",
				lineHeight: "1.7",
				color: color || COLOR.secondary,
			},
		}, text);
	}

	/**
	 * 渲染错误边界：本页出错时只让本页显示提示，绝不把整个设置面板带崩。
	 * （注册点外面没有别的边界，这里必须自带一层。）
	 */
	class Guard extends react.Component {
		constructor(props) {
			super(props);
			this.state = { failed: false };
		}
		static getDerivedStateFromError() {
			return { failed: true };
		}
		render() {
			if (this.state.failed) {
				return h("div", {
					style: { fontSize: "13px", color: COLOR.error, padding: "4px 0" },
				}, "「全局提示」页面渲染出错，可在 .dsh-local-plugins/dsh-global-prompt 中排查；其他设置不受影响。");
			}
			return this.props.children;
		}
	}

	/** 「全局提示」设置页面。 */
	function GlobalPromptSection(props) {
		var scope = props.scope;
		var snapshot = useScopeSnapshot(scope);

		var resolved = snapshot && snapshot.value && typeof snapshot.value.text === "string"
			? snapshot.value.text
			: "";
		var draftPair = react.useState(null);
		var draft = draftPair[0];
		var setDraft = draftPair[1];
		var statusPair = react.useState("idle");
		var status = statusPair[0];
		var setStatus = statusPair[1];

		var text = draft === null ? resolved : draft;
		var dirty = draft !== null && draft !== resolved;
		var writable = Boolean(snapshot && snapshot.writable);
		var unavailable = Boolean(snapshot) && snapshot.status === "unavailable";
		var saved = resolved.trim().length > 0;

		function onChange(event) {
			setDraft(event.target.value);
			setStatus("idle");
		}

		function save() {
			if (!writable || !dirty) return;
			setStatus("saving");
			var next = text;
			// 清空即取消用户覆盖，回落到组合 base / schema 默认值。
			var pending = next.trim().length === 0 ? scope.unset("text") : scope.set("text", next);
			Promise.resolve(pending).then(function () {
				setDraft(null);
				setStatus("saved");
			}, function () {
				setStatus("error");
			});
		}

		function restore() {
			if (!writable) return;
			setStatus("saving");
			Promise.resolve(scope.unset("text")).then(function () {
				setDraft(null);
				setStatus("saved");
			}, function () {
				setStatus("error");
			});
		}

		var statusText = "已生效";
		var statusColor = COLOR.success;
		if (status === "saving") {
			statusText = "保存中…";
			statusColor = COLOR.secondary;
		} else if (status === "saved") {
			statusText = "已保存";
			statusColor = COLOR.success;
		} else if (status === "error") {
			statusText = "保存失败，请重试";
			statusColor = COLOR.error;
		} else if (dirty) {
			statusText = "有未保存的修改";
			statusColor = COLOR.secondary;
		} else if (!saved) {
			statusText = "未设置";
			statusColor = COLOR.secondary;
		}

		return h("div", { style: { padding: "4px 0 24px", maxWidth: "760px" } }, [
			h("div", {
				key: "title",
				style: { fontSize: "15px", fontWeight: 600, color: COLOR.primary, marginBottom: "8px" },
			}, "全局提示"),
			h("div", { key: "desc", style: { marginBottom: "16px" } }, hint(
				"这里写下的内容会作为独立段落进入系统提示词，对本机所有会话生效（含子代理与新建会话）。"
			)),
			h("textarea", {
				key: "editor",
				value: text,
				onChange: onChange,
				disabled: !writable,
				spellCheck: false,
				placeholder: "例如：\n· 始终用中文回答，先给结论再给理由。\n· 改动代码前先说明影响范围。\n· 不要引入新的第三方依赖。",
				style: {
					display: "block",
					width: "100%",
					boxSizing: "border-box",
					minHeight: "240px",
					padding: "12px 14px",
					borderRadius: "10px",
					border: "1px solid " + COLOR.border,
					background: COLOR.layer,
					color: COLOR.primary,
					fontFamily: "inherit",
					fontSize: "13px",
					lineHeight: "1.7",
					resize: "vertical",
					outline: "none",
				},
			}),
			h("div", {
				key: "footer",
				style: {
					display: "flex",
					alignItems: "center",
					gap: "10px",
					marginTop: "12px",
					flexWrap: "wrap",
				},
			}, [
				h("button", {
					key: "save",
					type: "button",
					onClick: save,
					disabled: !writable || !dirty,
					style: Object.assign({}, buttonBase, {
						border: "1px solid transparent",
						background: COLOR.brand,
						color: "#fff",
						opacity: !writable || !dirty ? 0.5 : 1,
						cursor: !writable || !dirty ? "default" : "pointer",
					}),
				}, "保存"),
				h("button", {
					key: "restore",
					type: "button",
					onClick: restore,
					disabled: !writable || (!dirty && !saved),
					style: Object.assign({}, buttonBase, {
						opacity: !writable || (!dirty && !saved) ? 0.5 : 1,
						cursor: !writable || (!dirty && !saved) ? "default" : "pointer",
					}),
				}, "还原默认"),
				h("span", {
					key: "status",
					style: { fontSize: "12.5px", color: statusColor },
				}, statusText),
				h("span", {
					key: "count",
					style: { fontSize: "12.5px", color: COLOR.secondary, marginLeft: "auto" },
				}, text.length + " 字"),
			]),
			unavailable
				? h("div", { key: "unavailable", style: { marginTop: "12px" } }, hint(
					"当前页面连不上宿主设置存储，这里的修改不会被持久化。",
					COLOR.error
				))
				: h("div", { key: "note", style: { marginTop: "16px" } }, hint(
					"保存后立即写入宿主设置（settings.yaml 的 global-prompt 段），无需重启；"
					+ "留空表示不注入任何内容。"
				)),
		]);
	}

	var name = "global-prompt";
	/** `slots` 是硬依赖；`settingsScope` 在设置基座存在时才绑定，缺失时本页不出现。 */
	var inject = ["slots"];

	/**
	 * 注册设置页。
	 * @param ctx - 客户端插件上下文。
	 */
	function apply(ctx) {
		ctx.inject(["settingsScope"], function (scoped) {
			var scope = scoped.settingsScope.bind({
				namespace: NAMESPACE,
				decode: decodePrompt,
			});
			ctx.slots.inject("settings.section", function () {
				return ctx.slots.register({
					name: "settings.section",
					id: "global-prompt",
					order: NAV_ORDER,
					label: "全局提示",
				}, function GlobalPromptPage() {
					return h(Guard, null, h(GlobalPromptSection, { scope: scope }));
				});
			});
		});
	}

	exports.name = name;
	exports.inject = inject;
	exports.apply = apply;
	return module.exports;
}
});
