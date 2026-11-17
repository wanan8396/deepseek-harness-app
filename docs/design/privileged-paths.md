# 本机运行时的 Root / PRoot 启动路径

当前本机连接启动官方、未修改的 `dsh web`。`RuntimeController.startProcess()` 准备运行环境后创建 `DshProcess`；实际启动路径在每次运行时启动时自动选择，不是权限页中的用户开关。选择只对该次运行代际有效，停止并重新启动后再检测。

## 自动选择

- 普通启动由 `DshProcess.start()` 调用 `RootRuntimeAccess.prepareLaunch(rootfs)`。它经固定的 `su` / `app_process` 管道检查真实 Android UID 0、Root Runtime 协议版本、私有挂载命名空间和 `chroot` 所需能力；探测在该引擎启动中至多执行一次。
- 安全模式不尝试 Root，直接使用 PRoot。
- Root 探测、启动候选或兼容性条件未通过时，取消候选并使用运行时清单中的 PRoot 命令。PRoot 内展示的 UID 0 是兼容模拟身份，不表示 Android 系统授予了真实 Root。

## Root / chroot 路径

Root Runtime 用 `unshare -m` 建立私有挂载命名空间，将必要的 Android 系统目录绑定到运行环境，再对 rootfs 执行 `chroot`。`RootLaunchPlan.fromProot()` 从同一份已组合的 guest 命令中取出 `/usr/bin/env -i` 及其环境，不在该路径执行 PRoot 启动器，也不把 `PROOT_*`、`LD_PRELOAD` 或 `LD_LIBRARY_PATH` 带进 guest。App 注入 Android 系统路径和实际需要的 Android 环境变量。

Root 的 chroot 需要真实文件链接。若安装环境仍含 PRoot `--link2symlink` 产生的合成硬链接，`DshProcess` 会先核对进程清理观察，再用 `L2sMigration` 整理。迁移失败或空间不足时取消 Root 候选并回退 PRoot；不会以不兼容文件状态启动 chroot。

若上次 Root 命名空间的所有权清理标记仍在，启动前会先通过 Root Runtime 恢复。恢复未完成时停止启动并报告清理阻塞，不将不完整的 Root 清理静默转换为 PRoot 启动。

## PRoot 路径与就绪

Root 不可用或上述可回退准备失败时，App 以运行时清单的 `launch.argv` 和 guest 环境创建 PRoot 进程；临时文件位于 App 缓存目录。两种路径运行相同的官方 `dsh web`、端口和启动令牌流程。App 从 DSH 输出中读取有效 token，并确认本机 socket 就绪后才发布运行状态；仅创建进程不算连接成功。

`DshProcess.stop()` 按所选路径收尾：Root 关闭并等待私有命名空间与文件所有权修复结束；PRoot 先停止 guest DSH，再按需结束 PRoot tracees。正在运行时打开权限页、返回前台或刷新连接状态都不会切换 Root/PRoot 身份。

## 当前源码依据

- `RuntimeController.startProcess()`：运行代际、启动准备与 `DshProcess` 接线。
- `DshProcess.start()`：官方运行时门禁、Root 候选、PRoot 回退、令牌就绪与停止路径。
- `RootRuntimeAccess.prepareLaunch()`、`RootLaunchPlan.fromProot()`、`RootNamespaceMain`：UID 探测、命名空间、chroot 命令转换。
- `GuestSetup`：写入环境说明时区分真实 Root/chroot 与 PRoot 模拟身份。
