# DeepSeek harness

探索未至之境。

DeepSeek harness 是面向 Android 的 DSH 网页手机壳。Flutter 负责启动、连接、权限和手机窗口适配；聊天、模型、工具和对话设置由连接到的官方 DSH 网页提供。

## 当前版本

- 应用名：DeepSeek harness。
- Android 包名：`app.dsh`。
- 当前内置引擎：未修改的官方 `@deepseek-ai/dsh@0.2.2-rc.3`。
- 当前产品只有这一个 Android 手机壳构建。
- 最近确认覆盖安装的正式版为 `0.2.2-rc.3`，构建号 `11141326`，ARM64，已在手机启动。
- 本包保留配置只读查看及手机私有依赖目录，修复安装日志弹层短日志贴底导致的顶部留白；日志布局已通过真实widget回归，安装完成后的手机同入口未强制重现。
- 手机正常web profile已安装GitHub最新Purge rc.3，重启后状态接口HTTP 200、ready=true；不随APK内置，也不修改桌面安装。
- 新源码仓库：`wanan8396/deepseek-harness-source`，私有。APK并未随源码自动发布。

## 实际提供的功能

### 在手机本机运行

首次准备内置 Linux 运行环境，然后启动 DSH 并在 WebView 中打开它的网页。每次启动自动检查真实 Root：Root 可用时使用独立挂载空间中的 chroot，失败时回退 PRoot。界面没有需要手动开启的 Root 模式。

本机运行的是引擎及其文件、命令环境。模型请求仍发往网页配置的服务商，不代表手机离线运行大模型。

### 连接电脑上的 DSH

支持输入 HTTP(S) 地址、扫描连接二维码，以及使用已保存的连接记录。电脑模式与手机本机引擎分开，电脑端的登录、PIN和模型配置由所连接的网页负责。

### 手机界面

- 保留现有主题、鲸鱼图标及原启动动画。
- 左下鲸鱼打开网页对话和工作区侧栏。
- 右下入口切换本机与电脑连接。
- 处理系统安全区、键盘避让、横竖屏及触摸滚动。
- 对官方网页的命名锚菜单进行手机定位，包括账户、上下文、权限、缓存和通用设置菜单；官方网页仍负责菜单动作和设置保存。
- 首次权限集中在同一页；检测结果与厂商设置的用户确认分开显示。
- 新产出默认保存到手机的 `Download/DeepSeek-harness`；旧下载目录中的文件继续就地读取，升级不迁移或删除历史文件。
- 本机设置里的“打开配置文件”接入App内只读查看页；当前运行的正常或恢复配置分别读取，不导出或写回文件，电脑模式保持网页原行为。
- 本机额外工具、依赖下载和编译缓存集中在 `/root/.local/share/deepseek-harness/dependencies`，启动准备目录与guest环境；包内指南及托管说明约定用途，系统包与旧依赖不自动搬动。
- 同步当前手机使用指南，并清退三组已退休的旧托管技能目录；保留用户自行接管的技能。

## 源码位置

| 路径 | 用途 |
| --- | --- |
| `app/lib/ui/web/` | WebView、启动动画、手机连接与底部入口 |
| `app/lib/ui/onboarding/` | 首次运行引导 |
| `app/lib/ui/access/` | 权限界面 |
| `app/assets/web/` | 手机网页样式与脚本适配 |
| `app/android/app/src/main/kotlin/app/dsh/runtime/` | 运行时安装、启动和指南同步 |
| `app/android/app/src/main/kotlin/app/dsh/rootruntime/` | Root启动实现 |
| `runtime/build-official-runtime.py` | 官方运行时组装 |
| `runtime/locks/dsh-0.2.2-rc.3/` | 官方版本与依赖锁 |
| `tooling/build-local-web-apk.ps1` | Windows手机壳构建入口 |
| `tooling/build-local-web-apk.sh` | Linux手机壳构建入口 |

## 构建与验证入口

先准备 Flutter、JDK、Android SDK/NDK、Python/Pillow和真实运行时资产。源码仓库不包含发布私钥、本机私有配置、运行时产物或构建缓存；仅下载源码不会自动具备完整发布环境。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

```bash
bash tooling/build-local-web-apk.sh -f arm64
```

开发检查见 [CONTRIBUTING.md](CONTRIBUTING.md)，实际运行时输入见 [官方运行时说明](runtime/README.official.md)，具体使用见 [当前手机壳说明](docs/local-web.md)。

## 来源与许可

保留原项目及第三方组件署名、许可证和素材条款。参见 [LICENSE](LICENSE)、[第三方声明](THIRD_PARTY_NOTICES.md)、[来源说明](docs/ATTRIBUTION.md)和[素材条款](ASSETS.md)。
