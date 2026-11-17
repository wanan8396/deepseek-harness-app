# 当前手机指南同步与旧技能安装通道退休

## 当前生产路径

当前产品仅由原生 `RuntimeController` 的启动 worker 在官方普通模式、Root 所有权恢复之后、引擎进程启动之前调用 `OfficialPhoneSkills.sync`。它读取 `assets/skills/dsh-app-guide/manifest.json`，使用当前技能 ID `deepseek-harness-guide` 维护手机指南。

`ManagedSkillRequest` 与 `ManagedSkillInstaller` 保留严格 UTF-8、文件数量与字节预算、托管标记、路径校验、SKILL.md 最后提交和启动代次检查。已有用户自行接管的技能保持不变；中断只停止后续提交，不宣称回滚已经完成的文件操作。

本机同步不依赖 Flutter engine attachment 或页面 ready，不经 Dart、MethodChannel 或远程 shell 写入。运行代次及 stop 条件由已有启动生命周期提供；Root/PRoot 和 rootfs 更新事务仍使用原有所有权与进程屏障。

## 已退休的旧实现

旧版 `UiSkillAutoInstaller`、Dart 同步文件 helper、远程 shell/提示词安装器、RootGate 保活监听、远程设置里的技能安装按钮已退出源码。

对应私有 `installManagedSkill` / `cancelManagedSkill` 方法、`managedSkillGeneration` 状态字段和仅服务该路径的 native attachment owner / ready gate / queue 已退休。旧回归中仅验证这些退出功能的测试同步删除，不以空实现继续维持失效协议。

旧 UI/plugin/support 教学资产、SDK、同步脚本与旧 ui.json 协议实现均已退休，不再打包或保留成兼容入口。

## 当前托管边界

只同步 `deepseek-harness-guide`，以 `# deepseek-harness:managed` frontmatter 标记判断当前目录是否仍由应用管理，临时文件使用 `.deepseek-harness-tmp`。移除当前标记后，目录视为用户接管，更新不会覆盖它；路径边界和符号链接保护继续保留。

旧技能 ID、旧 marker、三个旧技能删除循环及旧页哈希迁移已删除；没有别名或旧格式 fallback。新版不会读取、迁移、归档或删除用户设备中已有的旧技能目录。

## 验证范围

原生 `OfficialPhoneSkillsTest` 与 `ManagedSkillInstallerTest` 继续验证真实指南资产、用户接管、托管更新、取消和路径边界。Flutter 指南测试验证真实 `dsh-app-guide` 资产目录及中英页面；APK verifier 校验指南字节并拒绝已退休的三组资产回生。

本次清理和 UI 修复的实际命令、结果、已知基线失败与设备验收记录见维护记录，不把源码静态检索当成完整真机验证。
