# 依赖与工具目录规范

本文件是本项目新增、安装、复用和清理依赖的目录约定。执行者、维护者和子代理在安装任何依赖前先读本文件。**先复用已提供工具，再安装缺失项；先明确版本和目标目录，再执行。**

## 1. 分清五类内容

| 类别 | 应放位置 | 说明 |
|---|---|---|
| 共用工具链 | `D:\Tools\<工具名>\` 或其已有版本目录 | Flutter、JDK、Android SDK、独立归档/分析工具；优先沿用已配置位置 |
| DSH宿主管理的工具 | `load_workspace_dependencies` 返回的路径 | Node、Python、pnpm及已捆绑库只读取和复用，不将这里当额外安装目录 |
| 项目包依赖 | 对应项目/包的标准依赖目录 | Flutter/Dart和Node由各自包管理器管理，锁文件是版本真源 |
| 手机运行时依赖 | `runtime/locks/`、`runtime/.work/`、`runtime/out/` | 分版本、ABI和用途；不要与桌面Host依赖混用 |
| 临时工作与诊断 | `.harness-tmp-current/<任务名>/` | 本次任务专属夹具、展开副本、日志和证据；不作为常驻工具仓库 |

**以下目录不是依赖投放点：** 桌面、下载文件夹、项目根目录散放的exe/tgz、`dist/`、手机用户home/Download、DSH用户profile，以及桌面DSH安装目录的`resources/app`。DSH实现checkout仅用于维护DSH本身。

## 2. 共用工具与额外环境

现有环境优先沿用，不因目录形状与示例略有不同而搬动：

```text
D:\Tools\
  flutter\                         当前Flutter工具链
  jdk21\<已有版本>\               当前JDK工具链
  android-build\sdk\              Android SDK/NDK/build-tools
  utilities\<工具名>\<版本>\    新增独立exe/CLI工具
  node-tools\<包名>\<版本>\     新增独立Node工具的私有安装prefix
  python-envs\<用途>\            确需额外Python包时的独立venv
  cache\<生态或工具名>\          下载缓存，含版本/校验记录
  tmp\deepseek-assistant-build\    已有ASCII构建junction，不是另一个源码副本
```

- 在新目录安装独立工具时必须固定版本，保留下载URL、SHA256/发行完整性值、许可证和实际入口。
- Python先调用宿主提供的Python与已有库；额外包放独立venv，不修改宿主管理环境，也不默认执行全局pip安装。
- 独立Node工具放私有prefix，使用其明确入口。不要为了一个命令全局升级Node/npm/pnpm或更改机器PATH。
- 共用缓存可复用，但每次用于构建的归档重新校验。缓存不是来源可信的证明。
- `.gradle`、Pub、npm现有缓存保持原管理方式。本文件不自动迁移它们；确需改缓存位置时只在明确的构建进程中设置，并记录新位置。

## 3. 项目包依赖

```text
app/
  pubspec.yaml / pubspec.lock       Flutter/Dart依赖声明与锁
  .dart_tool/                      Flutter生成目录，不手工塞入工具
packages/dsh_client/
  pubspec.yaml / pubspec.lock       当前手机壳HTTP/RPC客户端包声明与锁
  .dart_tool/                      包自身Dart生成目录；包内不维护独立工具依赖
```

- `pub get --enforce-lockfile`、`npm ci`等命令在正确包目录运行；不把不同包的node_modules混在项目根目录。
- 项目新增依赖写入对应声明和锁文件。不要只复制一个未知node_modules目录作为可复现输入。
- 不手工移动包管理器创建的解析目录、junction或缓存来“整理”；需要改变布局时先验证解析、构建和测试。
- 手机壳的 `dsh_client` HTTP/RPC 连接实现与手机官方引擎prefix是两套不同用途；即使包名相同也不共用可写安装目录。

## 4. 手机官方运行时

推荐稳定布局如下。原有可校验种子先登记原位；迁移种子不是普通升级的附带动作。

```text
runtime/
  locks/
    dsh-<版本>/
      package.json
      package-lock.json            官方完整依赖图，允许纳入源码
    pnpm-<版本>/package-lock.json
  .cache/                          校验过的npm/tar/deb下载缓存
  .work/
    official/dsh-<版本>/<ABI>/
      prefix/                      Linux/ABI/libc专属npm依赖树
      assembly/                    系统种子展开与归档工作目录
  seeds/<baseId>/<ABI>/             仅构建原件，不是手机已安装目录
    assets/runtime/manifest.json
    assets/runtime/rootfs-<ABI>.tar.xz
    jniLibs/<ABI>/
  out/<ABI>/
    assets/runtime/                 最终manifest、rootfs、许可侧文件
    jniLibs/<ABI>/                  APK真实JNI输入
    official-runtime-report.json
```

- 运行时prefix按**DSH版本 + ABI + libc**分开。当前手机版目标是Linux ARM64/glibc；Windows桌面、Linux x64和musl依赖树分别作为独立平台输入管理。
- 下载和装配先在独立工作目录完成。归档大小、哈希、官方包版本、锁文件、必需ARM64模块、升级14项精确路径和baseId核验后，才发布到`runtime/out/<ABI>/`。
- 当前唯一Android壳保持`engineDistribution=official-unmodified`、`legacyBridge=false`、`enginePatches=false`。不要把旧bridge/patch/preload目录混入官方prefix。
- 跨平台npm staging可暂用`--ignore-scripts`；对必要安装钩子及原生模块单独核验，安装完成、文件存在和目标ABI真实加载分别记账。
- 系统种子必须是有大小/哈希记录的构建产物。不得从手机已安装的rootfs、用户home、真实对话或凭据目录重新打包。
- 原JNI、第三方许可证、署名以及系统base身份保持可追溯。普通升级仅更新已声明的引擎路径，不把目录整理变成用户数据迁移。

## 5. 临时目录与交付目录

```text
.harness-tmp-current/<任务名>/
  downloads/                       本次临时下载
  staging/                         本次隔离展开/安装副本
  logs/                            测试与构建日志
  evidence/                        哈希、版本、检查结果

dist/
  最终签名APK
  release-verification.json
  SHA256SUMS.txt
```

- 临时任务中已有的`linux-arm64-prefix`等路径可以保留用于证据复核，不机械搬移正在使用的工作目录。下次长期复用时应使用第4节稳定布局，并由锁文件再生成。
- `dist/`只放最终交付物及校验结果，不放安装工具、node_modules、venv、种子或中间构建树。
- 清理前确认目标由本任务创建且已无引用；不清理其他任务目录、宿主工具、当前安装或用户数据。
- 源码与锁文件进入Git；缓存、venv、node_modules、原始种子、运行时归档、APK、日志、私钥和真实配置不进入源码提交。新建目录前先用`git check-ignore`确认相应产物被排除。

## 6. 每次安装的最小记录

执行者必须记录：

1. 用途、工具/包名、固定版本、操作系统/ABI/libc。
2. 优先复用的已存在入口；缺失项及最终安装目录。
3. 来源URL、发行完整性值或下载SHA256、声明/锁文件。
4. 实际命令、退出码、可用性检查；涉及原生模块时区分文件存在与真实加载。
5. 许可证/署名位置、是否纳入Git、清理条件。

**执行前检查清单：** 没装进桌面DSH目录；没修改宿主管理的Python/Node；没混用手机和桌面依赖；没把临时目录当永久工具仓；没覆盖用户配置；构建和签名没有因“整理目录”而变化。

## 7. 当前已登记位置

- 宿主Node/Python/pnpm：通过`load_workspace_dependencies`读取当前返回值，不硬改宿主安装。
- Flutter/JDK/Android SDK：沿用第2节已配置工具链。
- rc.3官方引擎锁：`runtime/locks/dsh-0.2.2-rc.3/`。
- 当前APK运行时输入：`runtime/out/arm64-v8a/`。
- 本轮rc.3临时装配与证据：`.harness-tmp-current/mobile-rc3/`。
- 保留的原始系统构建种子：`.harness-tmp-rc2/stable-runtime-seed/`；此处是构建缓存，不是真机文件。

## 8. 安装包内的手机依赖目录

第1–7节主要约束电脑上的构建与维护工具。手机本机Linux运行时使用独立的持久目录：

```text
/root/.local/share/deepseek-harness/dependencies/
  bin/ npm/ python/ venvs/          额外工具与Python环境
  downloads/ sources/ build/        下载、源码、编译输出
  tmp/ cache/ cargo/ rustup/ go/    临时文件、缓存与工具链
```

App在官方本机运行时启动前创建真实目录，并只向guest Linux命令加入`DSH_DEPENDENCY_ROOT`、npm/pip/node-gyp/Rust/Go/ccache及TMPDIR环境；Android宿主PROOT临时目录不改。新工具bin追加到现有PATH后，Root的Android系统命令路径继续保留。

规范已写入[包内中文指南](docs/guide/zh/03-engine-hosts.md#L20-L78)、[包内英文指南](docs/guide/en/03-engine-hosts.md#L20-L78)、正常/恢复托管代理说明和依赖根内README。用户接管的说明文件保持原字节；系统apt与项目node_modules不迁移，旧工具不自动搬动。目录不在14项引擎升级路径内；卸载、清数据或明确重置仍影响私有依赖。

后续新增目录或实际迁移完成后更新登记；不要把手机路径与电脑工具仓混用。
