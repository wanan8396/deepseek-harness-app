# iOS 功能验收矩阵

适用于 `feat/ios-local-engine`，不是 Android 或桌面版的功能承诺。

| 能力 | 首个绿色开发包 `46f70b0` | 验收证据或缺口 |
| --- | --- | --- |
| 本机 DSH、无本地 TCP | 已验证 | iPhone 16 Pro / iOS 18.5 的 App 进程内，WebKit 经 Swift 私有文件信箱调用官方 Node Host。 |
| 官方聊天、侧栏、模型选择、审批组件 | 28 个锁定模块已打包 | 官方侧栏切换两条真实 SQLite 会话和标题更新已在模拟器验证。模型目录、真实工具和一次性审批已分层验证。正式页面输入框到审批按钮的同链复测见下方。 |
| DeepSeek / OpenAI Chat 自定义 HTTPS | 已接入两种文本协议 | API Key 通过原生界面输入。CI 使用合成 SSE；真实模型服务的认证、费用和兼容差异未实测。 |
| 本机工具 | 已验证 | App 私有 Workspace 内列目录、读文本、审批后独占创建；无对其他 App 的文件访问。 |
| 官方附件 | 尚未交付 | 需要接通官方文件选择、同会话暂存凭据和 SQLite 历史引用；图片处理和预览是独立项目。 |
| 插件 | 固定首方模块随包发布 | 不包含第三方插件安装、动态发现或插件市场。纯 JS 不自动代表兼容：需同时符合 iOS 宿主 API、导出依赖和用户授权模式。 |
| Android Root / PRoot / Linux、桌面终端 / PTY | 不等价 | iOS 不移植 Ubuntu、独立系统进程、Shell、桌面原生扩展、主机任意目录或持续后台运行。 |
| 真机安装 | 未签名设备 IPA | 目标为 iPhone/iPad；需要 Apple 签名与描述文件。模拟器绿灯不代表物理 iPhone 或 iPad 通过。 |

## 证据索引

- [GitHub Actions `46f70b0`](https://github.com/wanan8396/deepseek-harness-app/actions/runs/44298142976)，归档 `ios-build-and-probe`。其中 `build-info.txt` 记录模拟器和 Widget 门槛；`official-web-embedded-session-rpc` 记录官方侧栏和无 TCP。`embedded-ios-chat-verification` 记录真实本机工具、应用级取消与模拟 HTTPS。此归档不是生产 WebKit 审批卡端到端证据。
- [GitHub Actions `cd2ae39`](https://github.com/wanan8396/deepseek-harness-app/actions/runs/44358820375) 用 Flutter 将调用的生产原生通道直接验收模型目录、会话流、同一官方 Peer 的审批回复、真实工具写入和关闭后旧代次失效；模拟器结果以 `ios-official-flutter-carrier` 证据为准。这不是 Flutter 界面本身的验收。前一轮 WebKit 审批卡 UI 测试未通过，当前计划改为原 Android 的 Flutter 界面。

## 文本附件接入门槛

先交付可验证的 UTF-8 文本附件，而非把本地路径硬塞进提示词：

1. 复用官方文件选择器、草稿区和 `dsh-client-file-upload`。iOS 给官方上传钩子提供限长传输，仅接收明确支持的文本及名称，按照当前会话归属检查。禁止借以访问任意文件、其他会话、二进制或图片。
2. 由官方存储生成附属文件摘要和短期凭据，凭据只有该会话可消费，持久化事件记内容引用而非文件正文、下载地址或原文件路径。取消、错误和重启必须显式验证。
3. 使用官方私有内容仓库校验大小和 SHA-256 后，将文本内容交给当前配置的模型，或者通过约束到当前会话附件的只读工具读取。保留默认文件句柄语义；不授权整个附件目录或文件系统。
4. 云端验收需覆盖文件选择、取消及重选、错误格式、超长、错误会话、重启历史、模型读取，以及实际 iOS WebKit 中上传后显示的附件。图片、其它二进制和插件安装另立门槛。
