# Windows / DSH Desktop 下做 PPT 的环境事实

本文件记录在 **Windows + DSH Desktop** 上处理 pptx 时踩过的环境坑与已验证的可用路线，
与具体技能无关——`pptx-toolkit`、`html-to-pptx` 和 DSH 内置的 PPTD 路线都用得上。

> 本文件的环境事实来自安装者（DSH 会话）在实际使用中的踩坑与验证记录。

## 1. 中文 Windows 的 GBK 控制台：Python 要开 UTF-8 模式

本机区域设置是 GBK。用默认编码读 OOXML 或打印非 GBK 字符（`→`、emoji、生僻字）会报
`'gbk' codec can't decode byte ...`——**这不是 deck 的问题**。

```powershell
$env:PYTHONUTF8 = "1"        # 或 python -X utf8 <script>
```

`pptx-toolkit` 的脚本已在启动时自行把 stdout/stderr 切成 UTF-8，不需要这步；
但调用**其它** Python 脚本时仍建议设置。

已验证：加上 `PYTHONUTF8=1` 后，同一份 deck 的输出从报错变为正常。

## 2. `require('pptxgenjs')` 的解析路径

`pptxgenjs`（MIT）随 DSH Desktop 一起安装，但不在当前工作目录下，直接 `require` 会失败。
写生成脚本后用 `NODE_PATH` 指过去即可，**不要** `npm install`：

```powershell
$env:NODE_PATH = "$env:LOCALAPPDATA\Programs\DSH Desktop\resources\app\node_modules"
node deck.js            # require('pptxgenjs') 可用；sharp 同目录也在
```

## 3. 内容 QA：没有 markitdown 时的替代

`markitdown[pptx]` 会连带 `onnxruntime` + `magika` 约 200 MB，本机没装。
用 `pptx-toolkit` 的 `dump_text.py` 代替，输出保持同样的 `<!-- Slide number: N -->` 分页格式
（该格式源自 MIT 许可的 microsoft/markitdown），便于直接 grep：

```powershell
py <skill_dir>\scripts\dump_text.py deck.pptx > deck.txt
Select-String -Path deck.txt -Pattern 'xxxx|lorem|ipsum|TODO|\[insert'
```

## 4. 视觉 QA：没有 LibreOffice / pdftoppm 时的两条路线

`soffice --convert-to pdf` 在本机不可用（未安装 LibreOffice，也没有 Poppler/pdftoppm）。

**路线 A（推荐，最接近用户实际打开的效果）**：用 PowerPoint / WPS 的 COM 导出 PNG。
WPS Office 会注册 `PowerPoint.Application`，因此即使没装 Microsoft Office 也能用。

```powershell
py <skill_dir>\scripts\render.py deck.pptx -o preview\ --via com
```

需要 `pywin32`（`py -m pip install pywin32`）。本机已验证可用。

**路线 B（无需 Office，纯 DSH 内置渲染器）**：先把 pptx 转成 PPTD 工程再渲染成 PNG。
`pptd_import` 是 agent 工具而非命令行，需在会话里调用；随后：

```powershell
node "$env:LOCALAPPDATA\Programs\DSH Desktop\resources\app\node_modules\dsh-ppt\lib\bin.js" `
     screenshot <pptd目录> -o <预览目录> --json
# → <预览目录>\pages\page-N.png
```

路线 B 忠实反映文字/图表/表格，适合自己审阅排版；对渐变、阴影等复杂装饰会有标准化提示。

## 5. DSH 自带的 PPTD 制作路线（模板化出稿）

DSH 内置了与模板配合的 PPTD 路线：`pptd_*` 工具 + 16 套模板（`dsh-ppt`，随 DSH Desktop
安装，MIT），`pptd_check` / `pptd_render` 直接产出**可编辑** PPTX。

分工建议：

- **HTML 已有成品 → 要 pptx**：用 `html-to-pptx`（保留矢量文字 + 装饰截图兜底）。
- **从零按模板出稿**：用 PPTD 路线。
- **已有 pptx，要读 / 检 / 改 / 预览**：用 `pptx-toolkit`。

三条路线产出的都是可在 PowerPoint / WPS 中继续编辑的原生元素。

## 6. `python` 命令的坑

本机 `python` 可能指向 Microsoft Store 的占位程序（执行后无输出）。
用 `py` 启动器更可靠：

```powershell
py -m pip install -r <skill_dir>\requirements.txt
py <skill_dir>\tests\smoke_test.py
```

另外：`pip install pptx` 装的是**另一个无关包**，正确的名字是 `python-pptx`。
