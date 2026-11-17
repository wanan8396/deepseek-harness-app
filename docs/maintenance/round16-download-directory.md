# 手机下载输出目录更新

日期：2026-11-13。当前分支与索引保留，未重置、提交或推送；本轮在既有未提交源码上继续。

## 已确认根因

用户报告“构建APK后仍生成dsh-go目录”。实查电脑“开发”父目录没有重新生成旧dsh-Go项目；当前手机存在 `/sdcard/Download/DSH-Go`，目录修改时间2026-11-13 22:53。手机已安装构建仍为11131447。

这不是Android从APK名称推导目录：旧 `FilesPlugin` 保存分支及MediaStore RELATIVE_PATH使用硬编码SUBDIR=DSH-Go，`GuestSetup.writeAgentsMd`也把该目录写入本机引擎说明。只读核验当前安装环境中该说明实际存在。Dart产物目录、空原生返回值展示fallback与四组双语提示同样是旧名字。电脑源码目录重命名不会改变这些运行时路径。

另发现默认临时构建junction `dsh-local-web-build`仍指向已不存在的DeepSeek-Assistant旧路径；只移除链接本身并重建指向当前deepseek harness，未复制或搬动源码，也未动同级新项目。

## 修改

- `PhoneStorage.OUTPUT_SUBDIR`集中定义新目录 `DeepSeek-harness`，原生两条保存分支与本机生成说明均使用它。
- `FilesPlugin.listOutputs`保持原权限入口、遍历规则、深度/隐藏文件/全局500上限；读取顺序为新目录、DSH-Go、DSH。旧目录仅就地发现，不mkdir、不迁移、不删用户产物。
- `GuestSetup`继续只更新带管理标记的说明；用户接管文件内容原样保留。
- Dart `phoneOutputDir`和null保存回执fallback更新，原生成功回执仍原样透传，旧目录产物发现保留。
- 中英文四组下载提示更新，运行现有merge/gen-l10n，不手改生成物。
- 仅同步相关导出模块、媒体/FileProvider的下载路径注释，未改相册命名或任何权限根。
- 未修改官方npm、主题/动画、Root自动优先、引擎升级空opt/dsh-go事务槽、签名或依赖锁。

## 实跑回归

### Dart

原聚焦24项通过；新增合同对未修实现实跑4项失败，覆盖新目录常量、ZH、EN和fallback。兼容测试在旧实现也通过。修复后相同聚焦组合33项通过，另诊断导出3个非golden用例通过。原生返回旧目录的成功toast测试特意保留。

merge/gen-l10n与--check通过（62 parts/6204 keys），6个相关Dart文件分析无问题，格式只读检查0改动。

### Native

缓存Kotlin编译器对真实源编译，未下载新工具。新增独立固定目录预期与真实文件遍历测试。未修GuestSetup新路径probe实跑失败；修复后FilesOutputs6、OpenCopies3、LocalWebLiteGuest2共11项通过。

扩大Windows JVM基线39项/14失败；修改后46项/13失败。保留13项既有Windows差异：GuestFiles符号链接路径10项、LegacyDownloads目录碰撞1项、诊断文件rename2项。另原LocalWebLiteGuest里品牌Harness/harness大小写旧预期与当前真实文案冲突，本轮同步当前大小写并明确区分于新路径修复。未skip或改golden制造通过。

Lead最终Flutter分析No issues，maintenance 247 passed、7 skipped。首次正式Gradle聚焦13项中5项listOutputs测试失败：Gradle mock Android jar的Environment.DIRECTORY_DOWNLOADS为空，而独立JVM使用真实android.jar常量，导致fixture路径不一致。没有改预期或跳过；把平台常量保留在实例权限入口，纯遍历函数显式接收downloadsDirectory，测试传独立字面Download。最终Gradle重跑13项全部通过，0失败/错误/跳过；从实际XML统计：FilesOutputs6、OpenCopies3、LocalWebLiteGuest2、GuestAgentsMode路径/接管2。正式APK检查器4项、运行时预检13项另均通过。正式包与手机安装结果见下文。

## 代理问题

用户中途另问VPN：只读观察当时是本机模式，实际node为Root UID0、App UID10351；后一次VPN管理器报告com.follow.clash、活动类型-1。当时不证明某个节点自身故障，也不证明Root一定绕过所有VPN。用户明确“先不管这个代理问题”，本轮不改代理、VPN路由或Root默认选择。

## 验证边界

新产出路径需安装新APK并重启本机引擎后才生效；已在运行的旧会话可能仍保留旧路径上下文。用户自写AGENTS或明确指定旧路径不被强制改写。旧目录中的历史文件保留，因此升级后旧目录仍存在不等于新实现继续默认往里写。

用户确认“现在安装并检查”后，同签名覆盖安装成功，冷启动319ms；dumpsys确认版本0.2.2-rc.2、构建11132323且无DEBUGGABLE。读取实际手机本机生成说明，输出目标已为 `/sdcard/Download/DeepSeek-harness/`。

旧目录的2个文件在升级前后，名称哈希、大小、mtime和inode的整体元数据摘要一致；没有读取文件内容、迁移或删除旧产物。此项是元数据保留核验，不冒称文件内容逐字节校验。

正式APK为ARM64 AOT、release、debuggable=false、229547530字节，SHA256 `7da0c8a66131fed555652740a038129a0c3d5ceec502d9ae7eed41a3fd767dd0`；原发布签名、官方运行时、网页资源和40帧原动画摘要校验通过。当前dist只保留这一最新APK与当前报告/校验清单。

手机真实检查覆盖安装、引擎生成指令更新和旧目录元数据保留；没有通过点击真实聊天中的导出动作创建用户文件，因此原生MediaStore实际写入由保存实现窄diff及桌面合同测试支持，不能把它写成已在手机逐项验收。源码修改仍在本地，未自动提交或推送新仓库。
