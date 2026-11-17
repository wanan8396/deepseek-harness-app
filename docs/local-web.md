# DeepSeek Harness · 手机 App

[English](local-web.en.md)

- **包名：** `app.dsh`
- **应用名：** DeepSeek harness
- **显示版本：** 来自实际内置运行时清单中的 `dshVersion`，例如 `0.2.2-rc.3`；Android 构建编号继续递增。
- **维护仓库：** [wanan8396/deepseek-harness-source](https://github.com/wanan8396/deepseek-harness-source)（私有）。来源与原作者见[署名和许可](ATTRIBUTION.md)。

> 本页介绍当前版本的界面与本机启动方式。当前源码每次本机启动自动检测真实 UID 0，条件满足优先 Root，否则回退 PRoot；没有手动 Root 选择。安装包功能范围以该 Release 说明和附件为准。

## 两种连接方式

### 本机

在手机运行内置 Ubuntu、Node.js 和 DSH，启动时自动检测 Root，取得真实 UID 0 且条件满足时使用 Root，否则回退 PRoot，直接显示该引擎的原网页。进入本机模式自动启动，真正退出 App（根页面返回或从最近任务划掉）停止本机引擎；普通切后台、锁屏和旋转不当作退出。模型配置、对话和普通工具权限使用网页原有控件，不在原生设置重复实现。

本机执行不等于离线模型推理，模型请求仍由网页配置的提供商处理。初次使用本机需要安装 APK 中的真实运行时。

### 电脑网页

首次进入或设置中选择“连接电脑或服务器”，手动输入 HTTP(S) 地址，或点击扫码读取电脑局域网插件的二维码。扫码先显示主机地址并确认，再打开网页。

已核实当前电脑插件 `@neil-yu/dsh-remote-access@0.1.3` 的二维码是**纯 HTTP URL**。其 PIN 留在插件网页的登录页输入，由网页 Cookie 管理；App 不收集或展示 PIN。

连接记录保存主机、名称和最后使用时间。普通偏好中的地址去掉 query/fragment；含登录参数的完整 URL 使用 App 密钥存储，不写进列表或日志。电脑模式不读取、覆盖或复用手机本机会话标识。返回本机时恢复本机页面，电脑网页自身保留其会话状态。

## 界面

- 左下角只保留一个鲸鱼按钮，点击直接展开网页的“对话与工作区”；删除独立菜单和原生 App 设置入口。预留 48dp 底栏，键盘或网页弹窗出现时收起，不挡输入与发送。
- 底部右侧仅保留“本机 / 电脑”连接入口，进入后只有本机、电脑两项；电脑页保留手动地址、扫码、连接记录。主题、语言、模型等设置全部使用网页原有控件。
- 网页手机适配默认开启，无重复开关。会话顶部的层级、子智能体/后台任务状态、工具与右侧栏按钮保持一排，可横向触控滑动；工具外框与40dp触控区对齐，不再剪裁。顶部下拉菜单在视口中独立定位，不受横向滚动行裁切；浏览器等右侧面板标签及关闭 × 使用40px同轴布局，标题不覆盖关闭区域。
- 正常启动与网页初载显示原始40帧GIF和“探索未至之境”，不显示加载文字或进度条；首次权限引导保留原主题与清晰字标；首次权限集中在一页，每项显示真实状态和“去开启”按钮，底部保留“继续”。未开启时也可继续，回到 App 只刷新状态，不自动弹出下一项。
- 原生连接页沿用内置网页设置的实际背景、文字、边框、选中项与主按钮颜色；网页选择深浅色时，连接页和底部鲸鱼随当前网页外观同步，无重复主题设置。
- 网页设置使用系统安全区，不重复预留原生菜单与底部鲸鱼空间。显示网页弹窗时原生悬浮控件暂时隐藏，关闭后恢复；长欢迎说明独立滚动，勾选与确认区域保持可见。
- 电脑网页模式不构造本机初始化页，也不读取本机运行时 Provider；用户选择的 HTTP 局域网 URL 在当前壳网络配置中放行，HTTPS 证书校验保持平台默认。
- 初次权限引导包括所需文件/通知/后台能力，可以跳过；Root 由每次本机启动自动检测，权限页没有 Root 开关，见下节。相机在主动扫码时申请。权限未授予时由实际操作提示，不在设置堆放开关。文件、通知与系统电池豁免显示真实读取结果；厂商“允许后台行为”等无读取接口的项目提供“查看设置”和“我已开启”，手动确认显示“已确认开启”，与系统检测结果区分。仅打开设置或返回不自动视为已授权。
- 本机引擎采用官方 `@deepseek-ai/dsh@0.2.2-rc.3`，网页、插件与会话接口使用官方实现。

当前仓库只有这一种 Android 手机壳产品，构建时不需要产品模式切换标记。

## Root 默认启动与 PRoot 回退

> Root/PRoot 由每次本机启动时的自动检测决定，不是用户可选开关。具体安装包的功能以该 Release 说明为准。

权限页只保留文件、通知与后台项目，**没有 Root 手动控件**。

- 每次本机引擎启动自动检测一次真实 Android Root，UID 0 与平台条件均核对成功后使用 Root；未授予、超时或设备不支持时回退 PRoot。
- Root 管理器可在首次检测时提示授权。打开权限页、返回 App 或读取状态不会重复发起探测；不依赖旧版本保存的 Root 开关值。
- Root 模式以真实 Root 在私有挂载命名空间/chroot 中启动 Ubuntu/Node/DSH，不使用 PRoot，也不要求 PID 命名空间。普通命令工具直接运行，不需要额外手动桥命令。
- Root 内保留 Ubuntu 路径和软件；Android 挂载路径下的脚本可直接通过 `/system/bin/sh /实际路径/script.sh` 执行。脚本解释器与库仍需与所选 Android/Ubuntu 环境匹配。
- 授权后可访问、修改系统文件。此功能不修改原网页工具审批，不恢复无障碍或手机操控 MCP。
- 运行期间不热切换 Root/PRoot，下次本机启动重新检测。Home、锁屏和旋转不停止引擎；真正退出回收本次 Root 命名空间及进程。
- Root 结束后只修复 App 私有物理 rootfs 内不属于 App UID 的文件和目录所有权，保留文件模式，不遍历外部挂载或跟随符号链接；硬链接须全部位于该 rootfs 内才处理。中断后若该清理未完成，会显示明确错误并保留数据；完成清理后再回退 PRoot，避免以损坏的权限继续运行。

平台支持和真实启动效果必须以目标手机实测为准，桌面单测不能代替真实 Root/PRoot 双路径验收。

## 构建

先按[官方运行时构建说明](../runtime/README.official.md)准备真实 ABI 载荷。当前壳要求 manifest 明确声明官方分发和关闭旧桥接/补丁能力；缺运行时、旧分发或校验错误会提前停止构建，不输出缺引擎的假安装包。

**Windows：** JDK、Android SDK/NDK、Flutter 和 Python/Pillow 准备好后，从仓库运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

脚本自动生成品牌资源、校验官方运行时，并为中文路径使用临时英文构建别名。跨盘 Kotlin 增量编译关闭，避免 Windows 缓存错误。可传 `-PythonPath`、`-BuildRoot`、`-Mode release` 和递增的 `-BuildNumber`。

正式构建要求本机配置 `app/android/key.properties`，包含 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`；`storeFile` 相对 `app/android/app` 解析。密钥与配置已被 Git 排除，缺失时正式构建立刻停止。发布者须自行保管原发布密钥以维持后续升级签名一致；旧 debug 测试包使用不同证书，不自动卸载或清除其数据。

正式包可用 `python tooling/verify_local_web_release.py dist/deepseek-harness-local-0.2.2-rc.3-release.apk --output dist/release-verification.json` 核验：非 debuggable、ARM64 AOT、签名和实际内置资产。

**Linux：**

```bash
# 先完成 runtime/README.official.md 的官方载荷构建，并放入 runtime/out/arm64-v8a/
python3 tooling/make_local_web_brand.py
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
bash tooling/build-local-web-apk.sh -f arm64
```

默认版本来自运行时 `dshVersion`；输出沿用 Flutter APK 目录，Windows 脚本另复制到 `dist/`。生成资产只从源输入重新生成，不手改。

## 验证

```bash
cd app
# 设置 DSH_TEST_FONT_DIR 指向真实 Noto CJK Light/Regular/Bold TTC 字体目录
flutter test test/local_web_lite
cd ..
python3 tooling/test_local_web_runtime.py -v
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
```

另检查最终 APK 的包名、版本、签名、运行时资产及合并清单，确认无手机操控/伙伴组件。设备验收包含首次连接、权限、二维码/手动地址、PIN 网页登录、连接记录恢复、本机安装与启停、左下入口、键盘和设置。桌面回归、浏览器验证和真机结果分别记录，不相互替代。

## 来源与许可

原作者、代码来源与修改范围见[来源和许可](ATTRIBUTION.md)。保留 [AGPL-3.0](../LICENSE)、[第三方声明](../THIRD_PARTY_NOTICES.md) 和[素材条款](../ASSETS.md)；品牌输入和生成说明单独留存。本版的下载与反馈入口均指向当前私有维护仓库。
