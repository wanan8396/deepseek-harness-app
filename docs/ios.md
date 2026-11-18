# iPhone 与 iPad 本机引擎适配

[English](ios.en.md)

此分支面向 iOS 手机和平板，不是 macOS 桌面程序。`main` 保持 Android 产品；开发位于 `feat/ios-local-engine`。

## 当前阶段

iPhone／iPad 可从本机能力页进入 **本机聊天**，输入 DeepSeek API Key 并启动一个纯文本会话。DSH AgentLoop 与 SQLite 在 App 进程内运行；模型推理由官方 DeepSeek HTTPS API 完成，不是在手机上跑模型权重，也不需要电脑、远程 DSH 或 `127.0.0.1` 桥接。

- Xcode Runner 同时面向 iPhone、iPad，最低 iOS 16。
- Node 在 App 自己的线程内通过 `node_start()` 运行，不解包 Ubuntu，不执行 Linux 二进制，不使用 Root、PRoot 或外部电脑。
- iOS 首屏进入本机能力检查，不恢复电脑地址，不调用 Android 运行时安装流程。
- 启动后检测私有目录读写、ICU/Intl、内置模块加载、SQLite/FTS5、ESM 元信息；显示实际版本和结果。
- 将官方锁中的 Loader 纯 JS 闭包与独立测试插件打包；验证真实服务激活、私有文件 challenge、dispose 和错误启动拦截，结果独立于 Node 能力记录。这个最小树没有挂载 Agent、模型或对话界面。
- 独立内核树挂载官方 Session、投影、Prompt、Tools、LLM、Agent 与 AgentLoop；仅外部模型端点由明确标识的离线夹具替代。检查真实流式 delta、第二轮历史、取消、模型错误后的恢复、清理与缺失服务坏基线；不发真实模型请求，不挂载持久化，不作为用户聊天入口。
- 另一棵树挂载 App 自有、兼容官方 SessionPersistence 的 SQLite 后端及官方会话检查点策略，验证真实会话落盘、同一会话写入排他、独立读取、坏批原子拒绝、损坏日志拒绝，以及关闭后重建 DSH 并恢复历史。验证使用临时数据库和离线测试模型，不等于杀进程恢复已通过。
- 检测页和聊天状态分开。诊断报告的 `engineReady: false` 不用于判断聊天是否可用；聊天独立报告启动、流式、取消和错误。
- Swift 与 Node 通过 App 私有目录中的限长、原子文件信箱传递请求，不开放端口。API Key 随启动请求短暂写入权限 `0600`、排除备份的信箱文件，消费即删除；不存入历史数据库或偏好设置，停止后释放运行时引用。
- 历史在 App 私有 SQLite 保存；停止再启动可恢复同一个会话。当前界面只显示最近的消息，历史可用于后续模型请求。
- iOS 切后台后受系统挂起约束；目前不声明持续后台执行。

## 运行时来源

官方引擎锁中的 `@deepseek-ai/dsh@0.2.2-rc.3` 要求 Node `>=24.9.0`。Node.js Mobile 主项目现成的 18.20.4 版本不足以满足要求。本分支固定采用 [fogtape 的 Node.js Mobile 24.22.1 完整框架](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)，包含 iOS device arm64 与 Simulator arm64 两个切片。

固定 URL、包大小、SHA-256、源码/recipe commit 记录在 [requirements.json](../runtime/ios/requirements.json)。下载脚本先验哈希，再检查解压路径、框架切片与入口 API。二进制放入被忽略的 Vendor 目录，不进入 Git；JS 探针只访问自己收到的私有报告路径。

该框架是第三方移植，不是 Apple 或 Node.js 官方 iOS 发行版；固定版本和通过探针都不等于已验证 DSH 所有模块。Node/框架及其第三方完整许可证固定为 [NodeMobile-LICENSE.txt](../runtime/ios/NodeMobile-LICENSE.txt)，随 App 一起打包；来源为其 [LICENSE](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE)。

## 直接在 GitHub 构建

[iOS Actions](../.github/workflows/ios.yml) 在独立分支推送后运行，也支持手动触发：

1. 校验依赖锁与运行时哈希。
2. 在 GitHub 上生成中英文文案，执行 Python/Node/Flutter 回归。
3. Ubuntu 先验证 Loader、AgentLoop、SQLite 持久化和本机聊天；将同一次运行的四个受审资源包交给 Xcode。XCTest 在 iOS 模拟器的 App 进程内执行 Swift 信箱、真实 DSH 和官方模型适配器；只替换出站 HTTP 响应为测试 SSE，不向 DeepSeek 发送请求。独立验证流式输出、取消、停止重开后的历史和认证错误。
4. 构建未签名的 iPhone/iPad Release App；检查 Mach-O 平台、设备类型、框架和探针资源。
5. 保存构建核验、XCTest 结果与未签名设备 App。

macOS runner 仅是 Xcode 构建环境，产物目标仍为 iOS。未签名 App 不是可直接安装的 IPA；真机安装还需 Apple 开发签名和对应设备配置。模拟器成功也不代表 iPhone 真机已验收。

## 支持范围

- 当前是单会话纯文本聊天，不是桌面版 DSH profile。没有终端、Shell、工作区工具、审批、附件及第三方插件。
- 聊天与存储在模拟器内验证；未用真机真实 API Key 验证付费接口，也未验证强制结束 App 后的恢复或持续后台运行。
- 完整 profile 的 `node-addon-require-builtin` 与内部 ESM/CJS 入口仍需单独适配。最小相对路径 Loader 不挂载该路径，也没有替代 shim；Mac arm64 原生扩展不等于 iOS arm64 原生扩展。

本分支没有更改 Android 官方运行时、签名、原主题或启动 GIF。
