# 开发与验证

[English](CONTRIBUTING.en.md) · [项目首页](README.md) · [实际功能](PROJECT.md) · [架构](docs/architecture.md)

## 当前开发对象

安装、复用或清理工具与依赖前先读[依赖与工具目录规范](DEPENDENCIES.md)；执行者和子代理沿用其中路径分类，先复用已有工具，不在桌面DSH或用户数据目录散放新依赖。

当前产品是 Android 手机壳：Flutter 负责启动、连接与权限，官方 `@deepseek-ai/dsh@0.2.2-rc.3` 网页负责对话和设置。本机每次启动自动检测真实 UID 0，条件满足优先 Root，否则回退 PRoot；没有用户可选的 Root 开关。

本机网页连接使用 [`dsh_client`](packages/dsh_client/README.md) 提供的轻量 HTTP/RPC/mux 与只读会话、工作区读取。先看 [PROJECT.md](PROJECT.md) 与[架构](docs/architecture.md)，再按实际调用路径确定改动范围。

## 开发环境与构建

- Flutter 版本参考[现有 CI 配置](.github/workflows/ci.yml)（当前为 `3.47.7`），Dart 要满足 [App SDK 约束](app/pubspec.yaml) `^3.13.5`。
- Android 使用 JDK 17、Android SDK/NDK；运行时 ABI 必须与 APK flavor 匹配。
- 构建工具需要 Python 3 与 Pillow；网页检查需要 Node.js，现有 CI 使用 `24.22.1`。
- 按[官方运行时说明](runtime/README.official.md)准备独立、可核验的载荷，勿以手机已安装环境代替构建种子。

从仓库根目录构建 Android 应用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

Linux：

```bash
python3 tooling/make_local_web_brand.py
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
bash tooling/build-local-web-apk.sh -f arm64
```

这些入口构建同一个 Android 手机壳，并检查所用运行时为官方未修改分发。显示版本取运行时 `dshVersion`，构建号独立递增。正式签名配置、私钥留在本机；更新安装须保持包名和签名一致。不要把 debug 包覆盖现有正式包当作默认开发流程。完整参数和签名要求见[构建说明](docs/local-web.md#构建)。

## 修改约定

- 一个改动解决一个可独立核验的问题，说明旧行为、触发条件和新行为，避免无关重命名、格式化或依赖升级。
- 保留现有网页主题与原始启动动画；布局问题只改相关定位、尺寸或输入行为。
- 界面文案按[中英文 ARB 输入](app/lib/l10n/parts/)同步维护；双语文档一起更新。生成文件从源输入重新生成。
- 改运行时、平台通道或仍有调用方的协议时，同时核对生产者、消费者、失败路径和兼容性。退休代码先证明引用与副作用，再删除。
- 不提交密钥、登录态、真实对话、设备标识、私有运维资料或构建缓存。诊断包、截图与日志外发前人工检查。
- 新增或移植第三方内容时，记录来源、版本或提交、源文件和许可证，保留必要的署名、许可及修改说明；既有许可不随目录移动而改变。

## 常用检查

以下命令从仓库根目录运行，按改动面选择。记录实际命令、结果、跳过项和未验证范围；静态检查、桌面回归、APK 检查与真机验收分别记账。

**仅文档：** 核对双语内容、链接、源码出处，并运行：

```bash
git diff --check
```

**Flutter 与 Android 壳回归：** 安装测试所需的真实字体，将 `DSH_TEST_FONT_DIR` 指向 Noto CJK Light/Regular/Bold TTC 所在目录；字体配置见[现有 CI](.github/workflows/ci.yml)。

```bash
(cd app && flutter pub get --enforce-lockfile && flutter analyze --no-pub)
(cd app && flutter test --no-pub test/local_web_lite)
```

**运行时构建器、网络与 APK 校验器的桌面回归：**

```bash
python3 tooling/test_local_web_runtime.py -v
python3 tooling/test_local_web_network.py -v
python3 tooling/test_verify_local_web_release.py -v
python3 -m unittest discover -s runtime/tests -p test_official_runtime.py
python3 -m unittest discover -s runtime/tests -p test_runtime_artifacts.py
```

**Android 原生单测：** 准备好 Flutter/Android 工具链与本机配置后，使用与[现有 CI](.github/workflows/ci.yml)一致的 Gradle 任务：

```bash
(cd app/android && gradle --stacktrace :app:testArm64DebugUnitTest)
```

**实际载荷与正式 APK：** 需要真实运行时资产；APK 检查还需要 Android SDK build-tools `35.0.0` 及 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。

```bash
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
python3 tooling/verify_local_web_release.py dist/deepseek-harness-local-0.2.2-rc.3-release.apk --output dist/release-verification.json
```

网页布局可按改动选择[页头](tooling/test_web_header_layout.mjs)、[弹窗](tooling/test_web_dialog_layout.mjs)或[设置菜单](tooling/test_web_settings_menu_layout.mjs)回归。先按脚本准备其官方 rc.2 展开目录、浏览器和独立端口；这些是本地合成 DOM/输入检查，不替代手机 WebView 验收，也不验证真实账号设置的持久化。

**文案与内置用户指南：** 修改源输入后生成，再只读检查：

```bash
python3 app/tool/l10n_merge.py
python3 app/tool/l10n_merge.py --check
python3 app/tool/guide_sync.py
python3 app/tool/guide_sync.py --check
```

## 保留的轻量客户端模块

Android 壳的本机网页连接使用 [`dsh_client`](packages/dsh_client/README.md)。修改该包时按包内说明运行静态分析与夹具检查；该包没有仓库锁文件，不使用 `pub get --enforce-lockfile`。内置用户指南的同步检查见上一节。

## 真机验收与交付记录

涉及本机启动、Root/PRoot、权限、WebView、更新安装的改动，记录 ABI、Android 版本、设备、包版本与实际启动路径。分别检查首次连接、安装/升级、进入本机自动启动、电脑地址/扫码/PIN 登录、连接记录、菜单/键盘/设置、返回与真正退出、Root 与 PRoot 路径。使用匹配签名的测试包，保留现有数据；桌面或 CI 通过不等于手机验证完成。

交付时给出问题与改动范围、源码出处、实际检查结果及剩余事项，界面证据按验证需要提供。未复验的故障（包括“新会话入口未进入新会话”）保持未验证状态。CI 检查不替代 Android 手机壳的真机验收；两者分别记录。

问题反馈附最小复现步骤、App/Android 版本、连接方式和已脱敏证据；私密问题按 [SECURITY.md](SECURITY.md) 报告。配套服务的生产部署、真实账号与线上检查不属于普通本地验证。
