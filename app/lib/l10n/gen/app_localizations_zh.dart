// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get accessRootPermissions => '本机权限与 Root';

  @override
  String get accessRootDone => '完成';

  @override
  String get accessFeatureFiles => '读写手机里的文件';

  @override
  String get accessFeatureFilesNeeds => '需要文件访问权限';

  @override
  String get accessFeatureBackground => '后台持续运行';

  @override
  String get accessFeatureBackgroundNeeds => '任务跑完通知你，需要通知和后台权限';

  @override
  String get accessTurnOn => '去开启';

  @override
  String get accessViewSettings => '查看设置';

  @override
  String get accessConfirmEnabled => '我已开启';

  @override
  String get accessStateConfirmed => '已确认开启';

  @override
  String get accessOpenFailed => '没能打开系统设置';

  @override
  String get accessStorageTitle => '允许访问文件';

  @override
  String get accessStorageWhy => '让 AI 读写相册、下载和文档';

  @override
  String get accessNotifyTitle => '允许通知';

  @override
  String get accessNotifyWhy => '任务跑完、需要确认时提醒你';

  @override
  String get accessBatteryTitle => '允许在后台运行';

  @override
  String get accessBatteryWhy => '切到别的 App 时任务照常跑';

  @override
  String get accessVendorBackgroundWhy => '锁屏或切走后，不被系统断网、清理';

  @override
  String get accessAutostartTitle => '允许自启动';

  @override
  String get accessAutostartWhy => '被系统清理后能自己恢复';

  @override
  String accessVivoAutostartPath(String app) {
    return '权限管理 › 自启动 › $app';
  }

  @override
  String accessXiaomiAutostartPath(String app) {
    return '应用管理 › $app › 自启动';
  }

  @override
  String get accessStateOn => '已开启';

  @override
  String get accessStateOff => '未开启';

  @override
  String get accessStateVisited => '已去设置';

  @override
  String get accessStateUnknown => '去设置';

  @override
  String get accessFinishFailed => '没能完成设置';

  @override
  String get accessPageTitle => '系统权限';

  @override
  String get accessPageSubtitle => '各项功能用到的系统权限';

  @override
  String get botsDiscardTitle => '放弃修改？';

  @override
  String get botsKeepEditing => '继续编辑';

  @override
  String get botsDiscard => '放弃';

  @override
  String get botsProgress => '进度';

  @override
  String get chatErrReasoningEffortUnsupported => '当前模型不支持此推理档位，请调整档位或换模型';

  @override
  String get chatComposerHint => '给 DSH 发消息…';

  @override
  String get chatErrApiKey => 'API Key 无效或已过期';

  @override
  String get chatErrBalance => '余额不足';

  @override
  String get chatErrAccountQuota => '账号额度已用完';

  @override
  String get chatErrRateLimit => '请求太频繁，稍后再试';

  @override
  String get chatErrContextLength => '对话太长，发送 /compact 压缩后再试';

  @override
  String get chatErrModelUnavailable => '模型服务暂时不可用';

  @override
  String get chatErrModelTimeout => '模型响应超时';

  @override
  String get chatErrModelConnection => '没能连上模型服务';

  @override
  String get chatErrModelEmpty => '模型没有返回内容';

  @override
  String get chatErrEngineOutdated => '这个模型需要新版引擎';

  @override
  String get chatErrModelUnsupported => '当前模型不可用';

  @override
  String get chatErrTurn => '本轮出错了';

  @override
  String get commonCancel => '取消';

  @override
  String get commonRetry => '重试';

  @override
  String get commonClose => '关闭';

  @override
  String get commonBack => '返回';

  @override
  String get commonCopy => '复制';

  @override
  String get commonDelete => '删除';

  @override
  String get commonInstall => '安装';

  @override
  String get commonShare => '分享';

  @override
  String get commonCollapse => '收起';

  @override
  String get commonDetails => '详情';

  @override
  String get commonContinue => '继续';

  @override
  String get commonStorageFull => '存储空间不足';

  @override
  String get commonConnectionFailed => '连接失败';

  @override
  String get commonUntitledChat => '未命名对话';

  @override
  String get commonThisPhone => '本机';

  @override
  String get commonStopped => '已停止';

  @override
  String get commonRunning => '运行中';

  @override
  String get commonStopping => '正在停止';

  @override
  String get commonViewLogs => '查看日志';

  @override
  String commonMonthDay(String month, int day) {
    return '$month月$day日';
  }

  @override
  String get companionVoice => '语音';

  @override
  String get featuresScheduleRunLocation => '在哪里运行';

  @override
  String get fileSharedText => '分享的文字.txt';

  @override
  String get iosLocalTitle => 'iPhone / iPad 本机引擎';

  @override
  String get iosLocalScope => '直接检查此设备内嵌的 Node.js；不连接电脑或远程引擎。';

  @override
  String get iosLocalChecking => '正在读取本机状态';

  @override
  String get iosLocalProbeIdle => '本地探针尚未运行';

  @override
  String get iosLocalProbeIdleDetail => '运行探针，验证此应用内嵌 Node.js 的实际执行能力。';

  @override
  String get iosLocalProbeRunning => '正在运行本地探针';

  @override
  String get iosLocalProbeRunningDetail => '由 iOS 原生层运行内嵌 Node.js，并读取本次执行的检测结果。';

  @override
  String get iosLocalProbePassed => '内嵌 Node.js 探针已完成';

  @override
  String get iosLocalProbeCompatible => 'Node.js 版本与已检测能力符合当前要求。DSH 引擎适配仍在验证，尚未启动。';

  @override
  String get iosLocalProbeUnavailable => '本地探针尚未就绪';

  @override
  String get iosLocalNodeVersionMismatch => '当前内嵌 Node.js 版本未满足 DSH 要求；需先更新原生运行时。';

  @override
  String get iosLocalCapabilitiesMissing => '当前内嵌 Node.js 的检测能力尚未满足 DSH 要求。';

  @override
  String get iosLocalProbeTimeout => '读取或运行探针已超时。可刷新状态查看原生层的实际结果。';

  @override
  String get iosLocalProbeFailed => '本地探针执行失败。刷新状态后查看本次原生检测结果。';

  @override
  String get iosLocalRuntimeUnavailable => '此安装包的本机运行时状态不可用。刷新可重试读取；此处不会替换为远程引擎。';

  @override
  String iosLocalNodeVersion(String version) {
    return '实际 Node.js：$version';
  }

  @override
  String iosLocalRequiredNode(String range) {
    return 'DSH 所需 Node.js：$range';
  }

  @override
  String iosLocalDshVersion(String version) {
    return '目标 DSH：$version';
  }

  @override
  String get iosLocalNotDetected => '尚未检测';

  @override
  String get iosLocalDshNotStarted => 'DSH 本机引擎未启动';

  @override
  String get iosLocalProbeOnly => '探针通过仅证明内嵌 Node.js 已实际执行，不代表 DSH 已安装、已启动或网页已就绪。';

  @override
  String get iosLocalCapabilitiesTitle => '本次原生能力检测';

  @override
  String get iosLocalCapabilityFileSystem => '应用内文件读写';

  @override
  String get iosLocalCapabilityIntl => 'Intl 国际化';

  @override
  String get iosLocalCapabilityBuiltinModule => 'Node 内置模块访问';

  @override
  String get iosLocalCapabilitySqlite => 'Node 内置 SQLite';

  @override
  String get iosLocalCapabilitySqliteFts => 'SQLite FTS5 全文检索';

  @override
  String get iosLocalCapabilityImportMain => 'ES 模块入口检测';

  @override
  String get iosLocalCapabilityImportFilename => 'ES 模块文件名';

  @override
  String get iosLocalCapabilityImportDirname => 'ES 模块目录名';

  @override
  String get iosLocalCheckPassed => '通过';

  @override
  String get iosLocalCheckFailed => '未通过';

  @override
  String get iosLocalBackgroundObservation => '原生层上次读取时，应用处于后台。';

  @override
  String get iosLocalBackgroundLimit => '后台暂停与系统终止后需重新确认本机状态；探针不承诺持续后台运行。';

  @override
  String get iosLocalRunProbe => '运行本地探针';

  @override
  String get iosLocalRefresh => '刷新状态';

  @override
  String localEnvThisPhoneDetail(int storage, int memory) {
    return '存储约 $storage MB · 内存约 $memory MB';
  }

  @override
  String localEnvThisPhoneDetailShort(int memory) {
    return '内存约 $memory MB';
  }

  @override
  String localEnvLowStorage(int needed) {
    return '存储空间不足，需要约 $needed MB';
  }

  @override
  String get localEnvRemoteDetail => '连接电脑或服务器上的 DSH';

  @override
  String get localEnvInstallTitle => '安装本机运行环境';

  @override
  String get localEnvInstallMessage => '在这台手机上运行 DSH';

  @override
  String localEnvFactStorage(int storage) {
    return '约 $storage MB 存储空间';
  }

  @override
  String localEnvFactMemory(int memory) {
    return '运行时约 $memory MB 内存';
  }

  @override
  String get localEnvNotInstalled => '本机未安装运行环境';

  @override
  String get mediaVary => '变体';

  @override
  String get mediaEdit => '编辑';

  @override
  String get mediaUpscale => '放大';

  @override
  String get phoneDiagnosticsCollecting => '正在收集…';

  @override
  String get phoneDiagnosticsPacking => '正在打包…';

  @override
  String get phoneDiagnosticsSharing => '正在打开分享…';

  @override
  String get phoneDiagnosticsSaving => '正在存到「下载」…';

  @override
  String get phoneDiagnosticsShare => '分享诊断包';

  @override
  String get phoneDiagnosticsShareHint => '附在问题反馈里';

  @override
  String get phoneDiagnosticsSave => '存到「下载」';

  @override
  String get phoneDiagnosticsSaveHint => '存进 下载/DeepSeek-harness';

  @override
  String get phoneDiagnosticsNote => '含版本、设备、日志和最近一次崩溃，不含 Key 和令牌';

  @override
  String get phoneDiagnosticsExport => '导出诊断包';

  @override
  String get phoneSafeMode => '安全模式';

  @override
  String get phoneEngineInstallRuntime => '安装运行环境';

  @override
  String get phoneEngineNotInstalled => '未安装';

  @override
  String get phoneEngineInstalling => '正在安装';

  @override
  String get phoneEngineStoppedSafe => '已停止 · 安全模式';

  @override
  String get phoneEngineStartingSafe => '正在以安全模式启动';

  @override
  String get phoneEngineStarting => '正在启动';

  @override
  String get phoneEngineRunningProbation => '运行中 · 试用';

  @override
  String get phoneEngineStartupFailed => '启动失败';

  @override
  String get phoneEngineCrashed => '已崩溃';

  @override
  String get phoneEngineKilled => '被系统结束';

  @override
  String get phoneEngineError => '出错了';

  @override
  String get phoneEngineRuntimeCorrupt => 'App 内的运行环境包已损坏，请重新安装 App';

  @override
  String get phoneEngineExited => '引擎意外退出了';

  @override
  String get phoneEngineRuntimeMissing => '运行环境还没有安装';

  @override
  String get phoneEngineSafeUnsupported => '这个版本的运行环境不支持安全模式，请更新 App';

  @override
  String get phoneEngineRuntimeIncomplete => 'App 内的运行环境包不完整，请重新安装 App';

  @override
  String get phoneLogEmpty => '还没有日志';

  @override
  String get phoneLogShareTitle => 'DSH 引擎日志';

  @override
  String get phoneLogCopyAll => '复制全部';

  @override
  String get phoneFailureLaunch => '本机运行环境未能启动';

  @override
  String get phoneAccentMist => '雾蓝';

  @override
  String get phoneAccentDaiqing => '黛青';

  @override
  String get phoneAccentDusk => '暮紫';

  @override
  String get phoneAccentTurquoise => '松石';

  @override
  String get phoneAccentAmber => '琥珀';

  @override
  String get phoneAccentGraphite => '石墨';

  @override
  String get phoneAccentCustom => '自定义';

  @override
  String phoneEngineInstallPercent(int percent) {
    return '正在安装 · $percent%';
  }

  @override
  String phoneEngineStatusSemantics(String prefix, String status) {
    return '$prefix引擎：$status';
  }

  @override
  String phoneLogLineCount(int count) {
    return '$count 行';
  }

  @override
  String phoneLogCopiedLines(int count) {
    return '已复制 $count 行';
  }

  @override
  String phoneEngineStorageDetails(String needed, String free) {
    return '存储空间不足：需要约 $needed MB，当前可用 $free MB';
  }

  @override
  String get pluginsAllowHighPower => '允许后台高耗电';

  @override
  String pluginsVivoBatteryPath(String app) {
    return '电池 › 后台耗电管理 › $app';
  }

  @override
  String get pluginsXiaomiBatterySetting => '省电策略：无限制';

  @override
  String pluginsXiaomiBatteryPath(String app) {
    return '应用管理 › $app › 省电策略';
  }

  @override
  String get pluginsHuaweiBatterySetting => '允许后台活动';

  @override
  String pluginsHuaweiBatteryPath(String app) {
    return '电池 › 应用启动管理 › $app';
  }

  @override
  String get pluginsOppoBatterySetting => '允许后台行为';

  @override
  String pluginsOppoBatteryPath(String app) {
    return '电池 › 应用耗电管理 › $app';
  }

  @override
  String get pluginsQrCode => '二维码';

  @override
  String get remoteConnectComputer => '连接电脑或服务器';

  @override
  String get remoteServerAddress => '服务器地址';

  @override
  String get remoteHost => '主机';

  @override
  String get remoteDirectoryRecent => '最近';

  @override
  String get remotePairCameraFailed => '相机打不开。可以用「从相册识别」或「粘贴配对链接」';

  @override
  String get remotePairConfirmTitle => '要连接这台电脑吗？';

  @override
  String get remotePairComputer => '电脑';

  @override
  String get phoneRuntimeUpgradeBase => '新引擎与现有 Linux 环境不能确认兼容，更新已停止。原环境和已装工具没有删除。请先完整备份，再联系维护者迁移；不要直接重置或卸载 App。';

  @override
  String get phoneRuntimeUpgradeManifest => '无法安全识别运行时更新清单，更新已停止，原环境保留。请核对安装包并联系维护者，不要直接重置。';

  @override
  String get phoneRuntimeUpgradeInterrupted => '运行时升级尚未完成，数据与恢复现场已保留。请重试安装；仍失败时导出诊断并联系维护者，不要重置或删除恢复目录。';

  @override
  String get phoneRuntimeUpgradeSymlink => '现有环境的系统路径已被自定义链接替换，无法安全更新。原环境保留，请先备份并联系维护者处理。';

  @override
  String get phoneRuntimeUpgradeRunning => '引擎或遗留进程尚未确认停止，更新未开始。请先停止本机引擎，等待清理完成后重试；不要重置环境。';

  @override
  String get setupCapsulePreparing => '准备运行环境';

  @override
  String setupCapsuleProgress(int percent) {
    return '运行环境 $percent%';
  }

  @override
  String setupCapsuleProgressSemantics(int percent) {
    return '正在准备运行环境，已完成 $percent%';
  }

  @override
  String get setupCapsuleReady => '运行环境已就绪';

  @override
  String get setupCapsuleFailed => '安装未完成';

  @override
  String get setupWaitingBody => '完成后自动进入';

  @override
  String get setupNotifyWhenDone => '完成时会通知你';

  @override
  String shellOnboardingStep(int step, int steps) {
    return '第 $step 步，共 $steps 步';
  }

  @override
  String get shellRuntimeUpdating => '正在更新运行环境';

  @override
  String get shellRuntimePreparing => '正在准备运行环境';

  @override
  String get shellRuntimeReady => '准备就绪';

  @override
  String get shellRuntimeIncomplete => '安装未完成';

  @override
  String get shellRuntimeFilesKept => '对话和文件都会保留';

  @override
  String get shellRuntimeFirstSetup => '首次准备约需一两分钟';

  @override
  String get shellRuntimeContinuing => '即将继续';

  @override
  String get shellRuntimeRestoreFailed => '没能放回保留的内容';

  @override
  String get shellRuntimeExtractFailed => '解压时出错';

  @override
  String get shellInstallLogs => '安装日志';

  @override
  String get shellRuntimeLocalOnly => '全程在本机完成';

  @override
  String get shellRuntimeContinueWithoutKept => '不保留，继续安装';

  @override
  String get shellRuntimeAlmostDone => '马上就好';

  @override
  String shellRuntimeSecondsRemaining(int count) {
    return '约 $count 秒';
  }

  @override
  String shellRuntimeMinutesRemaining(int count) {
    return '约 $count 分钟';
  }

  @override
  String get shellEngineLogs => '引擎日志';

  @override
  String get shellWelcomeMessage => '把 DeepSeek 智能体\n装进口袋';

  @override
  String get shellGetStarted => '开始';

  @override
  String get phoneStartupFailureStopping => '启动失败，正在停止';

  @override
  String get phoneStartupTokenTimeout => '启动等待已超时（180 秒内未收到启动标记），请查看日志';

  @override
  String get phoneStartupPortNotReady => '已收到启动标记，但本机服务端口尚未就绪，请查看日志';

  @override
  String get stateDiagnosticsSubject => 'DeepSeek harness 诊断包';

  @override
  String get stateStoragePermission => '没有存储权限，存不进「下载」';

  @override
  String get stateDiagnosticsStorageFull => '存储空间不足，没能生成诊断包';

  @override
  String get stateDiagnosticsExportFailed => '没能导出诊断包';

  @override
  String get stateFileOpenFailed => '无法打开这个文件';

  @override
  String get stateLinkOpenFailed => '无法打开这个链接';

  @override
  String get stateAlertPublicDone => '有一轮完成了';

  @override
  String get stateAlertPublicFailed => '有一轮出错了';

  @override
  String get stateAlertPublicStopped => '有一轮停下了';

  @override
  String get stateAlertPublicApproval => '有一步等你确认';

  @override
  String get stateAlertPublicQuestion => '有个问题等你回答';

  @override
  String get stateAlertTurnDone => '这一轮已完成';

  @override
  String get stateAlertOutputLimit => '已结束 · 达到单次输出长度上限';

  @override
  String get stateAlertTurnBlocked => '这一轮被拦截了';

  @override
  String get stateAlertEngineRestarted => '已中断 · 引擎重启过';

  @override
  String get stateAlertMissingKey => '出错了 · 还没有配置密钥';

  @override
  String get stateAlertTurnFailed => '这一轮出错了';

  @override
  String get stateRunCommand => '运行命令';

  @override
  String get stateWriteFile => '写入文件';

  @override
  String get stateEditFile => '修改文件';

  @override
  String get stateOpenPage => '打开网页';

  @override
  String get stateWebSearch => '联网搜索';

  @override
  String get stateAlertQuestion => '问你一个问题';

  @override
  String get stateWallpaper => '壁纸';

  @override
  String get stateShareFileTooLarge => '有文件太大，未添加';

  @override
  String get stateShareFileUnreadable => '有文件没能读取';

  @override
  String get stateProviderUrlInvalid => '以 http:// 或 https:// 开头的完整地址';

  @override
  String stateDiagnosticsSaved(String where) {
    return '已存到 $where';
  }

  @override
  String get stateDownloadsPrefix => '下载/';

  @override
  String stateAlertCompletedReply(String reply) {
    return '已完成 · $reply';
  }

  @override
  String stateAlertErrorDetail(String detail) {
    return '出错了 · $detail';
  }

  @override
  String stateAlertUseTool(String name) {
    return '使用工具 $name';
  }

  @override
  String stateAlertApprovalAction(String action) {
    return '等你确认：$action';
  }

  @override
  String stateAlertApprovalReason(String action, String reason) {
    return '等你确认：$action · $reason';
  }

  @override
  String stateAlertQuestions(String question, int count) {
    return '问你：$question（共 $count 个）';
  }

  @override
  String stateAlertQuestionText(String question) {
    return '问你：$question';
  }

  @override
  String stateAttachmentEmpty(String name) {
    return '「$name」是空文件';
  }

  @override
  String stateAttachmentImageLimit(String name) {
    return '图片「$name」超过 20 MB';
  }

  @override
  String stateAttachmentFileLimit(String name) {
    return '文件「$name」超过 200 MB';
  }

  @override
  String get stateAttachmentTotalLimit => '附件总大小超过 400 MB';

  @override
  String stateShareReadFailed(String name) {
    return '没能读取「$name」';
  }

  @override
  String stateShareAttachmentLimit(int count) {
    return '每条消息最多 $count 个附件';
  }

  @override
  String stateShareNamedFileTooLarge(String name) {
    return '「$name」太大，未添加';
  }

  @override
  String stateAlertPreviewRun(String value) {
    return '运行：$value';
  }

  @override
  String stateAlertPreviewWrite(String value) {
    return '写入：$value';
  }

  @override
  String stateAlertPreviewEdit(String value) {
    return '修改：$value';
  }

  @override
  String stateAlertPreviewOpen(String value) {
    return '打开：$value';
  }

  @override
  String stateAlertPreviewUse(String value) {
    return '使用工具：$value';
  }

  @override
  String get webConfigDocumentTitle => '配置文件';

  @override
  String get webConfigDocumentReadOnly => '只读 · 当前运行配置';

  @override
  String get webConfigDocumentReadFailed => '配置文件没有打开，请确认本机引擎仍在运行后重试。';

  @override
  String get localWebExploreBeyond => '探索未至之境';

  @override
  String get webComputerCheckConnection => '检查手机与电脑的网络连接，并确认电脑网页服务已开启';

  @override
  String get webTitle => 'DSH 网页版';

  @override
  String get webLocalAppOnly => '本机地址带启动令牌，只能在 App 内打开';

  @override
  String get webEngineStartFailed => '引擎没能启动';

  @override
  String get webAttachmentTooLarge => '附件太大，没能带进网页版';

  @override
  String get webTextCopied => '文字已复制，粘贴到输入框即可';

  @override
  String get webAttachmentFailed => '附件没能带进网页版';

  @override
  String get webPageClosed => '网页已关闭';

  @override
  String get webChatsWorkspaces => '对话与工作区';

  @override
  String get webRefresh => '刷新';

  @override
  String get webOpenInBrowser => '在浏览器打开';

  @override
  String get webBrowserUnavailable => '不能在浏览器打开';

  @override
  String get webReopen => '重新打开';

  @override
  String get webPageNotOpened => '页面没有打开';

  @override
  String get webCheckConnection => '检查网络或引擎状态后再试';

  @override
  String get webTargetSessionMissing => '网页版里没找到这个对话，已停在首页';

  @override
  String get webTargetNotLoaded => '网页版没有加载完成';

  @override
  String get webTargetSettingsMissing => '没找到这页设置，可能需要先登录或开启对应插件';

  @override
  String get webTargetNewChatFailed => '没能新建对话，已停在网页版首页';

  @override
  String get webTargetPageFailed => '没能直接打开这一页，已停在网页版首页';
}
