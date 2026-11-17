# DeepSeek Harness · Android

[English](README.en.md)

在 Android 手机上运行 DeepSeek Harness，或打开电脑上已有的 DSH 网页。以原网页作为对话界面，保留文件、命令和普通聊天工具，减少重复的原生设置。

- **应用名：** DeepSeek harness
- **包名：** `app.dsh`
- **仓库：** [wanan8396/deepseek-harness-source](https://github.com/wanan8396/deepseek-harness-source)（私有）
- **版本规则：** 显示版本跟随内置 DSH；Android 构建号独立递增。

## 当前源码状态

当前源码采用官方 `@deepseek-ai/dsh@0.2.2-rc.3` 网页。同签名 ARM64 Release 已构建核验并覆盖安装；保留配置只读查看、手机依赖目录、原主题与原始启动 GIF。当前壳聚焦回归 423 项通过、20 项跳过，原生关键链 53 项通过；完整套件仍有已记录的图像基准、图标规范和 Windows 文件系统相关失败，不宣称全量通过或真机功能已全部验收。详情见[本轮清理记录](docs/maintenance/round23-compatibility-marker-removal.md)。用户报告的“新会话入口未进入新会话”尚未完成复验，不标记为已修复。实际功能与源码入口见 [PROJECT.md](PROJECT.md)。

## 下载与安装

新仓库目前上传源码，不自动发布 APK。后续正式附件放在 [Releases](https://github.com/wanan8396/deepseek-harness-source/releases)，以实际发布内容为准。私有仓库的源码和附件需要使用有访问权限的 GitHub 账号登录。

正式包使用发布证书签名。升级时保持包名、签名一致；旧 debug 测试包若使用另一证书，会出现签名冲突。保留数据时不要直接卸载旧包。

**发行状态以每个 Release 的说明和附件为准。** 当前源码每次本机启动自动检测真实 UID 0，条件满足优先 Root，否则回退 PRoot；这不是用户可选开关，权限页也没有 Root 开关。详见[本机与 Root 说明](docs/local-web.md#root-默认启动与-proot-回退)。

## 两种使用方式

### 本机

- 手机运行内置 Ubuntu、Node.js 和 DSH，直接显示该引擎的网页。
- 进入本机模式自动启动；真正退出 App 后停止引擎。
- 切后台、锁屏和旋转不当作退出。
- 模型请求仍由网页中配置的提供商处理，本机运行不等于模型离线推理。

### 电脑网页

- 输入电脑 DSH 的 HTTP(S) 地址，或扫描其局域网连接二维码。
- 保留手动地址、扫码和连接记录。
- PIN 与登录状态由目标网页管理，App 不另做一套登录流程。
- 电脑模式不要求手机本机引擎先启动。

## 界面与权限

- **左下鲸鱼：** 打开网页的对话与工作区；侧栏展开时保持可达，键盘和真正阻塞弹窗按需暂时收起。
- **右下本机/电脑：** 选择运行位置；模型、主题、语言和对话设置留在网页。
- 顶部一排支持横向触控滚动，菜单独立展开，浏览器标签关闭按钮居中。
- 保留原网页主题，以及原始循环启动动画和“探索未至之境”标语。
- 新产出默认保存在 `Download/DeepSeek-harness`，历史下载目录中的文件保留原位并继续支持读取。
- 本机“打开配置文件”由App内只读查看页承接，不导出或写回配置；电脑模式保持网页原动作。
- 本机额外工具、下载和编译缓存使用私有依赖根目录，启动时配置；用途规范随包放入指南和托管说明，旧依赖保留原位。
- 首次权限集中一页，逐项开启，底部可继续；返回 App 只刷新状态，不连弹下一项。
- 文件、通知、电池权限显示实际检测结果；厂商后台项以“查看设置 / 我已开启”记录用户确认，与系统检测区分。

完整操作、本机启动方式与构建说明见[当前版本说明](docs/local-web.md)。

## 构建

准备匹配 ABI 的真实运行时、Flutter、JDK、Android SDK/NDK 和 Python/Pillow，再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

Linux 构建入口：

```sh
bash tooling/build-local-web-apk.sh -f arm64
```

正式签名配置和私钥仅保存在本机，不提交到仓库。构建环境、运行时准备及签名要求见[详细构建说明](docs/local-web.md#构建)。

## 文档与源码范围

- [实际功能与源码入口](PROJECT.md)
- [当前架构](docs/architecture.md)
- [当前版本说明](docs/local-web.md)
- [开发与验证约定](CONTRIBUTING.md)
- [依赖与工具目录规范](DEPENDENCIES.md)
- [问题报告](SECURITY.md)
- 本仓库上传当前源码、构建脚本、依赖锁、必要素材与许可证；不上传 APK、rootfs/JNI 运行时归档、签名密钥、设备配置或本机插件备份。额外插件由目标引擎自行安装，不内置到 App。

## 来源与许可

本修改版由 **wanan8396** 维护。保留原项目作者和第三方组件的版权、署名与许可证，详见[来源说明](docs/ATTRIBUTION.md)、[AGPL-3.0](LICENSE)、[第三方声明](THIRD_PARTY_NOTICES.md)和[素材使用条款](ASSETS.md)。旧 SDK 与示例已删除，仍分发的第三方内容继续遵循其原许可。

本项目是社区修改版，不代表 DeepSeek 官方；相关名称与商标归各自权利人所有。
