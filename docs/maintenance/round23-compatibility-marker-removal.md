# round23：删除旧兼容标记和对应实现

更新：2026-11-16。用户在已安装 round22 包后，明确要求此前保留的兼容标记也清理。本轮是对该要求的后续源码、生成物、运行时包装和 Release APK 修改，不把 round22 的已安装包当作当前结果。

基线仍为 `latest-official-rc2-source` / `d98afb64698013908dd99a74e3eba1c7e0d81b5d` 的共享 dirty 工作树，没有切分支、stash/reset、提交或推送。原 `remote-baseline` stash 保留。

## 实际删除与当前行为

| 旧兼容面 | 本轮处理 | 当前边界 |
|---|---|---|
| 旧指南 ID / marker / 临时文件后缀 | 从生产、生成器、双语指南和生成资产移除旧 ID 与 marker；只同步 `deepseek-harness-guide`，当前 marker 为 `# deepseek-harness:managed`、临时后缀 `.deepseek-harness-tmp` | 当前 marker 用于区分应用托管和用户接管，不接受旧 alias |
| 旧技能目录和旧页迁移 | 真删三组旧技能的退休循环、归档识别、6 页哈希迁移、对应压缩夹具和专属测试，Result 不再返回退休计数 | 不读取、迁移、归档或删除设备旧指南目录；当前取消/原子写入/用户接管/符号链接保护保留 |
| 旧进程环境标记 | 删除 `DSH_GO_RUNTIME_ROOT` 的读取、record 字段、reader environ 接口及其专属观测失败分支 | 仅同 UID、rootfs argv/cwd、PID 起始时间、已捕获身份和后代关系证明归属；只靠旧 marker 的 detached 进程不再认领 |
| 旧会话偏好 | 删除 `active_host` 和 `last_session_id` 恢复 fallback、旧值删除动作、`companion_sessions` 隐藏绑定与异步等待门 | 仅当前 `last_session_selection` 绑定读写；旧偏好值原样留在存储但不再影响当前行为，旧伙伴会话按普通列表规则可见 |
| 旧远端身份 | 删除 HostKind、HostRef.ssh/relay 和回退本机的解析分支 | 当前 local JSON 继续工作；缺失/畸形/远端 host 的通知动作、tap、chat shortcut 直接丢弃，不转成本机会话 |
| 旧重置 UI 保存路径 | 删除 `.dsh/dsh-go` 特例与 `uiAndSkills` wire；Dart/Kotlin 改为 `skills` | 只保留当前两个技能根与另一个 settings 选项，不迁移或清除真实用户值 |
| 旧升级空槽 | 从 incoming EngineUpgrade 清单和 rootfs 归档移除旧空目录，路径由 15 收敛到当前 14 项 | incoming 清单严格授予写入范围；installed manifest 只证明 baseId/Ubuntu/ABI/OS 身份，其旧列表不进入事务；无 descriptor 的旧系统不再自动收养，也不回退整根重装 |
| 旧 L2S 临时名字 | `.dsh-go-l2s-*` 改为 `.dsh-l2s-*`，旧 temp 格式不再识别 | PRoot `.l2s` 是当前 Root/PRoot 转换需求，算法和数据保护保留 |
| 其他旧产品文字 | 更新诊断分享标题、英文后台说明、内部 unreadable URI、生成 guest 说明和过时注释 | 许可与上游来源署名保留；未用批量替换改官方代码 |

## 官方引擎与运行时包装

新 runtimeVersion：`r17-official-dsh0.2.2-rc.3-node24.22.1-c7767e0f725d`。

使用既有、校验过的系统构建 seed 和 Linux ARM64/glibc prefix，在独立输出重建。与此前 r16 归档逐成员比较：

- 删除项恰为一个旧空目录；修改项恰为 `etc/dsh-app/runtime.json`。
- **37,129 项归档条目内容/类型/权限/链接保持一致**。
- **514 个保留的官方包文件哈希完全一致**；系统可执行文件和全部 JNI 字节不变。
- baseId 不变，Ubuntu/Python/用户系统不被新版引擎事务接管；新 archive SHA-256 为 `dfee8744aed0e75c420a39cd8ed78b0d6262ca92e270d7bf4f11982d25c2056c`。
- 已将核验后的 r17 包装归档作为当前 `runtime/out/arm64-v8a` 输入；原 r16 归档另留本地证据，不覆盖 seed 或旧 APK。

构建器仍知道如何从不可变历史 seed **排除**旧目录和旧元数据，这是构建过滤规则，不是新包中的运行兼容槽。历史记录、负例和种子不做字面名字清空；主题文件中那一处旧项目注释按主题哈希冻结规则保持，非运行兼容代码。

## 验证

| 检查 | 本轮结果 |
|---|---|
| `dart analyze .` | exit 0，No issues found |
| 当前壳/状态/通知/链接/快捷方式/runtime/onboarding/web 聚焦测试 | **423 通过、20 跳过，exit 0** |
| 原生指南/ownership/current upgrade compatibility/carried home/Root/current native contract | **53 通过、0 失败/跳过，exit 0** |
| Python 官方 runtime 回归 | **16 通过**，包括独立路径清单、seed 只读/旧slot不转发和真实双次 archive 构建 |
| l10n / guide 生成检查 | 当前 19 分区/247键；26 源指南检查通过；56 项 l10n、28 项 guide 测试通过 |
| 工具回归 | 34 项中 30 通过、4 跳过（bash dry-run） |
| 当前真实载荷预检 | exit 0 |
| Release 构建与签名校验 | exit 0，见下一节 |

首轮 Flutter 选择恢复测试和 ownership partial-read 测试各有一处陈旧测试假设：一个在断言前主动读取了 provider，另一个还假定失去 cwd 后旧 marker 可证明归属。现已按实际调用/观测边界修正，保留 known starttime 和不确定状态断言，复跑通过。

扩展原生测试首跑 106 项/17 失败，其中 ownership 陈旧假设已修；其余 16 项涉及此前已记录的 Windows 目录 fsync/Unix 属性、权限故障注入和直接 ManagedSkillInstaller symlink 用例，未宣称全量原生通过。完整测试结果与局限见 round22 及本轮本地日志；没有删除失败用例或取消用户资料边界断言来凑绿。当前 OfficialPhoneSkills 调用入口仍逐段拒绝符号链接，其当前回归通过。

## 新正式包

- 路径：`.harness-tmp-current/compat-removal/release/deepseek-harness-0.2.2-rc.3-release.apk`
- `app.dsh` / `0.2.2-rc.3` / build **11160129** / arm64-v8a / Release / 非 debuggable / Dart AOT。
- **198,565,284 B**；SHA-256：`f7d6b9ac4f170d3a44e608e4c8348ab3c6c79a15fc6802f66fd28896132d0f57`。
- 证书 SHA-256：`d74e8f4d1821cfa9270fd0f6e70b92ad8c14407f42eec3f0d416a2d8571982fb`，与原正式包一致，v2 验签通过。
- 解析 4582 个 DEX 类定义，结合 R8 映射的 5233 个原始类条目，退休功能类检查无命中；11 个 native 库保持当前扫码/WebView/Root-PRoot需要的集合。
- 22 份主题源码和 8 个品牌文件保护哈希一致，原 GIF SHA-256 不变。所有指南资产逐字节与当前输入一致。

证据：`.harness-tmp-current/compat-removal/` 下的 `guide-report.md`、`reset-report.md`、`state-process-report.md`、`runtime-verification.json`，以及 `release/` 下的签名、DEX、标记检查 JSON 和对应 mapping。它们是本地证据，不纳入源码提交。

## 设备与数据状态

本轮没有安装到手机、启动设备应用或进入设备用户数据目录。手机此前安装的是 round22 build **11152221**，这次的 **11160129** 包尚未安装。删除运行兼容代码不等于抹除设备旧目录、旧偏好、进程或真实对话；本轮不作这种宣称。新包也不再携带“下次启动清旧目录”的迁移逻辑。

用户随后若要求安装，应使用同签名覆盖安装；手机本机运行环境将按当前 14 项 incoming 事务升级为 r17，真机 Root/PRoot 与旧事务中断状态需要独立验收。主题、GIF、官方可执行引擎、签名和原交付包保持，本轮未 commit/push。

### 后续安装记录

2026-11-16 01:46（Asia/Shanghai），用户另行明确要求安装后，已使用 `adb install -r` 覆盖安装同签名 build **11160129**，安装返回 Success；安装前后包管理器构建号从 11152221 变为 11160129，首次安装时间保留。安装包 SHA-256 与本记录一致。未卸载、未清空应用数据、未启动应用验收，也未确认手机实际 rootfs 已升级为 r17。此前“尚未安装”是本轮源码完成时的历史状态。
