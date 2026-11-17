# iPhone 与 iPad 本机引擎适配

[English](ios.en.md)

此分支面向 iOS 手机和平板，不是 macOS 桌面程序。`main` 保持 Android 产品；开发位于 `feat/ios-local-engine`。

## 当前阶段

当前实现 iOS 工程、嵌入式 Node 框架、真实 JavaScript 能力探针及官方 DSH Loader 的最小加载验证。**探针通过不等于 DSH 引擎已启动；当前尚未提供完整的 iOS 本机 DSH 对话功能。**

- Xcode Runner 同时面向 iPhone、iPad，最低 iOS 16。
- Node 在 App 自己的线程内通过 `node_start()` 运行，不解包 Ubuntu，不执行 Linux 二进制，不使用 Root、PRoot 或外部电脑。
- iOS 首屏进入本机能力检查，不恢复电脑地址，不调用 Android 运行时安装流程。
- 启动后检测私有目录读写、ICU/Intl、内置模块加载、SQLite/FTS5、ESM 元信息；显示实际版本和结果。
- 将官方锁中的 Loader 纯 JS 闭包与独立测试插件打包；验证真实服务激活、私有文件 challenge、dispose 和错误启动拦截，结果独立于 Node 能力记录。这个最小树没有挂载 Agent、模型或对话界面。
- `engineReady` 仍为 false；缺失框架、超时或错误返回明确失败状态，不伪造运行网址或登录令牌。
- iOS 切后台后受系统挂起约束；目前不声明持续后台执行。

## 运行时来源

官方引擎锁中的 `@deepseek-ai/dsh@0.2.2-rc.3` 要求 Node `>=24.9.0`。Node.js Mobile 主项目现成的 18.20.4 版本不足以满足要求。本分支固定采用 [fogtape 的 Node.js Mobile 24.22.1 完整框架](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)，包含 iOS device arm64 与 Simulator arm64 两个切片。

固定 URL、包大小、SHA-256、源码/recipe commit 记录在 [requirements.json](../runtime/ios/requirements.json)。下载脚本先验哈希，再检查解压路径、框架切片与入口 API。二进制放入被忽略的 Vendor 目录，不进入 Git；JS 探针只访问自己收到的私有报告路径。

该框架是第三方移植，不是 Apple 或 Node.js 官方 iOS 发行版；固定版本和通过探针都不等于已验证 DSH 所有模块。Node/框架及其第三方完整许可证固定为 [NodeMobile-LICENSE.txt](../runtime/ios/NodeMobile-LICENSE.txt)，随 App 一起打包；来源为其 [LICENSE](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE)。

## 直接在 GitHub 构建

[iOS Actions](../.github/workflows/ios.yml) 在独立分支推送后运行，也支持手动触发：

1. 校验依赖锁与运行时哈希。
2. 在 GitHub 上生成中英文文案，执行 Python/Node/Flutter 回归。
3. Ubuntu 先执行官方 Loader 与错误基线，传递同一次运行的受审资源包给 Xcode；在 iOS Simulator App 进程内执行 Node 与 Loader 的独立 XCTest 断言。
4. 构建未签名的 iPhone/iPad Release App；检查 Mach-O 平台、设备类型、框架和探针资源。
5. 保存构建核验、XCTest 结果与未签名设备 App。

macOS runner 仅是 Xcode 构建环境，产物目标仍为 iOS。未签名 App 不是可直接安装的 IPA；真机安装还需 Apple 开发签名和对应设备配置。模拟器成功也不代表 iPhone 真机已验收。

## 后续完整引擎门禁

目前不把探针当作聊天产品交付，下一阶段还要逐项验证：

- 完整 profile resolution 使用的 `node-addon-require-builtin` 与内部 ESM/CJS 入口仍需单独适配；最小相对模块 Loader 检查没有挂载该路径，也没有以假 shim 替代它。Mac arm64 原生模块不是 iOS arm64 模块。
- 将会话和工作区映射到 App 沙箱目录；迁移或替换文件系统、图像和原生扩展依赖。
- 替代或禁用依赖子进程、终端、系统 Shell、动态工具安装的插件，明确真实功能范围。
- DSH profile 实际启动、认证握手、网页/API、会话流式消息、审批、持久化及前后台生命周期分别验收。
- 如果后续采用无 TCP 的进程内通道，需要另行适配完整 HTTP/流式传输语义；目前未声称实现了它。

本分支没有更改 Android 官方运行时、签名、原主题或启动 GIF。
