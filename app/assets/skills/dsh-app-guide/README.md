# DeepSeek harness 使用说明 · User guide

> DeepSeek harness 0.2.2-rc.3

## 适用范围

本说明适用于搭载官方 DeepSeek harness 0.2.2-rc.3 运行时的 Android 手机壳。首页就是官方网页；手机壳负责本机启动、手机布局、系统权限以及电脑网页连接。模型、对话、插件和自动化任务由当前网页所连接的引擎管理。

适用版本以源码中官方依赖锁的 `@deepseek-ai/dsh` 精确版本为准；随包运行时清单的 `dshVersion` 必须与之相同，不取旧 App 工程的版本号。电脑网页可能运行其他版本，按钮与可用项目以那台电脑实际提供的页面为准。

## 中文目录

1. [对话](zh/01-chat.md)：新建、选择、发送、三点与长按菜单，归档和删除的影响
2. [登录与模型](zh/02-models.md)：官方设置、账号、providers、API Key、token 与 cookie
3. [本机运行环境](zh/03-engine-hosts.md)：普通模式自动 Root 检测、恢复模式 PRoot、profile 与普通升级的数据保留
4. [系统权限](zh/04-permissions.md)：文件、通知与后台权限；Root 由启动流程检测
5. [本机与电脑网页](zh/05-web.md)：HTTP/HTTPS 地址、扫码、预览确认和连接记录
6. [常驻入口与侧栏](zh/06-navigation.md)：底部鲸鱼、键盘、遮挡和返回
7. [分享与草稿](zh/07-sharing.md)：接收文字和附件、检查后手动发送
8. [官方网页插件](zh/08-plugins.md)：当前引擎的插件、设置与重启
9. [外观与启动画面](zh/09-appearance.md)：网页主题、手机壳配色和 40 帧 GIF
10. [设置与使用说明](zh/10-settings.md)：本机、电脑、系统权限与网页设置的区别
11. [常见问题](zh/11-faq.md)：启动重试、后台、浮层、登录和菜单差异
12. [自动化任务](zh/12-automation.md)：创建、时区、执行位置、暂停与删除

## Applies to

This guide covers the Android phone shell bundled with the official DeepSeek harness 0.2.2-rc.3 runtime. Home is the official web interface. The shell handles local startup, phone layout, system permissions and computer webpage connections. The engine behind the current webpage owns models, conversations, plugins and automation tasks.

The supported version is the exact `@deepseek-ai/dsh` version in the source repository's official dependency lock. The bundled runtime manifest's `dshVersion` must match it; the old app project's version field is not used. A computer may run another version; its actual webpage determines available controls.

## English contents

1. [Conversations](en/01-chat.md): create, select, send, three-dot and long-press menus, archive and deletion effects
2. [Sign-in and models](en/02-models.md): official settings, account, providers, API keys, tokens and cookies
3. [Local runtime](en/03-engine-hosts.md): normal-mode Root detection, recovery-mode PRoot, profiles and data-preserving ordinary upgrades
4. [System permissions](en/04-permissions.md): files, notifications and background permissions; Root detection belongs to startup
5. [Phone and computer webpages](en/05-web.md): HTTP/HTTPS addresses, QR scanning, preview confirmation and recent connections
6. [Persistent controls and sidebar](en/06-navigation.md): bottom whale, keyboard, overlays and Back
7. [Sharing and drafts](en/07-sharing.md): incoming text and attachments, review and manual sending
8. [Official web plugins](en/08-plugins.md): current-engine plugins, settings and restarts
9. [Appearance and startup](en/09-appearance.md): web theme, shell colors and the 40-frame GIF
10. [Settings and user guide](en/10-settings.md): phone, computer, system permissions and web settings
11. [Troubleshooting](en/11-faq.md): startup retry, background operation, overlays, login and menu differences
12. [Automation tasks](en/12-automation.md): creation, time zone, delivery location, pause and deletion

本说明只描述当前产品入口；请通过本目录打开当前页面。

This guide describes current product entry points; use this index to open the current pages.

## 指南安装标识 · Guide identity

当前指南安装为 `deepseek-harness-guide`，托管标记为 `# deepseek-harness:managed`。删除该标记后，当前指南目录由用户接管，App 不再覆盖。程序不识别旧指南标识或旧标记，不读取、迁移或清理旧指南目录；更新安装包不等于设备上的历史目录已删除。

The guide is installed as `deepseek-harness-guide` with the `# deepseek-harness:managed` marker. Removing this marker makes the current guide user-owned and stops bundled overwrites. Previous guide identities and markers are not recognized; their directories are not read, migrated or cleaned. Updating the APK does not establish that historical device directories have been deleted.
