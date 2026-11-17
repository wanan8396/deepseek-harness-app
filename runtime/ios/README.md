# iOS 嵌入式 Node 输入与验收阶段

这是 iPhone/iPad **进程内真实 Node 引擎**的第一阶段输入，不是 Mac 可执行文件，也不是远程引擎客户端。`probeReady` 只表示 Node 探针完成；`runtimeCompatible` 只表示当前探针的版本/API 条件满足，**不表示 DSH 已启动**。探针始终输出 `engineReady: false`。

[English](README.en.md)

## 固定来源

- 提供者：第三方 `fogtape/nodejs-mobile`，不是 Node.js 官方 iOS 分发，也不是 `nodejs-mobile/nodejs-mobile` 的正式新版。
- 完整 full 版：[`v24.22.1-0`](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)，Node `24.22.1`；不选缺 SQLite/SEA 的 lite 版。
- [归档](https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-ios-24.22.1-0.zip)：62,732,962 字节；SHA256 `3fa1b8fb0720768b01c2e0dae3a17e788476e8c1613a1d9a54e206793b45326e`。
- [固定源码](https://github.com/fogtape/nodejs-mobile/tree/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5)；[配方提交](https://github.com/fogtape/nodejs-mobile/commit/d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5)；[MIT 与依赖许可](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE)。归档未携完整 LICENSE；对应完整许可已固定为 [NodeMobile-LICENSE.txt](NodeMobile-LICENSE.txt)，准备器复制到 App 资源中，不以链接代替发行许可。
- 实物 `NodeMobile.xcframework` 是动态 framework：`ios-arm64` 和 `ios-arm64-simulator`，均最低 iOS 14.0；无 Intel/x86_64 模拟器 slice。
- [公开头文件](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/tools/ios-framework/NodeMobile/NodeMobile.h) 仅 `int node_start(int argc, char *argv[])`；[构建配方](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/tools/ios_framework_prepare.sh) 使用 jitless V8、full ICU，保留 SQLite，并捆绑 polywasm 供 undici/fetch 使用。源码配方声明不是本项目真机验证。

## 准备与 CI

不安装工具链。所有构建和测试由 GitHub Actions 执行；本阶段本地只核验公开归档哈希、头文件与 Mach-O 元数据。

```sh
python3 tooling/prepare_ios_runtime.py --check
python3 tooling/test_prepare_ios_runtime.py
node --test runtime/ios/probe.test.cjs
python3 tooling/prepare_ios_runtime.py --download
# 已有归档可用：--download --archive /path/to/nodejs-mobile-ios-24.22.1-0.zip
```

`--check` 只读核对 `requirements.json` 与官方 rc.3 锁中的 `engines.node`。`--download` 固定 URL/字节数/哈希，将真实唯一 framework 根安装到 `app/ios/EmbeddedNode/Vendor/NodeMobile.xcframework`，并将探针、ESM 探针和 requirements 复制到 `app/ios/EmbeddedNode/Resources`。默认下载缓存位于 `runtime/.cache/ios`。缓存、Vendor 与生成 Resources 均不应进入 Git。

准备器在任何解压前检查全部 zip 成员，拦截路径穿越、绝对/Windows 路径、重复路径、符号链接、特殊文件和超额展开；再核对 framework slices、C API 与 arm64 MH_DYLIB。已有 Vendor 内容必须与重新校验的归档逐字节一致，否则报错而不是静默覆盖。

## Native runner 契约

后台专用线程调用一次 `node_start`，传入 `node`、真实 bundle 中 `probe.cjs` 的绝对路径，以及 **App 私有目录内且父目录已创建** 的报告绝对路径。`char **argv` 的内存须保持至调用结束；该调用会占据线程。运行时一进程一实例，不实现“停止后同进程再次启动”的假契约。

探针写入同目录随机临时文件（0600）后 rename 发布完整 JSON。它不输出环境、用户配置、令牌或原始异常；错误仅 machine code。timer 保持事件循环，不调用 `process.exit`。Native 以 JSON 的 `phase` 和 `schemaVersion` 判断探针完成；错误和超时保持错误状态，勿据 framework 文件存在、Node 版本或生成的测试报告标 DSH ready。

实际检查：Node/V8/ABI/N-API/platform/arch、版本约束、私有目录写读、`process.getBuiltinModule`、`node:sqlite` 内存读写及 FTS5、Intl、真实本地 ESM `import.meta.main/filename/dirname`。jitless 的 argv 请求、配方预期与未独立证明的运行时状态分开记录。

## 官方 Loader 的独立检查

`prepare_ios_loader.py` 从 Actions 用官方 rc.3 锁重新解析的独立 npm seed 导出受审纯 JS 闭包，拒绝未知依赖扩展和 npm 原生二进制，记录来源、遗漏原因、许可和逐文件哈希。供应包保持原字节；自有测试插件分开标记为 `ios-adapted-loader-probe`。

Ubuntu 先执行 [test-loader.mjs](test-loader.mjs)；通过后将同一次运行的归档传给 iOS job，放入 `DshEmbeddedNode.framework/dsh-loader`。嵌入探针随后运行同一 `runLoaderProbe()`，XCTest 独立要求激活、服务、清理、坏基线四项为真。`runtimeCompatible` 仍只描述 Node API，Loader 结果放在独立 `loader` 字段；两层 `engineReady` 都保持 false。安装产物校验逐一比对 Loader 文件哈希和官方锁哈希。

## DSH 启动门禁仍待闭环

1. 当前官方 DSH rc.3 锁要求 `>=24.9.0`。Node24.22.1 满足版本门槛，不等于整图兼容。
2. `dsh-app-boot` 的 profile resolution 直接依赖 `node-addon-require-builtin` 和五个内部 loader 模块；Linux ARM64/glibc 或 Mac darwin-arm64 addon 不等于 iOS addon。
3. CLI 与 `runProfile` 内含宿主进程退出路径；直接调用会影响整个 App。当前以 `dsh-app-boot.boot(...)` 和相对模块 tiny tree 验证真实 Loader 的激活、challenge、dispose 与必需 row 失败拦截；仍未实现用户 profile 的完整受控生命周期。
4. 全 web profile、HTTP/RPC、真实会话持久化、模型请求、原生工具、后台/锁屏/内存压力/真机都各自记录证据。没有“复用百分比”或“几个原生模块足够”的结论。
