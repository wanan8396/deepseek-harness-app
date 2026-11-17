# 官方 rc.2 运行时迁移记录

## 当前阶段

已生成未经旧引擎补丁的官方 `@deepseek-ai/dsh@0.2.2-rc.2` Linux ARM64 载荷，完成真机 rc.1→rc.2 事务升级及 Root/PRoot 启动、原生工具探针，并移除旧实现 bridge 装载器、生成器及全部 36 个生成资产。**仓库和 APK 仍有待拆除的旧全版模块；rc.2 页头合成 DOM/手机几何回归已通过 18 场景，完整真机交互验收与整个迁移目标尚未完成。** 本记录不作为正式发布完成说明。

基线提交：`1181ca8378b6654fe465edaf51703cc660ff97d8`；工作分支 `chore/official-dsh-rc2`；所有修改未提交、未推送。

## 已完成的真实改动

### 官方 npm 载荷

- 以 `runtime/locks/dsh-0.2.2-rc.2/` 的精确 package/lock 为输入，执行 `npm ci --os=linux --cpu=arm64 --libc=glibc --ignore-scripts` 在独立目录生成 Linux ARM64 optional 依赖树。
- lock SHA256：`f4e74dd02e5711a671cd78d51b25205b359391c085f5a1cb303c51776d675c04`。
- 官方 CLI tgz SHA256：`ce895e273bd76b63ce7285fcb018ce44000d3304d251ec3dfa83ee473a8f24ea`；最初 532 个文件与官方包逐字节核对一致。
- 当前版本使用 Node 内置 SQLite；依赖树没有 `better-sqlite3`。PTY、FFI、图片等所需 ARM64 预编译来自锁定的 npm 包，不从旧运行时复制原生模块。

### 可复现打包器

新增 `runtime/build-official-runtime.py`：

1. 仅以 checksum 匹配的旧**构建产物**作为 Ubuntu/Python/Node/pnpm 系统种子；从不打包已安装手机目录或用户 HOME。
2. 去除旧 `opt/dsh`、`opt/dsh-go`、`etc/dsh-app` 内容，换入官方依赖树和极小 CLI 启动 shim。
3. 保留原 baseId 和精确事务升级路径；旧 `opt/dsh-go` 仅为空目录占位，以便原安装器事务退休整个旧引擎目录，不保留其代码。
4. 不打入旧 bridge、Direct preload、boot cache、引擎 diff，也不在启动命令加入 App `--patch`。
5. 保留必要第三方许可，剔除不匹配平台/架构的二进制和开发 source-map/type 元数据，保留的 npm 文件不作代码修改。

已构建并校验的 xz 载荷：

- 大小：183658344 bytes。
- SHA256：`2636aa5b82845e8f876b04619cab6d556040f5dd3302ebf3892539b7a14d518a`。
- 19621 个保留 npm 文件逐项哈希与新安装 prefix 相同。
- 6 个 `.node` 均为 AArch64。
- 旧运行时代码目录内文件数为 0；启动 argv 无 `--patch` / `--import`。
- 已通过 App 原有运行时文件大小、SHA256、JNI 库预检。

### Android 启动

- 明确检查 `engineDistribution=official-unmodified` 和 `capabilities.legacyBridge=false`、`enginePatches=false`；只凭版本号不判断引擎能力。
- 官方分支不准备、不注入旧实现 bridge、auth、search、speech overlays；不重放旧 LastKnownGood、workspace recovery 环境扩展。
- `DshProcess` 对官方分支拒绝启用旧适配开关，不添加 Direct DNS preload；Root 优先/PRoot 回退入口保持。
- 恢复模式使用官方 `--profile dsh-app-safe --from-default-profile web`，在隔离 HOME 中复制官方 web 模板，不写旧恢复 patch 或旧修复工具。
- 正常模式原 HOME/profile 暂未做迁移；旧 profile/global patch 和插件残留是下一阶段必须核对的事项，不通过删除用户配置解决。
- UI、主题、网页适配文件及原依赖锁不作本轮功能变更。

## 已执行验证

| 检查 | 实际结果 |
|---|---|
| 官方 ARM64 `node-pty`、`koffi`、`sharp` 加载 | 手机隔离 Linux/chroot 中成功，Node 24.22.1 |
| 官方 CLI `--version` / `web --help` | 真手机返回 rc.2 及官方参数表 |
| 未加旧补丁的官方 Web | 隔离 HOME：ready；匿名 401；token 交换 303；已登录页面 200；包含官方 boot 注入 |
| 独立 PTY spawn | 已修复探针非递归 `/dev` bind；设备重连后正常输出 `official-pty-ok`，安装后的实际载荷也输出 `installed-rc2-pty-ok` |
| Python builder contracts | 5/5 通过 |
| 运行时打包预检 | 13/13 通过（包含 gzip 资产改名、旧分发、能力字段类型、旧 patch/preload 负向回归） |
| Android Gradle `OfficialRuntimeTest` + `RootRuntimeTest` | 16/16 通过 |
| xz ARM64 release APK 构建与签名/载荷校验 | 通过；rc.2 / 11122025，229609036 bytes，SHA256 `98202398e6629ab1b6322aa8bf4996cf989bf299f2024ee01b651bd18276c0e6` |
| 纯 JVM 新 helper / restart / classifier 测试 | 10/10 通过；另一个既有 SafePolicy Windows rename 覆盖测试失败，未放宽断言 |

### 发现并修复的打包问题

第一版试用 `.tar.gz`，Android asset packager 自动解压成 `.tar` 并改名，而 manifest 仍指向 `.tar.gz`，所以该候选包没有安装到手机。现已改为 `.tar.xz`：

- preflight 明确阻止 gzip runtime 资产。
- APK release 验证新增核对 rootfs 条目实际文件名、大小与 SHA256，防止此类构建成功但安装器找不到资产的假绿。
- 旧系统种子与原 rc.1 稳定 APK 均保留，输出和备份分开。

## 待继续

1. 继续结合实际升级后的 UI 回归。旧 Chromium 夹具最初只支持带空格的 JSON 字符串 CSS 声明，rc.2 改用压缩静态模板字面量；已修正夹具提取器且保留缺项、歧义和动态插值门禁，App 主题/样式未改。使用真实 rc.2 header/theme CSS 的合成 DOM 18 场景已通过（手机/横屏、浅/深色、当前/full、滚动与菜单）；这仍不是所有网页交互或全部真机视图的通过证据。
2. Root/PRoot 正常启动和独立官方 fresh 恢复 profile 已通过；App 自身切换恢复模式、恢复正常模式的完整 UI 流程仍待回归。
3. 电脑地址、二维码预览、PIN 导航、返回隔离与连接记录已通过 当前 widget 回归；相机实扫和外部电脑插件现场连接仍需单独记录。
4. 持续精确移除产品不使用的旧全版源码、Flutter/native asset 注册。旧实现 bridge 本轮已经真实删除，不再仅靠运行时分支排除。
5. 旧全版代码和其他资产仍在 APK/仓库中；“官方引擎无旧补丁”不等于“整个应用已经无旧代码”。

## 第二阶段：真机升级与第一轮真实删除

### 设备及执行证明

- Android ARM64 真机完成原包名、原签名 `pm install -r` 升级，没有卸载或清除数据。运行时实际安装标记和 `runtime.json` 一致，为 `r16-official-dsh0.2.2-rc.2-node24.22.1-f4e74dd02e57`；staging 已清理。
- Root：真实 UID 0，根目录是 App 私有 rootfs，由 `app.dsh.rootruntime.RootLaunchMain` / `RootNamespaceMain` 管理；实际命令为 `node /opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js web --host 127.0.0.1 --port 3080 --no-open`，无旧 `--patch`。
- PRoot：内核实际 UID 为 App UID，根目录观察为 `/`，没有 Root helper；网页匿名 HTTP 401（服务就绪）。工具探针以 App UID 执行 manifest 的 PRoot 命令，通过 PTY、koffi、sharp 图片生成、ripgrep、Node SQLite、DNS 和 npm。
- 探针中的 `process.getuid()` 在 PRoot `-0` 下显示模拟 UID 0，不作为真实 Root 证据；真实 UID 使用宿主 `/proc` 观察。已恢复用户原有 `preferRoot=true`。
- 已安装载荷的独立 fresh profile 使用 `--profile dsh-app-safe --from-default-profile web`，同样完成 401/303/200、官方 boot 注入和 PTY；没有访问或复制正常 HOME 的凭据。
- 数据校验：原凭据文件和用户 web profile `package.json` 升级后字节哈希不变；`cordis.patch.yml` 在运行之后哈希发生变化，升级前仅记录哈希而未保存内容，尚无足够证据归因，不声称所有用户配置逐字节不变。未删除或重建用户 HOME。

### 清理与验证

- 删除 `LiteBridgeGuest.kt`、其退休实现的专用测试、`tooling/sync_lite_bridge.py` 和经生成器逐项验证一致的 36 个资产，共 39 个文件。删除前仅作工作区外发无关的本地备份；保留项目许可与原始完整桥接源码中的必要署名。
- 同时删除 Controller/DshProcess 的桥接准备、参数和 patch 拼接入口，以及 Flutter asset 注册和构建生成步骤。当前 对非官方发行版返回明确 `official_runtime_required`，不退回旧桥接。
- 官方环境不再传旧 `DSH_GO_RUNTIME_ROOT`，也不导入 Direct DNS preload。
- 当前 App 根主题不再通过旧 `ui.json` provider 触发本机运行时；保留原生 settings 主题与网页外观同步。真机两个历史 ui.json 路径均不存在。原生插件 palette、旧 managed-skill 自动安装、诊断 phone-control 通道均仅完整模式使用。
- 新边界回归 4/4 通过；在仓库外副本单独移除这些 guard 后 4/4 失败，证实回归断言能够捕捉旧问题。完整版 Windows 分享文件名测试的原有失败在坏基线副本同样复现，未弱化断言。
- 完整模式 widget：211 pass / 6 intentional skip。Android 新桥接缺席断言与官方/Root 回归：17 pass。Flutter analyze：No issues found。
- 引擎事务三套单测在 Windows 首跑为 12 pass / 8 fail，失败包括目录 `FileChannel.force` 的 AccessDenied 和 `unix:ino` 属性不支持，前置失败也令故障注入点未触达。未改生产代码或削弱断言；将同一已编译测试与必要生产类用 D8 转为独立 dex，经真机 `app_process`/ART 在合成临时目录重跑，20/20 通过（7.222s），未触碰安装的真实 rootfs。首个运行探针假设设备有 dalvikvm 路径，启动前失败，改用实际 app_process 后成功；旧 D8 的 Kotlin metadata 警告保留在本地验证日志，未提升为产品错误。
- CI 增加显式的分支测试步骤，避免默认构建把这些测试全部跳过。

### 清理后候选 APK

- 显示版本 `0.2.2-rc.2`，build `11122055`；229461704 bytes。
- SHA256 `dbced0104466c15886101ab176bcfe2e0615f37a7997a09c650f67c370708dd0`。
- 原 release 签名证书保持不变；实际 APK 中已验证旧实现 bridge 资产和类均缺席，官方 manifest、rootfs 名称/大小/哈希一致，手机网页适配和鲸鱼品牌资产保持原字节。
- 已覆盖安装并启动，实际 Root 官方进程和运行时身份再次核对通过；真机实际安装目录的 514 个官方 CLI 保留文件均与已核验 npm 输入哈希匹配，不仅是 manifest 声称为官方。
- rc.2 页头 Chromium 18/18 场景通过；追加旧样式负控共 30/30 通过，确认旧 header 无滚动及旧菜单被裁剪的故障仍可被测试捕捉。8 个 CSS 提取正反探针通过。仅修改测试提取器，几何/触控/菜单/颜色断言及 App 样式未改；dock 独立矩阵未运行。
- 未提交、推送或发布。

## 第三阶段：退休旧覆盖层与连接配置写入

### 真实删除

- 删除 `SessionSearchGuest`、`AppAuthGuest`、`SpeechGuest` 三个 Kotlin 装载器；同时删除 Controller/DshProcess 的准备逻辑、三个启动参数和 patch 拼接路径，保留官方正常/恢复启动及 Root/PRoot 流程。
- 删除旧登录桥 `index.mjs`/`bridge.mjs` 的 Flutter asset 注册与文件，退休该实现专用的三份 JS/Python smoke/unit 夹具及 SpeechGuest 专用单测，本轮合计 9 个文件、84817 bytes。退休前原 auth bridge 基线为 19 pass / 1 skip（缺宿主安装）；删除是功能退出，不计为新官方功能测试通过。
- 加入实际 class/source/asset/注入参数缺席断言和 APK dex/zip 负向校验，避免只删调用但仍打包旧代码。
- 清理手机私有 rootfs 内旧 App 生成的 auth/search/speech/bridge 文件：仅逐项 SHA256 与已备份的生成输入完全匹配才删除，父目录和叶子均不跟随符号链接，不递归删除目录，空目录才 rmdir。共 42 个已匹配生成文件退出；没有访问或修改用户 HOME。首次脚本 CRLF 在第一行即停止；随后规范 LF，三个初次保留的 patch 也按 Kotlin 文本块的 LF 语义匹配后删除，未扩大匹配范围。

### 禁止旧配置迁移副作用

- 当前 的 LocalConnectionController 仍保留官方 cookie/mux readiness、close、网络重试和通知/快捷方式客户端，但不再读取旧原生 API key、建立 key 变化监听、恢复 provider key vault，亦不再执行修改 profile/可能重启的旧 Auto 权限修复。
- 新测试使用真实 DshClient/DshMux 与 recording carrier，不是只查源码文本：带非空旧 key 及其后续变化均没有 credentials/settings 写入，也不创建 settings/keyvault/guestFs；官方事件 generation、通知事件和 session/list 保持可用。未 guard 的坏基线确实出现旧设置读取和 credentials/set；guard 后双模式通过，保留完整模式原逻辑供拆分回归。
- 首轮独立连接回归：当前 4 pass / 1 edition skip，full 3 pass / 2 edition skip（各含原 local_connection 两例）；两文件 analyze 无问题。
- Android 官方/Root/退休适配器缺席聚焦回归 18/18 通过；完整模式 widget 213 pass / 7 edition/condition skip；全 App analyze 为 No issues found。
- 本轮新签名 APK 为 rc.2 / build `11122125`，229442920 bytes，SHA256 `6cd7e9b9af6f04c4270a1f062ff4adf13ffc9d92e665c0351dc8afc8503fe1a6`；实际 zip/dex 里已确认旧三个适配类与 auth 资产缺席，Root helper 与官方 rootfs 保持。
- 原包名覆盖安装后再次观察：Root 实际 UID 0/私有 chroot、PRoot 实际 App UID/无 Root helper 均正常，两个模式网页匿名响应均为 401；已恢复原 Root 优先。514 个已安装官方 CLI 文件哈希仍一致。
- 本轮安装前后原凭据、web profile package.json 与 cordis.patch.yml 三个文件的指纹全部不变。此结论仅针对本轮独立 checkpoint，不反向抹掉第二阶段 patch 曾变化且缺少原文对比的未归因记录。
- 新构建启动后检查旧生成文件，42/42 均缺席，没有重新生成；只做精确已知路径检查，没有递归清理用户目录。

### 仍待拆分的实际 owner

第四阶段已抽离只读连接和最近快捷方式 owner，通用通知的本机/电脑模式门和 DS Bot 懒启动亦已隔离；仍需把 CurrentSessionController、通知展示/格式化与 Kotlin phone/pet 编译引用从旧模块切出，才继续删除目录。当前未假称全部旧模块已移除。

## 第四阶段：独立只读 owner 与模式切换

### 中立类型与连接

- 原样抽离 HostKind/HostRef/hostLabel 到 `host_ref.dart`，编码、旧值解码、name 不影响相等/hash 的行为保持；secretStoreProvider 单独抽离，电脑网页 URL 状态不再通过整个旧 hosts_state 获取密钥存储。旧导出继续指向同一 provider/type 身份。
- `local_connection_state.dart` 提供唯一 `officialLocalConnectionProvider`。目的地未加载或 computer 模式先返回 null，不初始化 runtime/网络监听/client；本机时只读 runtime endpoint 并连接官方 cookie/mux 服务。mode/token 变化退休捕获的客户端，迟到的 connector 恰关闭一次；多个读者共享一个 client，不再各自发起连接。
- 旧实现 localConnectionProvider 只委托新 owner；完整模式既有连接仍在原模块，供拆分回归使用。新 owner 的 App 源码静态闭包不含 phone/companion/SSH/relay 文件；这是依赖图证据，不等于整个应用已不引用这些旧目录。

### 最近快捷方式

- LauncherEntry/RecentShortcut 原类型抽到中立 `launcher_models.dart`，新 `local_web_sessions_state.dart` 仅消费共享官方 client 和普通 session/list/events/workspace/projections 接口；不引用旧 sessions/hosts/connection/companion/account/bot owner。
- 保持最多三条、更新时间排序、blank/subagent/archived 过滤、标题 trim/fallback。读取旧伙伴绑定兼容时只读原偏好键，不构造伙伴状态；列表/archived baseline 未知或失败为 null 保留现有系统项，确认成功空列表才清空。
- projection 补读保持每次列表最多 40、并发 2、15s 指数退避至 10min；行版本、client 与 mux generation 失效保护，退休 HTTP 请求占槽直到实际完成，防止同客户端重连后失控并发和旧标题回流。
- 11 项真实 client/mux recording carrier 回归通过（包括实际 mux reconnect/ready）；移除 blank 过滤的坏基线输出错误会话并失败，正式实现恢复后通过。原三个完整模式 recent provider 用例只在完整模式执行，新实现 owner 由这组独立动态断言覆盖；没有跳过原 WebView UI 断言。

### 普通通知

- 当前 不挂远程 activeConnection 监听；本机/电脑切换明确 detach 本机 tracker、撤旧提醒、阻止旧审批按钮请求，回本机再挂当前连接。
- 当前 `_deliver` 不再读取额外 DS Bot filter/provider。回归验证普通系统提醒仍收到，本机→电脑时旧 source 发事件不再显示，回切可收到新提醒；Bot filter/provider 和 active remote connection 均未构造。单点撤掉 Bot guard 的负控确实失败，源码完整恢复。
- 通知模型/平台通道只导入中立 HostRef，不再为了标识引入完整 hosts_state。

### 验证与当前产物

- 全 当前 228 pass / 7 condition/edition skip；完整模式通知/审批/迟到响应与连接兼容 44 pass / 2 edition skip；新主机标识与原 hosts 36 pass；带 当前 define 的标识/电脑连接导航兼容 84 pass；全工程 analyze 无问题。
- WebView 几何夹具之前只模拟旧 localConnectionProvider，新快捷方式走真实独立 client 后触发未模拟的 connectivity 平台插件而失败。已在实际 `_liveHome` fixture 明确提供空官方连接/快捷方式（而非修改原几何断言）；正式 owner 的网络/列表/模式动态测试独立运行。最初误将 override 加入同文件另一个设置页夹具，未解决失败；纠正作用域并移除无用 override 后原全部网页壳与全 当前 通过。
- 最新候选 APK：rc.2 / build `11122159`，229444932 bytes，SHA256 `11327135051ca1429296cf2573636a9c55296607d790cb2f58732db759f2ad24`。原签名/官方载荷与主题鲸鱼 Web 资产保持，已覆盖安装。
- 最新真机 Root 与 PRoot 均正常，真实 UID/chroot 观察和匿名 HTTP 401 就绪确认；最后恢复 Root 优先。独立第四阶段安装 checkpoint 中，凭据、web profile package 与 patch 三文件保持原字节。安装前对第三阶段旧 checkpoint 复查时凭据已变化、两个 profile 未变，未读取内容、未作因果归属；独立新 checkpoint 防止把用户运行期间凭据刷新或操作误算为本轮安装写入。
- 额外真实互操作：从已安装官方载荷启动独立临时 HOME 的 rc.2 服务，项目真实 Dart DshClient 通过 HTTP token/cookie、官方 mux ready、session/list 与 workspace baseline；不是只有 fake carrier 的协议推测。服务不访问用户 HOME，token 仅进程内管道传递、未记录或回显，结束后临时服务和目录均清理。

## 第五阶段：优先修复手机 UI 反馈

本轮用户新增明确 UI 修改要求，优先于继续 CurrentSession/旧目录拆分；该拆分仅只读设计、没有落盘。不把本轮 UI 修复冒充又删除了旧代码。

### 封面、标语与清晰字标

- 采用用户桌面 `deepseek-whale-cover-natural-v2.gif` 原始 512×768 / 40 帧 / 循环 GIF；不是聊天归一化后只有一帧的 WebP。工作区资产 `startup-cover.gif` 与原始字节一致（SHA256 `28819e73e7a94d680a70a5bd4d2eca6c88bff734aafca9615b882950faec3e0b`）。Flutter 实际 codec 回归验证 frameCount=40/repetition=-1。
- 冷启动覆盖层、连接恢复、引擎等待与网页初载统一使用 StartupCover；正常等待移除进度条和“等待加载”，不添加最低等待时间。错误重试、环境安装与一次启动门保持。裙下标语新增中英文 ARB 输入后运行正式生成器；后按用户追加要求用 22px/500 字重/4px 字距和 1.35 行高，横竖屏均验证不溢出。
- 紧凑权限页的原文字图只有约 245×35，手机高 DPI 上采样会模糊。顶部改用原鲸鱼图加原生字形的 HarnessWordmark，仅修改紧凑标题；大欢迎页原图、页面主题和配色不变。Android label 与 AppInfo.name 统一精确 `DeepSeek harness`，包名、签名保持。

### 鲸鱼与浮层

- rc.2 的侧栏同时有 role=dialog；旧 modal 观察把它当全屏阻塞层，加上 Dart 又按 sidebarOpen 隐藏底部整行，会令鲸鱼在抽屉打开后消失。现在排除精确 `data-shortcut-modal=sidebar`，底部入口不因侧栏打开而删除，侧栏账号区为其保留 48px。真正阻塞 dialog 与键盘仍按原逻辑临时隐藏并恢复。
- 对账号、删除会话/工作区、模式右侧省略号、底部缓存与子菜单分别核对实际 rc.2 打包代码。菜单有普通 position-anchor，以及 contextual anchorPoint 指向 shell.overlay 里零尺寸命名点两种；后者精确关联坐标吻合的唯一 expanded trigger，多个同点候选时不猜。缓存 compact Tooltip 是 aria-describedby 精确 ID + JS 固定定位，不是 CSS anchor；非 compact 统计 dialog 仅处理 composer-stat 的精确命名锚点。子菜单保留 --dsh-submenu-parent 与 page/side 合同。
- App 注入只调整精确关联 portal 坐标/安全区/可用尺寸，保留官方动作、DOM 归属与外观宽度下限 144/163/300。原 body transform 的包含块差值被显式折算，滚动、safe inset、键盘和回前台重新定位；不是把任意 menu/dialog 固定到一个角落。官方 npm/引擎文件未改。
- 独立桌面 Edge 几何回归：47 个修复场景通过，47 个故障注入/坏基线场景复现通过；真实 rc.2 CSS、核心 Tooltip 定位函数及合同 DOM，三视口含横屏，覆盖真实 pointer hit/click、scroll/keyboard、重复触发器隔离和无关弹层不变。47 场景共 7050 个事件，稳定后 8 帧 style 变动合计 0，无该测试范围内 MutationObserver↔rAF 自激循环。这是合成合同回归，不冒称已观察到手机内部 DOM 根因。

### Root 就绪延迟

- 真机旧 build11122159 三次 Root launch→原生就绪均 2004–2005ms；独立 HTTP 已比 token-derived 原生就绪早约 838–930ms。确认 RootRuntimePipe 把 frame 写入 PipedOutputStream 后漏 flush，Android PipedInputStream 阻塞读只等 1000ms 轮询唤醒。
- 同一独立探针在桌面 JVM 与手机 ART 分别实证：旧实现约 1000ms，flush 后为 0ms。生产只在 stdout/stderr 每帧 write 后 flush，不改帧内容/顺序/大小或 Root 检查、namespace、恢复和 PRoot 回退。RootRuntimeTest 增真正阻塞读者双流回归，连同原十项共 11/11 通过。
- 旧启动 profile 的必需 namespace/ownership 恢复约 1.9–2.5s 保留；没有将其删作“加速”。整机新版后测另记录，HTTP / Flutter 首帧不代替网页 ready。

### 当前验证与产物

- 完整模式 233 pass / 7 condition/edition skip；全工程 analyze 无问题；l10n 62 parts / 6213 keys 检查通过。中间五个失败均完成闭环：两项旧启动进度外观断言已按用户新契约改；旧侧栏隐藏断言改为入口可达；两个纯 Node DOM 模型补新增真实 API 并增加侧栏可见负向断言。没有跳过失败用例来制造通过。
- 首个内部候选在用户追加标语字号后未交付；下一构建因浮层最小宽度保真调整主动取消；最终生产冻结后重建。
- 本阶段首个已安装签名 APK：rc.2 / build `11122301`，229718159 bytes，SHA256 `a6084d2d739a9af88eed763d7dbe6a19185a1fd3eacc1eeef4969c5fdc6259e5`，应用名 `DeepSeek harness`。实际 APK 校验包括 phone.js/css/modal、原始 GIF 字节、旧适配器缺席、官方 rootfs digest 与 release 签名。已覆盖安装，用户数据保留；引擎与主题代码未改。随后用户发现 ContextMeter、长按和动画/说明问题，以下补充修复进入更新候选，不把此首包冒充后续修复已安装。

### 追加反馈：上下文、长按、真实睁眼与说明

- 右下 ContextMeter 并非缓存 UsagePill：独立 `--dsh-context-*` named anchor 在 composer-dock，漏掉它会使缓存修正有效但上下文仍错位。现以精确三合同（命名前缀、dock归属、dialog触发器）接入，保留官方264px/8px。旧47扩成53场景，全部通过且53个坏基线复现通过；7950事件后静默style变动为0。
- 长按/右键对话和工作区走官方 `contextmenu` 的 clientX/clientY点，不产生 expanded 三点按钮，因此点击三点路径通过不能证明长按。新观察器只记录真实 sidebar row、官方已 preventDefault 的同次事件、新创建菜单与虚拟 named point完全匹配，不消费事件、不代用户打开/删除。坐标随原row移动。
- 独立30项长按回归中12项为真实 CDP rightclick，另含 keyboard(0,0)、四边、scroll/body transform、未处理/无关/旧菜单不接管和same-frame新事件。实测两处问题并闭环：监听器间microtask可能在官方handler前执行，故从Promise改rAF；旧rAF可能覆盖较新的无关/未处理事件，故加context事件generation。最终30/30、去掉记录段坏基线30/30复现、旧53/53重新运行通过。失败前2项竞态证据另存，不覆盖。
- GIF并非缺睁眼帧：真实原frame0闭眼、frame20/32睁眼；实际Flutter Image会因祖先MediaQuery.disableAnimations暂停多帧，而旧自动performance策略将其写成true。现在封面只遵循真实系统减少动画设置，不把旧性能降级当用户关闭动画；LaunchOverlay同样取消Lite强制reduced。10项强测核对真实AssetImage→RawImage/RenderImage与独立codec逐像素完全匹配，2010ms/frame20和2710ms/frame32面部SHA256均不同；真实系统reduce=true才保持frame0。不是仅检查40帧元数据。
- WebView初载封面改为220ms AnimatedOpacity退场，AbsorbPointer在加载/退场期间吸收正文触摸（IgnorePointer反而穿透，已改）；保留同一WebView controller和一次load，底部鲸鱼独立上层仍按就绪可用。失败立即移除遮罩供重试，renderer换代后的旧finish通知忽略。中间alpha介于0/1、221ms下一tick移除均有强测。
- 当前使用说明不是旧文案改名：26份中英md实质重写为官方rc.2手机壳实际入口、Root/PRoot、权限、网页模型/插件、HTTP(S)/QR电脑连接、分享草稿、归档/工作区数据影响与自动任务；不再教旧原生聊天/手机自动操控/pets/SSH。旧12文件名和内部skill id仅作兼容，用户可见正文与提问提示用DeepSeek harness。generator从实际runtime manifest dshVersion核对，不读旧pubspec版本；24测试及5个旧行为负控通过。
- 此阶段曾新增原生“使用说明”入口，直接读双语资产；当时245 pass / 7 condition skip、全工程analyze无问题。后续用户明确要求移除此入口，已按下方第六阶段处理；这不是当前仍存在的入口。
- Root管道优化后同条件3轮测量：launch→nativeReady为1157/1141/837ms，旧2005/2005/2004ms，中位数减少864ms（约43%）；独立HTTP从am调用为3485/4625/4438ms，旧5672/5531/4875ms。prepare恢复时长存在波动且首样本2ms，不能把所有差值归因pipe。CDP仍无页面，网页ready未测得，不以HTTP/首帧冒充。
- 第五阶段结束时手机断开，build11130025已验签但未安装；第六阶段重连后覆盖安装成功，官方Root进程实际UID0、HTTP401就绪，三份配置指纹逐字节保持。真机账号菜单确认在账号上方、鲸鱼侧栏可见；工作区长按尝试期间页面被切到原生连接页，故不把这张截图当作长按验收成功。

## 第六阶段：按用户最新要求精简连接页（2026-11-13）

- 直接要求为“侧边使用说明可以删掉本机和电脑这个中间隔线不美观优化一下”。已删除新增说明ListTile、孤立原生reader及其三个无消费者的双语key；保留重写后的实际指南内容和资产校验，移除双语10-settings中已不存在的入口描述。
- 本机/电脑仅两项，之间以8dp留白代替Divider；保留原主题、圆角、选中底色、勾选、权限按钮和电脑地址/二维码/历史入口。标题下原有AppBar细线不属于两项中间线，保持原样。
- 新回归精确断言两项、说明缺席、列表内部无Divider、两项间隔8dp；首次误把AppBar Divider也计入导致五项失败，已将验证范围收窄到真实连接列表，而非删标题线或跳过失败。完整Lite最后244 pass / 7 condition skip；整工程analyze无问题。指南25测试通过，l10n生成6213keys。
- 四个真实选择owner作为官方化前置清理迁到selection_state.dart，旧hosts/sessions仅re-export同一符号；持久化keys/恢复逻辑/override身份保持。抽前和抽后原44项都过；新完整模式13pass/3skip、Lite11pass/3skip，静态中立owner闭包7文件。当前web_home/notify消费者尚未接入，不能声称已完全切断旧消费闭包。
- 最终签名APK build11130044：229677432bytes，SHA256 `9fa97ebcd5f64146b533eeefa3f323e426cf8ef20d6a1fa2fadbf2246b6d6575`。实际包验签、全部JS/GIF/指南与官方rootfs核对通过，已覆盖安装到手机（pm Success）。安装前后三份凭据/profile只核对指纹，全部精确保留，HTTP401就绪。
- 已读取真机最终连接页截图：只见本机和电脑、无说明项，两项之间无横线、选中圆角与权限按钮保留。截图含设备状态，只用于内部验收。后续整体验收仍需长按会话、上下文及启动全程逐项闭环，旧模块消费依赖与原生phone/pet耦合仍待清理。

## 第七阶段：消费端接入、原生适配器隔离与真机启动验收（2026-11-13）

- 消费端已实际接入中立选择 owner：`web_home.dart` 不再直接导入旧 `hosts_state`/`sessions_state`；SSH 快捷方式有效性校验移入既有 `dsh_web_launcher.dart` 且仅完整模式调用，当前 本机快捷入口不再读取 hosts；`launcher_entries.dart` 只替换活动主机选择。旧 provider 同名 re-export 与完整模式 recent-list 旧依赖如实保留。
- `notify_state.dart` 改为直接依赖 `host_ref`/`selection_state`。新增动态断言：当前 本机通知送达后不存在 `hostsProvider`/`sessionsProvider`，真实通知点击选择走 canonical `currentSessionProvider`。既有 `notify_state`/`notify_action`/`turn_end_race` 41 项与普通边界测试通过。
- 完整模式 回归 **244 pass / 7 condition skip**，全工程 analyze 无问题；l10n 6213 keys 与 26 篇指南检查通过；diff whitespace 0，主题与 pubspec.lock 未改。
- 原生通知旧耦合已隔离到唯一显式适配器：`FullNotifyAdapter.kt` 集中保留 `PhoneControl`/`PetOverlay`/`ResultSilence`/`DshService.phoneStopIntent`，`MainActivity` 仅两行 full-only 安装；`ChatNotifier`/`LiveActivity`/`XiaomiFocus` 的 phone/pet 静态引用归零，`XiaomiFocus` 改用既有 `org.json`。未安装适配器时静默 false、手机任务/头像/停止动作均为 null，没有反射或新增吞错。
- 原生验证：full 改后 15 项、当前 改后 18 项（另 3 项既有 manifest/activity 合同）全部通过 0 skip；`compileArm64DebugKotlin` 实编通过；当前 release merged manifest 包名 `app.dsh`、phone/pet 组件 0、审批 receiver 保留且不导出。隔离旧源码负控恰好 2 项断言失败，证明边界测试有效。
- 真机冷启动逐时截屏（30 帧，附实际采集区间）首次实际看到：闭眼封面 → 睁眼 → 进入官方对话页。之前只有像素级 widget 证据，本轮补齐设备端时间线；0.35s 帧间隔仍不能替代逐帧录屏。
- 最终候选 build11130109：229678214 bytes，SHA256 `ab32945e6d220b3b94a2b10a1d0a5f8617a9f18cd2ff6cde09df5e391a101341`，签名证书未变，官方 rootfs/全部 JS/GIF/指南字节核验通过，已覆盖安装。
- 安装后核验：官方 Root 实际 UID0/私有 mount namespace、服务 401 就绪；切 PRoot 后进程 UID10351、root `/` 容器路径、引擎正常，再恢复 Root 偏好回到 UID0。三轮前后三份凭据/profile 文件哈希逐字节不变。手机当前仍连接。
- 真机 UI：侧栏底部账号菜单在账号上方且鲸鱼可见；一次长按落在对话消息上，打开的是官方消息菜单（复制/朗读/翻译/编辑重发/回滚/删除/插入总结/创建分支/信息/多选），落位贴合触点且未越界。它不是侧栏会话行长按，不能替代该项验收；该路径由 30 项真实 CDP 合同与既有 53 项覆盖。

## 第八阶段：可证删除、既有基准漂移与原生死代码

- 删除 `ui/common/glass_pill.dart`（3201B，SHA256 `59263a7e…fe98c`）：产品、测试、工具代码零引用，仅两处文档组件清单提到，已同步。
- 删除 `ui/bots/drawer_row.dart`（3217B，SHA256 `c697605f…ac679`）：与 `shell/sessions_drawer.dart` 内真实抽屉行重名的陈旧副本。原 `bots_pages_test` 两个用例测的是死副本，真实组件由 `integration/wiring_test` 覆盖；已删副本并移除这两个陈旧用例，使覆盖重新指向生产实现。
- 删除原生 `ResultSilence.apply`（已零调用，ChatNotifier 改用 `NotifyFeatures.silencesResult`）。`ResultSilence` 本身与 `petSpeaks`/`silenced` 仍被 full 适配器使用，保留。
- 既有问题：`app/test/integration/goldens/` 十个基准图当前不匹配（0.46%–3.44%）。仅 drawer dark/light 做过删除前后 A/B：临时还原两个被删文件后，这两项失败比例相同，支持它们不由这两个删除引起；该证据不证明其余八项的原因，也未证明具体源自主题或字体。未改写基准图。
- 原生编译曾因 `android_file_picker` 的 Kotlin 增量缓存损坏而失败（`Could not close incremental caches`），清理缓存并停掉残留守护进程后编译通过，与本轮改动无关。
- 本轮验证：`bots_pages_test` 11 项、完整模式 244 通过/7 条件跳过、analyze 无问题、原生 `ResultSilenceTest` + notify 全 15 项 0 失败 0 跳过、原生 Kotlin 编译通过。
- 候选 build11130149：229678552 bytes，SHA256 `313feee1daca707400f1b9011b4e5d7551e39699a66407b06b010cd083aa03c4`，签名与官方载荷校验通过；因手机 ADB 断开尚未安装。

## 第九阶段：删除落地、回归锁与旧桥存留判定

- 确认 `runtime/bridge/`（33 文件）与 `runtime/patches/`（124 文件）**不是死代码**：`.github/workflows/ci.yml` 的 runtime 作业仍执行 `rtbuild.py patch-dsh`、`test_patch_dsh.py`、`run-guard-tests.sh`、`run-native-tests.sh`。官方构建器 `build-official-runtime.py` 只调用 `rtbuild.py` 的 `dsh_drop_reason` 与 `elf_summary`，不打包桥或补丁，但仓库级 CI 契约仍在，删除会破坏 CI，故保留。
- 新增 `app/test/maintenance/legacy_removal_test.dart`（3 项）锁定本轮删除：未引用的 `glass_pill.dart` 与重复的 `ui/bots/drawer_row.dart` 不得回归、`DsBotDrawerRow` 全库唯一、`ResultSilence` 不再构造通知、notify 核心不得重新出现 `app.dsh.phone.`/`app.dsh.pet.` 直接引用。
- 负控：把 `glass_pill.dart` 从 HEAD 临时还原后该测试立即失败（`Expected: false / Actual: true`），证明断言有效；随后恢复删除状态。3 项正跑通过，全工程 analyze 无问题。
- 另一个 golden 样本：`shell_golden_test` 的 26 项图片比较也未通过（如 `web_offline` 0.69%）。这表明问题并非仅集成测试样本，但尚未独立锁定字体、平台或源码改动的具体原因，不能据此声称全库均为环境差异。未改写任何基准图。
- `plugin_config_memory.dart` 等仅测试引用的文件经核对是测试替身（模拟 Host 接口），不是死代码，保留。测试导入扫描未发现任何悬空引用。

## 第十阶段：自动 Root、启动对齐、盾牌菜单与品牌技能迁移

- 用户要求权限页移除 Root UI，启动时自动判断。实查旧 `prepareLaunch` 被持久化 `preferRoot=false` 阻断，先前“已有自动检测”的说法不准确。现每次本机引擎启动按代际核验真实 UID 0，成功优先 Root，失败沿现有 PRoot 路径；恢复与启动共用一次探测，下次启动重新检测，运行中不热切换。权限页不再显示 Root、读取 Root provider 或在 resume 请求探测，孤立旧 Root 行实现已删除。
- 启动等待页的 Column 原来预留底部按钮高度，网页加载层却覆盖全视口，导致 GIF 与标语中心在交接时偏移。改为全屏 Stack + 覆盖按钮；启动遮罩、恢复、等待及网页初载复用同一背景与阶段布局。三尺寸真实状态交接逐矩形对齐通过；临时恢复旧 Column 后三例全部失败，源码精确恢复。保留原始 40 帧 GIF、22px 标语和 220ms 网页过渡。
- 输入框左下盾牌的官方按钮没有 `aria-expanded`，仅 chevron 表示展开；其 `conversation.input.permission` named-anchor portal 漏出旧接管范围。App JS 新增精确合同，仍由官方菜单执行权限选择。59 项浮层/59 项坏基线以及 30 项长按/30 项坏基线通过，CSS 与官方 npm 未改。
- 手机确实残留四个旧 App 托管技能。新官方启动阶段在已有 worker 中更新 `dsh-go-guide` 的全部当前说明，并只将三个托管旧原生技能（ui/plugin/support）的 `SKILL.md` 原子归档为 `SKILL.retired.md`。rc.2 官方扫描每个技能目录仅查 `SKILL.md`，归档不再进入目录；附加文件保留。用户去掉托管标记、符号链接和自有技能保持原样，不修改用户 profile/会话或官方引擎。全局 当前 AGENTS 使用精确产品名 DeepSeek harness，说明自动 Root 与网页界面；兼容 ID/许可证保持。
- 最终 maintenance 回归 247 pass / 7 condition skip，全工程 analyze 无问题。聚焦原生 36 项通过（Root16、notify13、技能迁移6、AGENTS 1）；较大原生44项运行有2项未改诊断文件替换测试在 Windows 失败，异常为二次替换 diagnostics.md 的 `cannot replace`，原记录保留，不宣称44项全过。
- 正式构建、验签和覆盖安装完成：build **11130312**，229679049 bytes，SHA256 `fe8c81a899f67804fd2096e766509e8fa9801849e8d3ba767efc8672f81e0d3f`。原签名、官方 rootfs 与全部 JS/GIF/指南字节核验通过。第一次安装因设备短暂离线在修改前停止，重连后 `pm install -r` 成功。
- 真机设置旧 `preferRoot=false` 后仍以真实 UID0/私有 mount namespace/chroot 正常启动，实际端口3080匿名HTTP401；测试后无中断恢复旧偏好原值，新代码已不依赖它。凭据、web package 与 profile patch 三份文件安装前后指纹完全一致。设备全部26份指南字节与生成输入精确相同，三个旧入口缺席且归档保留，新品牌与自动Root全局指令确认已落盘。
- 用户同时在操作手机。新版盾牌点击尝试和打开权限页时页面被并行切换，不能把这些截图计作真机菜单/权限页验收；未为录屏打断用户正在运行的对话。新包完整启动连续性、实际盾牌菜单可见、权限页 Root 缺席、侧栏会话长按仍需稳定设备验收。此轮不声称整个旧代码清理与总目标完成。

### 用户更正：删除，不归档

- 用户明确要求旧 skill 直接删除，而非停用/归档。已将 `OfficialPhoneSkills` 改为删除三个固定旧托管技能的完整目录（ui/plugin/support），同时识别前一版本的托管 `SKILL.retired.md`；不再创建归档。用户移除托管标记或路径含符号链接时保留，不扩大到其他技能目录。新版指南继续更新。
- 手机已直接删除三个旧目录共30个文件：ui6、plugin23、support1，含旧归档。删除前后凭据及两份 profile 指纹完全一致。首个执行尝试因 `/usr/bin/python3` 路径不存在，在任何删除前停止；改用已核实的 `/opt/python/bin/python3` 后完成。
- 原生技能迁移专项8项通过、0失败/跳过，覆盖旧活跃目录与前版本归档目录的真实删除、重复执行、新指南、用户接管、取消和符号链接保护。正式文案/指南检查及 diff whitespace 检查通过。
- 新签名 build **11130328** 已覆盖安装，229680080 bytes，SHA256 `45e895c8f676ec8c3cb10cb01382bd4be754afda71c760c9ac862804060ed2e7`。官方载荷/资产及原签名验真；启动后再次核对三个完整目录和归档均不存在，26份新版指南逐文件字节一致，三份配置指纹未变，官方 Root 实际UID0且HTTP401正常。该包替代前一归档版本。




