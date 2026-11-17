# Round 18：手机版 rc.3 与依赖目录规范

## 任务与范围

将当前Android Lite手机壳升级为官方未修改`@deepseek-ai/dsh@0.2.2-rc.3`，保留现有主题、原40帧启动GIF、Root优先/PRoot兜底、配置只读查看和原签名。用户同时要求建立依赖目录约定，已新增根目录[DEPENDENCIES.md](../../DEPENDENCIES.md)，首页和中英文开发说明均有入口。本轮不搬动既有依赖、不修改桌面DSH或Purge私有仓库、不自动提交Android源码。

## 运行时

- 沿用官方构建器，固定rc.3并保存新[锁文件](../../runtime/locks/dsh-0.2.2-rc.3/package-lock.json)。
- 种子是保留的原始构建缓存，不来自手机文件系统。其SHA256为`8978b3f55a0525a4cb6573f23397c7c6d91bacdedbc7b2476dd54663f007586f`。
- 新rootfs：183725956字节；SHA256 `76e6ece3b92ff98acbb5a7e9a7b8b0597e0c7665307edec98764d6969c85e3b7`。
- 新runtimeVersion：`r16-official-dsh0.2.2-rc.3-node24.22.1-c7767e0f725d`。
- baseId保持`4e5b05dadfef6bb2a6dbd00872ec8309320b1fc9c12b922d7a50157d6737fc38`；精确15项升级路径原样。
- 独立归档比较：8482份保留JS逐字节等于官方prefix，10966项路径之外的基础系统记录（类型、模式、链接和内容哈希）与原始种子一致。
- node-pty、koffi、sharp必需原生模块为ARM64；sharp 0.35.5的二进制现在由官方index loader指向带版本号文件，按真实loader定位后通过，不改变pruner或放宽模块要求。
- 继续声明`official-unmodified`、`legacyBridge=false`、`enginePatches=false`。原JNI与三份许可侧文件逐字节保留；空`opt/dsh-go`退休事务槽保留。
- 原生升级四个核心文件未改。静态审查确认相同baseId/ABI/Ubuntu身份时只走引擎事务；旧20项迁移JUnit本轮未在Android ART执行，不把静态比较计为真实手机升级。

## 应用与指南

guide生成器原样保留，版本从真实运行时清单读取；指南真实再生成，8个版本/当前措辞/配置查看说明资产变化，另19个不变。正常与恢复profile、只读、不回传网页及后台/代次失效说明已双语同步。

13份界面/脚本/启动封面源码哈希与升级前一致。实际rc2/rc3 APK对照：114份共用Flutter资产逐字节一致，仅8份指南资产变化，配置查看桥与许可侧文件保留，原启动GIF仍40帧。

## 实际验证

| 检查 | 结果 |
|---|---|
| rc3版本新断言对旧rc2 builder | 6项中1个预期AssertionError；不是依赖导入失败 |
| 官方builder与归档集成回归 | 6 + 7通过 |
| 运行时preflight/网络/APK校验器回归 | 13 + 4 + 4通过 |
| 指南生成、--check、聚焦单测 | 26份检查/生成，25单测通过 |
| Flutter analyze | No issues found |
| maintenance Flutter | 259通过，7个既有跳过 |
| 原生配置查看/官方标记/文件输出 | 24通过、0失败/跳过，核对实际JUnit XML |
| 配置文档JS作用域回归 | 9通过 |
| 真实rc3设置CSS的Edge合成布局回归 | 通过；独立无账号blank页面，非手机WebView |
| 正式APK校验与资产对照 | 通过 |

## 交付与安装状态

- APK：`deepseek-harness-local-0.2.2-rc.3-release.apk`，包名`app.dsh`，ARM64 AOT、Release、non-debuggable。
- versionCode：`11140253`；大小229628656字节。
- SHA256：`4778fd5349bf34540b68cc32b8d1169079ce650092df983f8ddf4fa92fecca15`。
- 原证书SHA256：`d74e8f4d1821cfa9270fd0f6e70b92ad8c14407f42eec3f0d416a2d8571982fb`；签名验证通过。
- 当前ADB无设备，没有执行覆盖安装、卸载或清数据。最后确认的手机安装仍为rc2构建`11132323`；Root/PRoot、配置查看与rc3真实启动待连接手机验收。

正式包和校验报告在本地dist，未因源码编辑自动发布GitHub Release。旧运行时构建原件保存在独立证据目录，保留用户安装环境不变。
