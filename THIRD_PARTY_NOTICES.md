# 第三方声明（Third-Party Notices）

本文记录当前 Android 手机壳实际保留的第三方源码、素材与原生库。App「开源许可」页由 `app/lib/ui/common/third_party_licenses.dart` 和 `app/lib/ui/settings/font_licenses.dart` 注册本页列出的许可；Flutter/Dart 包的许可证由 Flutter 的 `LicenseRegistry` 收集。发行 APK 前仍需按实际依赖与打包内容复核。

项目自身许可见根目录 `LICENSE`（AGPL-3.0）。品牌与启动素材的权利说明见 [ASSETS.md](ASSETS.md)。官方运行时是独立构建载荷，其运行时许可证保存在运行时归档中，并不由此 Dart 文件代替。

## 复制或改写进源码的代码与图标

### PiPilot（MIT）

- 项目：https://github.com/CikeSeven/pi_pilot
- 版权：Copyright (c) 2026 CikeSeven
- 用途：当前主题、通用弹层与手机壳界面的部分结构和实现。
- 当前保留文件：`app/lib/ui/theme/` 下带有 `Portions derived from PiPilot` 标记的文件，以及 `app/lib/ui/common/app_sheet.dart`、`sheet_navigator.dart`、`status_dot.dart` 等保留组件。
- MIT 完整文本在 App 开源许可页的 PiPilot 条目中。

### DeepSeek Harness（MIT）

- 项目：https://github.com/deepseek-ai/deepseek-harness
- 版权：Copyright (c) 2026 DeepSeek
- 当前保留的派生实现：`app/lib/notify/secret_mask.dart`。
- MIT 完整文本在 App 开源许可页的 DeepSeek Harness 条目中。

### Phosphor Icons（MIT）

- 项目：https://phosphoricons.com/
- 字体：`app/assets/fonts/DshIcons.ttf`，由 `app/tool/make_icon_font.py` 根据保留图标子集生成。
- 版权：Copyright (c) 2023 Phosphor Icons。
- MIT 完整文本在 App 开源许可页的 Phosphor Icons 条目中。

### Material Icons（Apache-2.0）

当前 Android 快捷方式与磁贴图标使用 Google Material Icons 的部分图形。版权归 Google。Apache License 2.0 完整文本在 App 开源许可页的 Material Icons 条目中。

## 原生运行库

| 库 | 当前版本/来源 | 许可证与用途 |
|---|---|---|
| XZ for Java (`org.tukaani:xz`) | 1.10，`app/android/app/build.gradle.kts`；版权 Copyright (C) The XZ for Java authors and contributors | 0BSD；官方运行时归档解压 |
| AndroidX WebKit (`androidx.webkit:webkit`) | 1.15.0，`app/android/app/build.gradle.kts` | Apache-2.0；WebView force-dark 与 renderer/lifecycle 支持 |
| Google ML Kit Common | 18.11.0，应用 Android Gradle 依赖 | Google ML Kit 服务条款；扫码初始化 |
| Google ML Kit Barcode Scanning | `com.google.mlkit:barcode-scanning:17.3.0`（mobile_scanner 7.5.0 的 bundled Android 依赖）；传递组件包括 `com.google.mlkit:barcode-scanning-common:17.0.0`、`com.google.mlkit:vision-common:17.3.0`、`com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1` 与 `com.google.mlkit:common:18.11.0` | Google ML Kit 服务条款；二维码/条码识别。详见 https://developers.google.com/ml-kit/terms 与 https://developers.google.com/ml-kit/android-data-disclosure |

本地扫码仅在用户进入扫码页并触发扫描时使用相机。Google ML Kit SDK 还可能按其条款与数据披露收集服务诊断/使用信息；本文不把这些服务信息与扫码图像内容混为一谈。ML Kit 相关 SDK 许可与隐私条款由 Google 发布，Apache-2.0 示例代码许可不代表 SDK 二进制本身采用 Apache-2.0。

Apache License 2.0、XZ 0BSD 和 Google ML Kit 条款提示均在 App 开源许可页登记。Flutter 插件、AndroidX、相机与平台基础依赖的其余许可证由对应依赖元数据提供。

## 字体

- JetBrains Mono：随 `app/assets/fonts/JetBrainsMono-*.ttf` 分发；版权 Copyright 2020 The JetBrains Mono Project Authors，SIL Open Font License 1.1。许可全文随 APK 在开源许可页显示，来源文件为 `app/assets/fonts/OFL.txt`。

## 删除范围说明

当前 App 不再包含旧 phone-control/Phase、DSHA、DS Bot、DSH Remote、WebRTC/AudioSwitch、Shizuku/libadb、中文 OCR、宠物/伙伴小屋或相关桌面资源；这些功能对应的依赖、代码、资源和许可条目已从当前源码中移除。历史维护记录仅用于追溯，不构成当前运行时依赖说明。
