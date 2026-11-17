# Android 目录与命名空间迁移验证

## Review verdict

**结论**：Merge with conditions（目录迁移与构建已验证；官方 rc.2 替换尚未完成）。

- **模式**：Deslop apply，范围仅为本次工作树中的目录/包名迁移与相关引用修复。
- **基线 / Head**：`1181ca8378b6654fe465edaf51703cc660ff97d8`，分支 `chore/official-dsh-rc2`；未提交、未推送。
- **信任级别**：trusted-local。
- **复核日期**：2026-11-12。

## 本次实际内容

1. 项目工作目录迁至 `DeepSeek-Assistant`，恢复 Windows 普通目录可见属性。
2. Android main/test/androidTest 源码树迁至 `kotlin/app/dsh/`；namespace 与 applicationId 使用 `app.dsh`，应用显示名称为 `DeepSeek Assistant`。
3. 同步清单、静态快捷方式、ProGuard、反射/原生进程入口及源码路径断言。Kotlin 代码中以 `app` 命名的上下文变量遮蔽根包时，改用显式类型导入。
4. 桥接源码目录迁至 `runtime/bridge/dsh-app-bridge/`；内置技能资产、插件示例目录、论坛主题及客户端 API 源文件改为新路径，保留原有协议与包身份。
5. 修复生成器使用分段路径时漏掉的目录引用；通过 guide、SDK、bridge 生成器重新生成相应资产，不手工修补生成模块。
6. 恢复先前误改的运行时 manifest：从已核验的旧 release APK 提取原始 metadata，并核实 APK 内 rootfs 与本地 rootfs 的 SHA256 相同。

### 保持不变的边界

- 手机主题、网页布局、鲸鱼按钮和输入框几何不作功能修改。
- Root 优先与 PRoot 回退逻辑、Root 原生通道及命名空间隔离实现保留。
- `app.dsh` 的应用身份和原签名保持一致；覆盖升级不卸载、不清空数据。
- 旧 rc.1 rootfs 仍使用 `/dsh-go/v1`、`DSH_GO_*`、旧 bridge loader id 和引擎 seam；本次恢复这些兼容拼写，避免只改一端后失效。源码目录改名不等于删除旧引擎扩展。
- 保留所用第三方内容的版权、许可证及来源记录。移动代码不改变来源或许可。

## Findings

本次发现并修复：单端路由改名、引擎 seam / 环境键与已打包 rootfs 不一致、bridge 替换 id 不一致、分段源码路径遗漏、Android 包名被 `app` 变量遮蔽。

独立只读复核确认：下面 Android 的源码计数/启动点白名单和 Windows 截图路径机制在旧基线已存在；没有为通过测试改动这些断言或门禁。golden 的差异集中于字形光栅像素，未执行隔离旧基线复跑，保留环境限定。先前 `pub get` 的版本漂移已备份并恢复为提交基线的原始 `app/pubspec.lock`，随后 `flutter pub get --enforce-lockfile` 通过。

下列结果不作为本次迁移已全部通过的证明：

- 依赖漂移时 `flutter analyze --no-pub`：0 error、0 warning、41 条 `deprecated_member_use` info，命令退出 1；恢复原始依赖锁后 `flutter analyze --no-pub --no-fatal-infos` 返回 0，输出 `No issues found`。
- 扩展 Android 测试：91 项中 3 项失败，包括旧源码计数断言、Root 启动点白名单和 Windows 符号链接测试；未通过放宽门禁消除结果。
- 完整版 WebView 测试：94 通过、33 跳过、2 失败（英文 golden 像素差异、Windows 截图路径）；不同于手机 当前 产品配置。
- Windows 上会话删除路由测试：6 个正向场景失败；生产实现明确在 `win32` 返回能力缺失，不能将其写成通过。
- 首次把完整版 WebView 测试放入 当前 define 运行产生额外失败，后按配置分开验证；此前结果不作产品回归结论。

## Validation record

| 检查 | 结果 | 说明 |
|---|---|---|
| ARM64 release APK 构建 | pass | 经项目 Windows 当前 构建入口，真实编译 Dart、Kotlin 与 release 打包 |
| release 验证器 | pass | 核 package、label、签名、AOT、ABI、Root 入口与网页/品牌资产 |
| WebView 布局/renderer 聚焦测试 | 240 pass / 6 skip | 恢复提交基线依赖后重跑；`DSH_LOCAL_WEB_LITE=true`，Windows x64 Flutter tester；不是 ARM64 真机 widget 测试 |
| 客户端包 analyze | pass | `No issues found` |
| 客户端 API 聚焦测试 | 46 pass | 改名后的 4 个 API/能力/文件/心跳测试文件 |
| 远程包 analyze | pass | `No issues found` |
| SDK 测试 | 112 pass / 1 skip | TypeScript 未安装，类型编译测试跳过；生成声明一致性通过 |
| bridge / native / plugin-config 聚焦测试 | 56 pass / 1 skip | 真实 pinned boot 测试因未设置 `DSH_PREFIX` 跳过 |
| guide 生成器单元测试 | 16 pass | 新资产目录与旧宿主技能身份相互独立 |
| guide / l10n / bridge / SDK 生成检查 | pass | 从输入再生后检查 |
| Web header Chromium 场景 | 18 pass | 自有临时浏览器 fixture；并非真机验证 |
| Android Root/bridge/process ownership/launcher 聚焦 JVM 测试 | 63 pass | 运行 `testArm64DebugUnitTest` 的对应筛选集合；扩展失败另列 |

精确命令与完整原始日志保留在本地会话记录；release 检查 JSON 位于本地临时验证目录，不包含签名密码、API key 或会话 token。

## Coverage and residual risk

- 已验证新源码路径存在，旧 Android namespace 未进入 release dex，Root 两个入口未被 R8 去除；runtime 补丁/pins 没有改动。
- 真实 rc.1 rootfs SHA256：`8978b3f55a0525a4cb6573f23397c7c6d91bacdedbc7b2476dd54663f007586f`。
- 先前已安装 release APK SHA256：`4a0fe10080430259d7963b2ff1c6ad22e2ebdb300e844f790b0fd21209e63fae`，本地保留副本。
- 根目录旧空文件夹仍被外部进程占用，暂留；未为删除空目录终止无关进程。
- 该迁移仍保留旧扩展实现。后续官方化需要替换真实 runtime 载荷、移除旧桥接/补丁调用链并重做 Root/PRoot 与 UI 回归；现有 rc.2 lock 文件和字符串锚点扫描不是升级完成证据。

## 真机记录

- OPPO PLQ110 / Android API 36 / ARM64，采用 `pm install -r --user 0` 覆盖安装；安装成功，新入口 `app.dsh.MainActivity` 冷启动成功，无卸载/清除应用数据。
- 原 `app.dsh` 工作区和已安装 runtime 仍存在。原记录选择电脑连接，升级后仍显示电脑；手动切回本机后正常启动。
- Root 实测：DSH 进程真实 `Uid/Gid=0`，进程根目录为应用私有 rootfs；`app.dsh.rootruntime.RootLaunchMain` 与 `RootNamespaceMain` 正在运行。
- PRoot 实测：用备份后的单一 `preferRoot=false` 下一次启动偏好重启，DSH 进程真实 UID 为应用 UID，根目录为 `/`，没有 Root helper。此项验证显式 PRoot 模式，不替代 Root 拒绝/超时的真机回退测试。
- 测试结束恢复原 `preferRoot=true`；原始偏好单文件与测试过程记录保留在本地临时目录。
- 最终原依赖锁验证包：`0.2.2-rc.1` / `11121950`，205486807 bytes，SHA256 `3e5c9e528cb05b938e51a235d93d4ba9245bf6659cbd49104e89a04aa852c7fd`；已再次覆盖安装并验证新入口 Root UID 0。
- 最终 APK 的 9 个网页适配资产、7 个品牌资产与原稳定包逐字节一致；rootfs、runtime manifest 和原生 PRoot 库同样未变。

## Merge Conditions

1. Root 拒绝/超时回退仍以聚焦测试为证，未补做真实拒绝/超时交互；未来运行时替换仍应独立覆盖安装验证。
2. 本次仅作为目录/namespace 迁移，不发布为“纯官方 rc.2”或“旧代码已全部移除”。
3. 保留上述未通过和跳过项目；另行处理原有测试/Windows fixture 差异，不把缩小测试范围描述为全量通过。
