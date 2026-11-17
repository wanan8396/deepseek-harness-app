# 本机运行环境

选择本机后，手机壳启动随包的官方 DeepSeek harness 运行时，再在 App 内显示它提供的网页。首次使用按页面安装运行环境；启动与网页首次加载期间会显示鲸鱼动图。

## Root 优先与 PRoot 回退

- 普通模式每次启动本机引擎时自动检测一次真实 Android Root，取得 UID 0 且启动条件满足时优先使用 Root；权限页没有 Root 开关或手动授权行。恢复模式跳过 Root 探测，使用 PRoot。
- 设备的 Root 管理器可能在首次检测时显示授权请求。未授予、设备没有可用 Root 或启动条件不满足时，自动使用 PRoot；普通使用不需要先给手机 Root。
- PRoot 的 Linux 环境中显示的 `root` 或 UID 0 是模拟身份，不代表取得 Android 宿主 Root。
- 启动后运行方式保持固定；返回权限页或切回 App 不会反复检测，也不会中途切换正在运行的对话。下次本机启动重新检测。

Root 的权限更大，运行命令前仍需核对目标文件与动作。Root 授权不是手机自动点按入口，相关系统项目见 [权限](04-permissions.md)。

## profile 与数据位置

官方引擎使用自己的 HOME/profile 保存账号配置、providers、插件与对话数据；工作区文件保存在对应目录。切换到电脑后使用电脑自己的 HOME/profile，不会自动同步手机记录。

恢复用途的隔离 profile 与正常 profile 不是同一套配置。若页面或维护流程启用了隔离环境，原列表未出现不等于原数据被删除；回到正常配置后再核实。不要为了找回列表而直接清空运行环境。

## 依赖、下载与编译目录

本机启动自动准备统一目录 `/root/.local/share/deepseek-harness/dependencies`，并在手机 Linux 环境中设置 `$DSH_DEPENDENCY_ROOT`。正常与恢复 profile、Root 与 PRoot 共用同一持久私有目录；配置隔离不另建工具副本。电脑网页不使用手机的这些环境变量。这是目录说明，不新增按钮。

以下子目录都位于 `$DSH_DEPENDENCY_ROOT` 内：

| 子目录 | 用途与环境变量 |
| --- | --- |
| `bin/` | 手动放置的命令行工具 |
| `npm/` | 全局用户 Node 工具；`NPM_CONFIG_PREFIX` 指向这里，可执行入口在 `npm/bin` |
| `python/` | `PYTHONUSERBASE`；使用 `python3 -m pip install --user` 安装用户包 |
| `venvs/` | 独立 Python 环境；优先使用 venv，避免不同工具的包相互影响 |
| `downloads/` | 下载的安装包与源代码归档 |
| `sources/` | 解压或检出的源码 |
| `build/` | 编译输出与中间文件 |
| `tmp/` | `TMPDIR` 临时文件 |
| `cache/` | npm：`NPM_CONFIG_CACHE` 为 `cache/npm`；node-gyp：`NPM_CONFIG_DEVDIR` 为 `cache/node-gyp`；pip：`PIP_CACHE_DIR` 为 `cache/pip`；Go：`GOMODCACHE` 为 `cache/go-mod`、`GOCACHE` 为 `cache/go-build`；ccache：`CCACHE_DIR` 为 `cache/ccache` |
| `cargo/` | Rust 用户工具与依赖，`CARGO_HOME` |
| `rustup/` | Rust 工具链，`RUSTUP_HOME` |
| `go/` | Go 用户工作目录与工具，`GOPATH` |

这些安装、缓存和临时目录环境变量只设置在本机 Linux 进程中。`bin`、`npm/bin`、`python/bin`、`cargo/bin`、`go/bin` 追加到 `PATH` 末尾，保留官方 Node/Python 的原有优先级；独立环境按其完整路径调用。不要把 Ubuntu `/usr`、`dpkg/apt` 系统依赖或项目标准 `node_modules` 搬进此目录，也不要改动官方引擎 `/opt/dsh`。旧位置已安装的工具不会自动搬迁，新增用户工具按上表存放。

### 四个命令范例

下面仅展示目录写法，不会自动执行。将 `PACKAGE`、`TOOL_PACKAGE`、`SOURCE_URL` 换成所需的包名或源码地址；范例需要对应工具已安装，源码构建例适用于 CMake 项目。

1. 优先创建独立 Python 环境，再在其中安装包：

```bash
python3 -m venv "$DSH_DEPENDENCY_ROOT/venvs/my-tool"
"$DSH_DEPENDENCY_ROOT/venvs/my-tool/bin/python" -m pip install PACKAGE
```

2. 确实需要共享用户 Python 包时，使用用户安装：

```bash
PYTHONUSERBASE="$DSH_DEPENDENCY_ROOT/python" python3 -m pip install --user PACKAGE
```

3. 安装全局用户 Node 工具，不写官方引擎目录：

```bash
NPM_CONFIG_PREFIX="$DSH_DEPENDENCY_ROOT/npm" npm install -g TOOL_PACKAGE
```

4. 下载跟随跳转、明确文件名，并分开源码和编译目录：

```bash
mkdir -p "$DSH_DEPENDENCY_ROOT/downloads" "$DSH_DEPENDENCY_ROOT/sources/my-tool" "$DSH_DEPENDENCY_ROOT/build/my-tool"
curl -L -o "$DSH_DEPENDENCY_ROOT/downloads/my-tool.tar.gz" "$SOURCE_URL"
tar -xzf "$DSH_DEPENDENCY_ROOT/downloads/my-tool.tar.gz" --strip-components=1 -C "$DSH_DEPENDENCY_ROOT/sources/my-tool"
cmake -S "$DSH_DEPENDENCY_ROOT/sources/my-tool" -B "$DSH_DEPENDENCY_ROOT/build/my-tool"
cmake --build "$DSH_DEPENDENCY_ROOT/build/my-tool"
```

共享存储 `Download/DeepSeek-harness` 只放导出、分享等产出文件，不放依赖或编译环境。外部存储可能带 `noexec`，Linux 符号链接支持也可能不完整；工具、源码和构建留在上述私有目录。

依赖根位于当前 14 项引擎升级路径之外，普通兼容升级保留这里的文件；卸载、清除 App 数据或明确重置会影响这里的私有依赖。需要保留的资料另做备份，版本变化后的原生扩展仍可能需要重建。

## 普通升级不是重置

普通兼容升级只替换 App 管理的精确引擎组件，不重建整个 Linux 系统。原 HOME/profile、工作区、系统中已安装工具以及 Python/pip 等用户数据按升级契约保留；App 管理的引擎目录由随包版本接管。第三方原生扩展遇到 Node 等组件版本变化时可能需要重新构建，文件保留不等于所有扩展自动兼容。

兼容性核对失败、清单异常或升级中断时，保留原环境并按错误提示重试。重试不等于重置，也不要手动删除升级事务目录。

清除 App 数据、卸载 App 或明确的环境重置会影响本机数据；这不是普通升级步骤。重要文件应另存到运行环境之外。对话导出和诊断材料都不等于完整环境备份；当前手机壳不提供一键完整环境备份/恢复入口。

## 启动失败

错误页面出现后点重试。普通等待不需要不断重开 App；连续失败时记录版本、页面错误与启动方式，见 [常见问题](11-faq.md)。使用电脑网页不会把电脑的引擎安装到手机，详见 [网页连接](05-web.md)。
