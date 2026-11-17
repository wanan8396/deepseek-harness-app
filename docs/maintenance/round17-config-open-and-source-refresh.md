# 最新私有源码重建与手机配置文档打开

日期：2026-11-13。用户要求删除当前GitHub仓库、上传最新源码并保持私有，随后检查手机“打开配置文件”。本地原分支、索引及既有未提交修改保留。

## 私有仓库重建

已实际删除旧实例并创建同名 `wanan8396/deepseek-harness-source`，GitHub返回新仓库ID1456778095，旧ID1456292413；private=true，默认分支main。上传快照含下载目录修复与11132323实际功能说明，共5989文件、397036843字节，初始提交 `aa3578557b1500ecf4ec62f9ad86223e6e3f1bf5`，tree `ba6c61585eb728e18a34b7fe35077ff63f4de324`。没有上传APK、私钥、个人配置或临时材料。

上传前完整清单哈希校验，并逐文件证明52条既往已审测试签名命中的源码字节、数量和行位置完全未变；没有新增未审命中。创建快照使用独立索引，未切本地分支或重置工作树。

独立Git完整拉取长时间无数据传输，因此终止该验证任务，改用GitHub递归tree。5989个远端文件的路径、模式、大小和Git blob内容标识全部匹配逐文件SHA256校验的本地快照，仓库ID确认确已重建、visibility=PRIVATE。此方法是远端内容标识核对，不称已把全部blob独立下载逐一计算SHA256。临时拉取副本已清除。

## 配置文档根因

当前官方rc.2真实调用链：

1. `SettingsDocumentAction` 点击后调用 `SettingsDocumentStore.open()`。
2. RPC为 `settings/openSettingsDocument`，不是文件浏览器/reveal路线。
3. 服务端先取当前profile provider的 `prepareDocument()`，配置位置来自 `configEditor.documentPath` → `profileContext.patchPath`。
4. 调用 `openNativeTextFile(path)`；普通Linux分支执行 `xdg-open path`。
5. 手机chroot里没有桌面打开器，原生失败包装成 `gateway/internal`，UI显示通用打开失败。

`describe().hasDocument=true`只表示存在provider配置文档，不代表本机有桌面编辑器。正常返回只有 `{opened:true}`，不会将配置路径或全文发给网页。

手机只读元数据验证：当前正常profile的cordis.patch.yml存在，属App UID；rootfs/usr/bin/xdg-open不存在。未读取该文件正文到诊断日志。

对实际官方lib的合成probe9项通过，覆盖headless capability、text intent仍调用xdg-open、BROWSER不影响text intent、hasDocument、成功payload、prepare/open错误分类与取消；没有执行真实用户配置打开或修改官方npm。

## 修复方案与边界

本机模式由App接管设置窗口里的精确“打开配置文件”按钮，在Flutter内展示当前运行配置的只读内容。电脑模式保留网页原行为；不安装桌面组件，不创建通用文件读取RPC，不修改官方npm。

网页只发无路径动作，不接收配置正文。原生根据当前实际运行身份和代次选择normal/safe文档，校验本机origin、token、foreground与phase；读取前后核对代次及路径身份，严格UTF8和大小预算。普通文档和恢复配置分开；不把未知自定义profile回落到正常文件。

查看页内容只在Flutter内存中显示，不落盘、不写日志、不回传JS，不提供保存/导出或复制菜单；打开不是编辑功能。JS trusted-click及闭包nonce是交互限制，不宣称可把同源恶意脚本与页面本身隔离。

实现分别位于App原生的LocalSettingsDocument/RuntimeController/RuntimePlugin和Flutter的local_settings_document/WebView桥，官方npm未修改。当前仅支持已确认的normal/safe home/profile，未知自定义home返回unsupported，不猜读正常文档。读取采用NOFOLLOW和读取前后文件、目录身份核对；这是有限变更探测，不宣称完全消除所有同UID并发路径置换竞态，也没有新增su文件读取能力。

## 已完成回归

- 正式Gradle XML：LocalSettingsDocument12、OfficialRuntime6、FilesOutputs6，共24项通过，0失败/错误/跳过。
- 独立JVM纯读取器12项另通过；使用合成临时文件覆盖UTF8、512KiB边界、正常/恢复分离、缺失不创建文件、内外符号链接和固定位置约束。
- Dart读取/只读页面8项及真实WebView集成4项全部通过，包含电脑页面无通道、正文不回JS、旧票据无读取、导航过期结果废弃和进程停止撤下内容。
- Node配置按钮合成DOM9项通过，8种官方文案精确匹配；脚本点击、disabled、子框架、其他按钮及缺少桥均不抢原事件。
- 分析器中文路径LSP编码崩溃后用既有ASCII别名重跑，5条新代码lint逐项修正，最终No issues。WebView导航测试单独通过但跨测试失败，扩大等待仍失败；定位AssetBundle缓存Future跨FakeAsync页面，改为与现有网页资产一致的cache=false后，完整12项配置回归通过，没有删断言或跳过场景。

## 手机验收状态

准备了只访问新建合成目录的ART探针，首次Java编译因Kotlin方法不声明受检异常失败，修正后D8生成成功但报告旧工具Kotlin metadata警告；推送时手机已离线，探针没有在手机执行。不把这些桌面步骤算作手机文件读取或按钮验收。

手机最近已安装版本仍是11132323。本次完整Lite/maintenance回归259通过、7项既有跳过。正式包构建11140049核验成功：release、debuggable=false、ARM64 AOT，229560599字节，SHA256 `c5c30ea85d76fc068d74f766c39ae9771536493d20cd2755b9513f0d95011bfc`，发布证书摘要与前版相同。原CSS/手机JS/40帧GIF摘要保持不变；新增配置按钮桥与源码逐字节一致，原生readLocalSettingsDocument方法真实进入Dex。

新包未在离线手机覆盖安装，实际点击和恢复模式验收仍待设备连接。修复源码、文案与回归纳入同一私有仓库的快进源码快照；不再次删除仓库，不上传APK、临时探针或私有配置。远端核验比较完整源码树的路径、模式、大小与本地SHA256校验后的Git blob内容标识，不把它冒称二次全文下载。
