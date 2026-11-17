# Round 20：手机Purge rc.3安装与日志弹层留白

## 目标与范围

用户要求安装自己GitHub最新Purge到手机，并整理运行环境更新页“查看日志”弹层、去除上方留白。当前工作树不切换、不重置、不提交；桌面DSH和Purge远端源码不改。保留手机数据、主题、40帧启动GIF、官方归档及依赖目录功能。

## Purge安装与来源核对

- 私有仓库`wanan8396/dsh-plugins-backup/main`最新提交`5f0ace5e7ce62eeaf150e699256debf562c446a0`；包版本`0.2.2-rc.3`。
- 从本地适配源码重新计算Git blob/tree，插件树与GitHub的`965b25c7371f31e47683774daed1cde05a9ec3b5`一致；不是仅依靠本地git HEAD（缓存工作树有之前适配改动）。
- 使用归档`dsh-purge-community-0.2.2-rc.3.tgz`，SHA256 `28e43d938752efc3321377876cc9f341d25076b591c21bca9f00cf68bac8ca73`。249份载荷文件逐字节等于对应源码，package.json由npm pack格式归一化但JSON语义完全相同。
- 手机当前官方DSH为rc.3，实际Root chroot。安装归档放私有依赖根的downloads；通过该手机引擎的挂载命名空间执行官方`dsh plugin --profile web add`，未使用仓库历史profile/state覆盖用户配置。
- 修改前把五份profile清单/锁/patch保存在手机私有依赖根backups中。初次指定新pnpm store返回`ERR_PNPM_UNEXPECTED_STORE`；先验证配置文件哈希未变，再沿用手机原pnpm存储重试成功，不强制重装或迁移旧依赖。
- 原两个登录插件依赖声明保留，Purge bundle已选中。没有主动调用Purge apply CLI；APK不内置Purge，插件按手机profile原有启动配置工作。
- 重启最新App后，手机`/dsh-purge/status`返回HTTP 200，`plugin_version=0.2.2-rc.3`、`ready=true`、`ok=true`；运行状态报告65项已应用、0项待处理、83项定义总数，资格qualified。该计数不是宣称83项均有文件改写。

## 日志弹层根因与修改

公共LogView使用reverse列表来尾随终端；短日志贴底，上方产生大片空白。原实现独立几何断言实际失败，首行距列表顶部487.68逻辑像素（期望0–16）。并非此入口的拖柄或重复顶部SafeArea。

仅改日志入口并新增专用[RuntimeLogSheet](../../app/lib/ui/onboarding/runtime_log_sheet.dart)，公共LogView与全局sheet原样：

- 短日志与空态顶对齐，标题/复制/关闭复用原控件与颜色。
- 长行自动换行、可选取、可滚动；初次显示长日志尾部，位于尾部时跟随新增，查看历史时不抢滚动。
- 懒加载混合行高的extent逐帧收敛到真实尾部；用户正在滚动时停止自动跳转。
- 弹层继续约72%高度，局部处理键盘、底部安全区；关闭不停止安装或重置环境。

## 验证

- 新增[10项widget回归](../../app/test/local_web_lite/runtime_log_sheet_test.dart)：短/空/live、320×568/390×844/844×390、深浅色、2倍字、横向/顶部/底部安全区、键盘、旋转、混合行高批次、历史滚动、复制清ANSI、关闭无安装副作用，全部通过。
- Flutter analyze：No issues found；完整Lite/maintenance：270通过、7个既有跳过。
- 正式APK：ARM64 AOT、non-debuggable、包名app.dsh、rc.3、原签名；122份App资产、官方manifest/rootfs与上一包逐字节一致，含原主题/GIF/指南和配置桥。
- 覆盖安装`adb install -r`成功，版本号11141326；firstInstallTime和应用数据inode保持不变。随后App冷启动成功，实际手机Purge状态端点就绪。

## 验证边界

运行环境升级在用户截图后已完成。当前Lite安装完成后没有稳定入口重新打开同一个安装日志弹层，本轮不篡改版本、不重建runtime、不造失败来重现它。日志布局证据为真实Flutter widget回归与合成日志渲染；深浅色截图均实测首行距列表顶部12px、列表紧接标题底部0px。弹层外部原页面遮罩保留约28%，已修的是日志内容区内部的大块留白。手机已安装新代码并验证App/引擎/Purge启动，但不把这一事实替代该弹层的真机几何验收。

## 最终包

- 构建11141326，229637137字节。
- SHA256 `a77a76277560fc376ed4fc064f3f132bebb1adaad9e9fbd43f81dcb8e5c48d9b`。
- 证书SHA256 `d74e8f4d1821cfa9270fd0f6e70b92ad8c14407f42eec3f0d416a2d8571982fb`。

手机安装和插件状态验证完成；源码及GitHub Release未自动上传。
