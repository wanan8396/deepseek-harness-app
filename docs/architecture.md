# DeepSeek harness 架构

当前产品是唯一的 Android 手机壳 + 官方 DSH 网页构建。功能摘要见 [PROJECT.md](../PROJECT.md)，使用方式见 [当前版本说明](local-web.md)。

## 组成与职责

| 层 | 实现 | 负责内容 |
| --- | --- | --- |
| Android壳 | Flutter + Riverpod | 启动引导、权限、连接记录、WebView、原动画与手机入口 |
| 网页适配 | `app/assets/web/` 的CSS/JS | 安全区、键盘、抽屉、顶部滚动和命名锚浮层定位 |
| 原生运行时 | Kotlin | 安装及更新运行环境、生命周期、日志、Root/PRoot启动 |
| 本机引擎 | Linux环境 + Node.js + 官方DSH | 提供手机本地HTTP网页和引擎能力 |
| 电脑引擎 | 用户指定HTTP(S)网页 | 提供远端聊天、设置及其登录/PIN流程 |

当前聊天页不由Flutter原生聊天模块重画。模型、工具、对话与大部分设置保留官方网页的行为；手机适配不替网页执行菜单动作或保存偏好。

## 运行位置

### 本机

1. Flutter检查本机运行环境状态，首次使用时安装内置运行时。
2. 进入本机页面后发起启动；出错后显示重试入口，而不是无限后台重启。
3. 原生层在普通模式每次启动检查真实 Root 可用性，成功时使用私有挂载空间与 chroot，失败则回退 PRoot；恢复（安全）模式跳过 Root 探测，直接使用 PRoot，见 [DshProcess.kt](../app/android/app/src/main/kotlin/app/dsh/runtime/DshProcess.kt) 的 `safe` 分支。
4. 启动官方 `dsh web --host 127.0.0.1 --port PORT --no-open`，不携带旧引擎补丁参数。
5. WebView打开本机引擎的实际URL和启动令牌。

`PORT` 来自实际运行状态，不把单一默认端口当作连接身份。切后台、旋转和锁屏不等同于退出；真正退出时经既有生命周期停止本机引擎。

### 电脑网页

用户输入HTTP(S)地址、扫码或选连接记录。电脑模式独立于手机本机引擎，不先启动本机环境。目标网页负责远端模型设置、登录和PIN；App负责WebView连接及手机窗口适配。

## 网页适配边界

[web_view_page.dart](../app/lib/ui/web/web_view_page.dart)注入手机样式、脚本与窗口信息。网页主体仍来自当前连接的引擎。

- 原启动GIF和淡出过渡由Flutter启动封面控制。
- 左下鲸鱼操作网页侧栏，右下入口切换本机/电脑。
- CSS处理抽屉、安全区、横竖屏和触摸布局，保留现有主题。
- [dsh_web_phone.js](../app/assets/web/dsh_web_phone.js)根据实际 `position-anchor`、上下文点或tooltip关联定位对应浮层，不按界面语言猜按钮。
- 通用设置的Menu使用设置modal内的精确命名锚；滚动、窗口尺寸和键盘状态变化后，重新计算浮层边界。
- 菜单选择、焦点恢复、关闭与设置保存由官方网页原事件处理器负责。
- 唯一本机配置文档打开动作由无路径WebView桥交给Flutter只读查看页：当前运行URL、令牌、代次与正常/恢复profile经原生校验，内容不回传网页。电脑网页不注册该通道；其他菜单继续由官方网页处理。

## 原生通道与生命周期

Dart通过 `dsh/runtime` 方法通道请求运行时状态、安装、启动、停止、日志等；状态和进度通过事件通道回传。当前本机入口的主要所有者为 [RuntimeController.kt](../app/android/app/src/main/kotlin/app/dsh/runtime/RuntimeController.kt)与对应Dart运行时状态。

Root/PRoot选择不是独立的手动开关，也不由上次保存的偏好代替每次启动的真实检测。启动代次和停止代次约束后台工作；当前手机指南同步使用此生命周期判断，不再伪造旧技能安装请求的token/generation。

## 官方运行时与升级

[官方构建器](../runtime/build-official-runtime.py)读取官方rc.3依赖锁、Linux ARM64/glibc依赖prefix，以及校验过的构建seed，生成独立rootfs归档。纯ELF/裁剪工具位于 [runtime_artifacts.py](../runtime/lib/runtime_artifacts.py)，官方构建器不加载整份旧patched CLI。

运行时清单显式声明：

```json
{
  "engineDistribution": "official-unmodified",
  "capabilities": {
    "legacyBridge": false,
    "enginePatches": false
  }
}
```

官方归档不包含旧bridge、补丁、Direct preload或旧boot cache；保留的官方可执行JS不做引擎内修改。手机样式和WebView适配是App资产，不是官方npm补丁。

升级只处理当前14项精确引擎路径并核对baseId系统身份，保留Ubuntu/Python及用户数据，不把普通更新变成整根rootfs替换。旧空目录事务槽已从输入清单和归档删除；已有清单只证明系统身份，不再授予旧路径写入权。旧指南ID、托管marker和旧进程环境标记不再读取或迁移。

运行时归档、seed、APK与签名不随源码仓库上传。详细输入和已有设备验证范围见 [runtime/README.official.md](../runtime/README.official.md)。

## 验证记录

手机运行时和设置菜单的具体测试、构建及安装结果记录在[最近维护记录](maintenance/round15-local-cleanup-and-settings.md)。页面适配、引擎归档和实际手机运行分别验证，桌面浏览器回归与手机操作记录各自说明覆盖范围。
