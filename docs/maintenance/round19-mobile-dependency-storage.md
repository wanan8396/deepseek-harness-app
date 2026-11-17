# Round 19：安装包内统一依赖、下载与编译目录

## 用户目标与选择

用户要求把下载的编译依赖目录规范写进手机版安装包，并实际改为集中位置。选择App私有Ubuntu内：

```text
/root/.local/share/deepseek-harness/dependencies
```

位置位于15项引擎替换路径之外，Root/PRoot及正常/恢复profile共用，具备Linux文件权限、可执行和链接语义；不使用外部Download存储承载工具链。本轮没有迁移旧工具或真实用户数据，也未改桌面DSH、Purge或上传源码。

## 实现

- [GuestDependencies](../../app/android/app/src/main/kotlin/app/dsh/runtime/GuestDependencies.kt)在启动前创建bin/npm/python/venvs/downloads/sources/build/tmp/cache/cargo/rustup/go等真实子目录。
- rootfs叶、直接runtime父及内部组件NOFOLLOW检查；允许更上层Android系统alias，避免误挡`/data/user/0`。README严格首行marker管理，64KiB读取上限，用户接管与超限文件原样保留；同内容不写，更新原子替换。
- [启动接入](../../app/android/app/src/main/kotlin/app/dsh/runtime/RuntimeController.kt#L472-L519)在旧Root归属恢复后准备目录，正常/恢复环境组装后设置guest变量。唯一`{GUEST_ENV}`检查确保变量在`/usr/bin/env -i`后，Android宿主PROOT缓存路径不变。
- 配置DSH_DEPENDENCY_ROOT、npm prefix/cache/node-gyp、PYTHONUSERBASE、pip cache、Cargo/Rustup、Go、ccache及guest TMPDIR；既有PATH优先，工具bin追加去重。HOME/DSH_HOME、宿主PROOT变量、动态库路径不由本模块新增或更换。
- 正常托管AGENTS、官方恢复briefing及根目录README含同一目录规范；自定义正常AGENTS原字节保留。[包内双语指南](../guide/zh/03-engine-hosts.md#L20-L78)真实生成，仅改两份03页面，不增加按钮或改主题。
- [Root命令规划](../../app/android/app/src/main/kotlin/app/dsh/rootruntime/RootLaunchPlan.kt)保持带受管依赖标记的最后PATH可访问Android系统命令；未标记的显式重复PATH契约不变。
- apt系统包和项目标准node_modules仍按原包管理器契约管理，旧安装不自动搬迁。

## 验证与发现处理

- 初次完整Flutter analyze定位一个新增测试插值lint，已定点修正；最终No issues found。
- Flutter maintenance：260通过，7个既有跳过。
- 原生目录/代理/配置文档/官方标记/输出/Root规划：63项，62通过、1个Windows POSIX模式assumption skip、0失败。核对真实JUnit XML。
- 全类回归初次暴露既有diagnostics的`File.renameTo`在Windows覆盖现有目标失败。改为同目录Files.move ATOMIC_MOVE/REPLACE_EXISTING，复跑所有原断言通过；没有删除或豁免两个快照替换测试。
- 指南生成与--check：26份；25项Python指南单测通过。旧指南不含统一根的独立断言触发预期失败。
- 独立APK对照上一rc3包：120份共用Flutter资产字节一致，仅中英文03指南变化；主题、40帧GIF、配置查看桥、官方运行时manifest/rootfs、原生系统库与许可证保持原样。DEX内存在目录、环境及启动模板检查字符串，签名与AOT正式标记验证通过。

## 交付

- `app.dsh` / ARM64 AOT / Release / `0.2.2-rc.3`。
- 新构建号`11140337`，大小229637145字节。
- SHA256：`45ac6a49007596f31a6dca9f988472f75aac966c617688c8f083d1d590ac6ee6`。
- 原证书SHA256：`d74e8f4d1821cfa9270fd0f6e70b92ad8c14407f42eec3f0d416a2d8571982fb`。
- 本次ADB无设备，没有覆盖安装或清数据。目录在新版App本机启动时创建；手机真实Root/PRoot、编译及权限效果仍待连接验收。

正式APK与包内目录核验报告在本地dist；依赖规范不是搬移已经存在的系统工具，卸载/清数据/明确重置仍影响私有目录。
