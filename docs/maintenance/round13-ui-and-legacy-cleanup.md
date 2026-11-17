# 页头分支胶囊修复与旧技能通道退休

日期：2026-11-13。基线：`d98afb64698013908dd99a74e3eba1c7e0d81b5d`。当前改动尚未提交或推送。

## 用户截图对应根因

截图中的树枝、横杠和边框来自已安装的 `dsh-github-gate` 分支胶囊，不是官方 forge 页头按钮。静态读取实际安装插件的 browser artifact 后确认：它以无 display 声明的 `.ghk-root` span 包住局部 style 和 `.ghk-pill`；pill 固定高 24px，空状态是 span，有可切换分支时才是 button。

手机适配把 utilities 的直接子项最小高度设为 40px，但普通容器的 align-items 不生效，内部行盒仍靠上。真实 Chromium 合同夹具测得空态框高 26px、中心 y=67，按钮态高 24px、中心 y=66；同排更多及侧栏按钮中心 y=74。与截图约 25px 的物理像素上偏一致。

仅在当前 drawer 的准确 utilities 槽下为 `.ghk-root` 开启 inline-flex，并为直接 `.ghk-pill` 使用 border-box、最小宽高40px。未改插件、官方 npm、图标路径、配色、分支文字、空态语义或切换事件。

## 实际删除范围

- 删除 UI/plugin/support 三组旧 App 教学资产33文件与 pubspec 注册。
- 删除旧 Dart 教学技能 owner：本机自动安装、同步磁盘 helper、远程 shell/提示词 installer；移除 RootGate 监听及远程设置安装入口。
- 同时删除 RuntimeBridge/MethodChannel 的 install/cancel、generation 字段和仅服务旧 Dart 通道的 native owner/gate/queue，未保留空壳。
- 当前启动 worker 的 OfficialPhoneSkills 指南同步、旧托管目录实删、用户接管保护及 Root/PRoot 生命周期保持。
- 指南常量移到中立 state 文件；附件读取使用真实 dsh-app-guide 资产目录，稳定安装 ID 保持 dsh-go-guide。
- 原 ui.json schema/checker 和3份示例的原始字节仅保留为5个测试夹具，不打包、不带 SKILL/manifest。
- SDK 原始教学输入/许可证保留，原 sync 命令收窄为只读兼容检查；APK verifier 拒绝三组退休资产回生。

旧 bridge/patches、phone/pets/companion/full UI 主体及旧 CI 消费链尚待后续完整退休。此次不是全仓旧代码清理完成声明。

## UI 检查覆盖

- 页头：三尺寸320×640、363×800、800×363，深浅主题，长路径，横向真实 wheel 输入，菜单锚点、触控和分支空态/可切换长分支+PR。
- 侧栏：官方与适配抽屉状态、frame replacement、重复注入；会话/工作区长按及菜单归属。
- 输入与浮层：账户、缓存、上下文、权限、子菜单的尺寸及边界。
- Flutter 壳：启动GIF/标语与等待→WebView阶段几何、权限/连接页、安全区、键盘与原生底部控件。
- 设置键盘疑点经实际 rc.2 CSS specificity 与 Chromium 几何验证排除；仅扣除一次键盘高度，未作无效产品修改。
- 修复旧 phone layout Node 夹具缺失 getComputedStyle.getPropertyValue 与视口字段的异常，保留原断言。

这不是所有页面和状态的真机验收。新会话故障仍是独立未闭环问题，不归因于 skill 删除，也未宣称已修复。

## 已执行验证

| 检查 | 结果 |
|---|---|
| rc.2 shipped CSS 的 Chromium header/branch/menu 合同 | 42 passed；12个旧分支布局均按预期失败；12个非Lite对照深比较无变化 |
| 账户/上下文/缓存/权限/子菜单 Chromium 几何 | 59 passed |
| 会话/工作区长按菜单 Chromium 行为与几何 | 30 passed，0 failed |
| Flutter + maintenance | 246 passed，7 skipped，exit0 |
| Flutter full schema/parser/checker/guide/ask_ai/runtime | 112 passed，无skip，exit0 |
| Flutter startup/boundary/current guide | 35 passed，exit0 |
| Flutter analyze --no-pub | No issues found，exit0 |
| SDK原技能/防回生 | 4 passed；默认和--check不写资产 |
| APK退休资产单元检查 | 4 passed；去除实际gate后3个坏ZIP子例均失败 |
| 指南/l10n生成检查 | 26 files / 62 parts、6213 keys，通过 |
| Native guide/installer/Root/当前品牌 | 39项中38 passed，1项既有Windows符号链接基线失败，见下 |
| Full web全量 | 99 passed，32 skipped，2 failed，见下 |

### 保留的失败与限制

1. `ManagedSkillInstallerTest.escapedFileSymlinkIsNotFollowed`：Windows/JDK21 的 File.canonicalFile 未解析真实符号链接，expected userOwned/actual installed。隔离编译原HEAD完整Installer、原fixture及逐字原测试方法，复现相同1/1失败；未skip或改expected。Android启动同步另有未变的plainPath逐层拒绝符号链接。未将平台基线问题混入本次清理修复。
2. ui_config旧widgets/state聚合：16 passed/7 failed；6个golden差异像素前后完全一致，另local wiring5秒超时，相关生产核心未改；未更新golden基线。
3. Full web：英文handle sheet golden差5817px；旧pet screenshot夹具使用Windows反斜杠路径，而Android专用入口guard只接受`/`起始路径，事件未派发导致No element。相关代码与HEAD字节一致，测试不挂RootGate；未把其视为本次旧installer退休回归。
4. SDK全量111 passed/2 failed/1 skipped；两失败为原生成快照CRLF/LF严格比较，临时副本重新生成归一后相同；TypeScript依赖缺失跳过，未动锁或依赖。
5. 最初把full web_mode测试与Lite define一起运行出现21个模式不匹配失败；已分产品Lite和full模式重跑，以上按正确模式结果记录。

## 最终构建与交付

签名 Release 已构建并经实际 APK verifier 验证：版本 `0.2.2-rc.2`，构建号 `11131252`，229548567字节，SHA-256 `7877da88a7e02098047b91b6298cba3e890d673327a220b7be3e7e08ff4c6046`；签名证书保持 `d74e8f4d1821cfa9270fd0f6e70b92ad8c14407f42eec3f0d416a2d8571982fb`。

APK 的官方分发、ARM64 AOT、非debug、Root入口、运行时摘要、原40帧GIF、当前网页CSS/JS及指南字节均验证通过，三组退休技能资产缺席。当前CSS SHA-256为 `cb6efb6cb3aff054214ed1e0e6e3b5c6ff7c37af7acb820aa80a95b15801b9dc`。

未覆盖安装到用户正在使用且运行并行任务的手机，因此没有宣称新包已在真机展示修复效果。仅捕获过修复前页面并读取实际已安装插件代码作根因证据；未对用户页面发送点击。安装包提供独立交付，升级保持原签名与数据。未提交、推送或发布GitHub Release。
