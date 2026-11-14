# ollama-chat-ui

给本地 Ollama 模型用的**单文件网页聊天界面**，外加一个**视频抽帧**小工具。

不依赖任何框架、不用 npm、不用联网（除了你自己的 Ollama）。

```
ollama-chat.html   聊天界面（一个文件，18 个功能全在里面）
ollama-chat.ps1    Windows 一键启动器（起本地服务 + 开浏览器）
video-frames.ps1   把视频抽成九宫格图（给看图模型用）
```

## 为什么需要它

Ollama 自带的界面有两个在实际使用中很烦的问题：

1. **`qwen3.5` 这类「思考模型」默认开着思维链** —— 在这台没有独显的机器上，
   一句「你好」要等 **172 秒**。命令行加 `--think=false` 只要 **15 秒**。
2. **命令行（GBK 控制台）里中文输入法基本没法用** —— 候选框不出来、字符被吞。

于是做了这个网页版：浏览器输入框走系统 IME，请求里显式带 `"think": false`。

## 功能

| 功能 | 说明 |
|---|---|
| 多对话 | 左侧列表，localStorage 持久化，可单独删除 |
| 拖图 / 粘贴图 | 直接拖进窗口，或 `Ctrl+V` 粘贴截图，走模型的视觉能力 |
| 读秒 | `⏳ 等待模型… 3.2 秒` → `✍️ 生成中 8.5 秒 · 23 字 · 4.1 字/秒` |
| 完成后留统计 | `✅ 24.3 秒（生成 19.8 秒）· 96 tokens · 4.8 tok/s` |
| 复制按钮 | 每条消息一个，复制内容 |
| 翻译成英文 / 中文 | 输入框有内容就翻它，没有就翻上一条回答 |
| 总结这段 | 压成 3–5 条要点 |
| 导出 | 当前对话导出 Markdown，全部导出 JSON |
| 预设角色 | 跟随语言 / 中文 / 英文 / 严谨 / 简洁 / 翻译官 |
| 思考开关 | 默认关；复杂推理可临时打开 |
| 排队 | 单通道排队，界面上显示「前面还有 N 个」 |

## 怎么用

### 1. 装 Ollama 和模型

```powershell
winget install --id Ollama.Ollama -e
ollama pull qwen3.5:2b      # 约 2.7 GB；也可以换成你喜欢的
```

### 2. 启动

**双击 `ollama-chat.ps1`**，或者：

```powershell
powershell -ExecutionPolicy Bypass -File .\ollama-chat.ps1
```

会自动：

```
起一个只监听 127.0.0.1:8765 的静态服务
→ 打开浏览器 http://127.0.0.1:8765/ollama-chat.html
```

**换模型**：地址后面加参数，选择会被记住：

```
http://127.0.0.1:8765/ollama-chat.html?model=qwen2.5:3b
```

### 3. 视频抽帧

```powershell
winget install --id Gyan.FFmpeg -e

.\video-frames.ps1 -Path "D:\video.mp4"          # 抽 9 帧 → 3×3
.\video-frames.ps1 -Path video.mp4 -Count 16     # 抽 16 帧 → 4×4
```

输出 `<视频名>.frames.png`，同时打印时长 / 分辨率 / 帧率 / 码率 / 音轨。

## 几个设计决定

### 为什么必须起本地 HTTP 服务，而不是双击打开 HTML

浏览器从 `file://` 页面发请求时，`Origin` 头是 **`null`**，Ollama 会回 **403**：

```
Origin: null                → 403   （浏览器只能报一句含糊的 "Failed to fetch"）
Origin: http://127.0.0.1:8765 → 200
```

所以启动器起一个小服务，让页面来源变成白名单里的地址。

### 为什么要排队，而不是并发

`OLLAMA_NUM_PARALLEL=1` 时（CPU 推理基本都这样），两个请求同时发会互相踢。
所以聊天页做了单通道队列，第二个请求显示「🕒 排队中（前面还有 N 个）」。

### 为什么统计要存进消息对象

界面是「状态 → 渲染」的投影。如果统计只存在 DOM 里，重绘（切对话、完成时刷新）
就会丢。同理，**正在流式输出的内容也按对话存一份状态**，切换对话后重新挂回界面。

## 踩过的坑（都是真踩的）

| 症状 | 根因 |
|---|---|
| 按钮点了没反应 | 声明了 `const btn = ...` 但忘了 `btn.onclick` |
| 快速连点「新建」建不出对话 | `Date.now()` 当 ID，同一毫秒撞车 → 改 `crypto.randomUUID()` |
| 生成中切换对话，AI 气泡消失 | 流式写入的是「已被重绘替换掉的节点」 |
| 两个对话互相中断 | Ollama 单通道 + 前端并发 |
| 完成后统计消失 | 重绘只还原了 content，没还原 meta |
| `Failed to fetch` | `file://` 的 Origin 是 `null`，被 403 |

**共同点：状态没有单一来源，一半在 DOM 一半在内存，重绘就丢。**

## 限制

- **只在这台机器上验证过**（Windows 10 + PowerShell 5.1 + Edge），没有做跨平台适配
- `ollama-chat.ps1` 依赖 PowerShell；Linux/macOS 用 `python -m http.server` 起服务即可
- 抽帧只能看「静态瞬间」，看不出动作连贯性和节奏
- **小模型看图会编造**：能描述画面，但认角色/认人名几乎必错（还会编罗马音）

## License

MIT
