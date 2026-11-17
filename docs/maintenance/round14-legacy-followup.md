# 旧源码清理第二批：测试宿主、退休提示与官方构建解耦

日期：2026-11-13。基线 HEAD 为 `d98afb64698013908dd99a74e3eba1c7e0d81b5d`，在上一轮未提交工作树上继续，未 reset/stash/提交/推送。上一版已安装正式包 `11131252` 未覆盖，本记录不是新APK发布说明。

## 1. 测试专用插件宿主移出生产 lib

生产 import/export/part 图核对：迁前852个节点，从 main 可达842；旧内存宿主无生产入边，真实消费者为10个测试，没有动态注册或反射消费者。生产 provider 仅注册真实 bridge/settings API。

将旧 `plugin_config_memory.dart` 迁至 `app/test/plugin_config/memory_api.dart`，只改头注释和2条依赖 import，10个测试各替换1条 import。正文9084字节不变，SHA-256 `d8a22705e8b424af19035d27ee1fdd902a5558a73af122339eac798fbe9af1f5`。全部测试实现保留，退出生产目录而非删掉验证能力。

- 同15个非golden测试：迁前184 passed/1 failed，迁后185 passed。
- 迁前失败是bridge teardown 的 HTTP Connection closed while receiving data，未改该无关问题，迁后单次通过不代表修复了它。
- test-only边界断言在迁前实际失败（旧路径存在），迁后通过；保护生产源码不反向导入测试宿主。
- 首次迁移采用相对lib导入触发Dart URI身份不同的编译失败，改用2条标准package imports后通过；实现正文未改。
- 迁后生产节点851，main可达仍842。Golden未更新。

## 2. 已退休技能的残余提示退出

旧 UI/plugin/support 技能在上一轮已实删，安装入口已退出；本批清除 full 生成环境说明里仍要求加载这些不存在技能的指令，以及诊断注释残留。保留原生界面事实、插件协议、当前Lite说明、指南、许可证和原Download兼容路径。

新增真实生成并读文件的回归覆盖 proot/direct 组合，旧三ID负向断言与保留事实正向断言一起验证。Native聚焦27项全部通过：Root16、指南同步8、环境说明3。两个既有Windows诊断文件rename失败测试未修改，也未冒称本批已修复。

## 3. 官方构建器不再加载旧 patched CLI

共享 `ABI`、`EM_NAMES`、完整 `Elf`、`elf_summary`、`dsh_drop_reason` 迁入纯 `runtime/lib/runtime_artifacts.py`，5个定义AST与原HEAD一致，依赖只有struct。官方构建器仅加载纯模块；旧rtbuild重新导出相同符号而不是复制实现，保留`python -I`和动态文件加载消费者。

旧build-runtime配方指纹加入新helper hash，原输入列表完整保留，避免后续helper改动遗漏版本身份。

- 官方5项、artifact7项、升级3项、inventory2项，共17项通过。
- Lead独立重跑官方/artifact/升级15项全部通过。
- artifact测试独立构造ELF32/64和路径oracle；实际旧CLI执行patch-dynstr/elf-info；临时checkout完全无rtbuild/bridge/patches，官方CLI从合成小seed实际构建两次并逐文件检验归档字节、权限、符号链接、JNI、base/upgrade、hash与确定性。
- 坏基线恢复旧loader时集成测试失败；ELF机型故障触发5failure；prune恒None触发36subtest failures；恢复后7/7。
- 旧全Python基线24项含4failure/7error/1skip，来自Windows缺Unix shell、GBK和CRLF fixture；范围外未改，未计作通过。
- SDK sync-bridge及退休skill只读检查均通过。

## 4. 后续集成核验

删除 `UiConfigState.skillMissing` 转运、`needsSkill` getter和零消费者的 `uiLocalEngineRunningProvider`。源端 `UiConfigAbsent.skillMissing` 及其寻址逻辑保留，noSkill→availability映射不变，不把移除安装提示当成移除配置读取。

从双语shell ARB输入删除9个无消费者的安装提示键及对应元数据；用既有merge与Flutter gen-l10n重新生成，不手改生成物。l10n检查62 parts/6204 keys、指南26 files均通过。

state/remote/local三文件前后均34 passed/7 failed；7项相同的Windows本地inotify与real wiring5秒超时，源端和相关support文件字节未改。新增remote widgets前后均3 passed，断言实际SettingsTile/key与配置恢复，不依赖被删除的文案。未改超时、未删失败测试或golden基线。首次漏设字体环境导致加载失败，后续设置现有字体目录；追加单列命令使用该CLI不支持的--exclude-name而未执行测试，均未计为通过。

最终Lead统一执行：`flutter analyze --no-pub` exit0，No issues found；`flutter test --no-pub --dart-define=DSH_LOCAL_WEB_LITE=true test/local_web_lite test/maintenance` exit0，247 passed/7 skipped。最后diff检查通过，依赖锁与官方运行时锁没有变化。

## 仍保留的旧栈

旧bridge/patches/CLI、full原生聊天、phone/pets/companion、SDK与其CI仍有真实消费者。本批分离的是官方构建对旧CLI的加载依赖，不等于删掉旧补丁链。系统seed、精确升级路径、旧技能退休名单和用户接管标识继续保留。

当前主题与树枝按钮修复没有在本批改动；官方npm与锁文件未改，未操作手机或清用户数据。新会话故障仍为单独未闭环问题。
