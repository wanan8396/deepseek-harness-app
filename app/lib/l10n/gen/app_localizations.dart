import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  /// No description provided for @accessRootPermissions.
  ///
  /// In zh, this message translates to:
  /// **'本机权限与 Root'**
  String get accessRootPermissions;

  /// No description provided for @accessRootDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get accessRootDone;

  /// No description provided for @accessFeatureFiles.
  ///
  /// In zh, this message translates to:
  /// **'读写手机里的文件'**
  String get accessFeatureFiles;

  /// No description provided for @accessFeatureFilesNeeds.
  ///
  /// In zh, this message translates to:
  /// **'需要文件访问权限'**
  String get accessFeatureFilesNeeds;

  /// No description provided for @accessFeatureBackground.
  ///
  /// In zh, this message translates to:
  /// **'后台持续运行'**
  String get accessFeatureBackground;

  /// No description provided for @accessFeatureBackgroundNeeds.
  ///
  /// In zh, this message translates to:
  /// **'任务跑完通知你，需要通知和后台权限'**
  String get accessFeatureBackgroundNeeds;

  /// No description provided for @accessTurnOn.
  ///
  /// In zh, this message translates to:
  /// **'去开启'**
  String get accessTurnOn;

  /// No description provided for @accessViewSettings.
  ///
  /// In zh, this message translates to:
  /// **'查看设置'**
  String get accessViewSettings;

  /// No description provided for @accessConfirmEnabled.
  ///
  /// In zh, this message translates to:
  /// **'我已开启'**
  String get accessConfirmEnabled;

  /// No description provided for @accessStateConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'已确认开启'**
  String get accessStateConfirmed;

  /// No description provided for @accessOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能打开系统设置'**
  String get accessOpenFailed;

  /// No description provided for @accessStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许访问文件'**
  String get accessStorageTitle;

  /// No description provided for @accessStorageWhy.
  ///
  /// In zh, this message translates to:
  /// **'让 AI 读写相册、下载和文档'**
  String get accessStorageWhy;

  /// No description provided for @accessNotifyTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许通知'**
  String get accessNotifyTitle;

  /// No description provided for @accessNotifyWhy.
  ///
  /// In zh, this message translates to:
  /// **'任务跑完、需要确认时提醒你'**
  String get accessNotifyWhy;

  /// No description provided for @accessBatteryTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许在后台运行'**
  String get accessBatteryTitle;

  /// No description provided for @accessBatteryWhy.
  ///
  /// In zh, this message translates to:
  /// **'切到别的 App 时任务照常跑'**
  String get accessBatteryWhy;

  /// No description provided for @accessVendorBackgroundWhy.
  ///
  /// In zh, this message translates to:
  /// **'锁屏或切走后，不被系统断网、清理'**
  String get accessVendorBackgroundWhy;

  /// No description provided for @accessAutostartTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许自启动'**
  String get accessAutostartTitle;

  /// No description provided for @accessAutostartWhy.
  ///
  /// In zh, this message translates to:
  /// **'被系统清理后能自己恢复'**
  String get accessAutostartWhy;

  /// No description provided for @accessVivoAutostartPath.
  ///
  /// In zh, this message translates to:
  /// **'权限管理 › 自启动 › {app}'**
  String accessVivoAutostartPath(String app);

  /// No description provided for @accessXiaomiAutostartPath.
  ///
  /// In zh, this message translates to:
  /// **'应用管理 › {app} › 自启动'**
  String accessXiaomiAutostartPath(String app);

  /// No description provided for @accessStateOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get accessStateOn;

  /// No description provided for @accessStateOff.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get accessStateOff;

  /// No description provided for @accessStateVisited.
  ///
  /// In zh, this message translates to:
  /// **'已去设置'**
  String get accessStateVisited;

  /// No description provided for @accessStateUnknown.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get accessStateUnknown;

  /// No description provided for @accessFinishFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能完成设置'**
  String get accessFinishFailed;

  /// No description provided for @accessPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'系统权限'**
  String get accessPageTitle;

  /// No description provided for @accessPageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'各项功能用到的系统权限'**
  String get accessPageSubtitle;

  /// No description provided for @botsDiscardTitle.
  ///
  /// In zh, this message translates to:
  /// **'放弃修改？'**
  String get botsDiscardTitle;

  /// No description provided for @botsKeepEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get botsKeepEditing;

  /// No description provided for @botsDiscard.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get botsDiscard;

  /// No description provided for @botsProgress.
  ///
  /// In zh, this message translates to:
  /// **'进度'**
  String get botsProgress;

  /// No description provided for @chatErrReasoningEffortUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持此推理档位，请调整档位或换模型'**
  String get chatErrReasoningEffortUnsupported;

  /// No description provided for @chatComposerHint.
  ///
  /// In zh, this message translates to:
  /// **'给 DSH 发消息…'**
  String get chatComposerHint;

  /// No description provided for @chatErrApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key 无效或已过期'**
  String get chatErrApiKey;

  /// No description provided for @chatErrBalance.
  ///
  /// In zh, this message translates to:
  /// **'余额不足'**
  String get chatErrBalance;

  /// No description provided for @chatErrAccountQuota.
  ///
  /// In zh, this message translates to:
  /// **'账号额度已用完'**
  String get chatErrAccountQuota;

  /// No description provided for @chatErrRateLimit.
  ///
  /// In zh, this message translates to:
  /// **'请求太频繁，稍后再试'**
  String get chatErrRateLimit;

  /// No description provided for @chatErrContextLength.
  ///
  /// In zh, this message translates to:
  /// **'对话太长，发送 /compact 压缩后再试'**
  String get chatErrContextLength;

  /// No description provided for @chatErrModelUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'模型服务暂时不可用'**
  String get chatErrModelUnavailable;

  /// No description provided for @chatErrModelTimeout.
  ///
  /// In zh, this message translates to:
  /// **'模型响应超时'**
  String get chatErrModelTimeout;

  /// No description provided for @chatErrModelConnection.
  ///
  /// In zh, this message translates to:
  /// **'没能连上模型服务'**
  String get chatErrModelConnection;

  /// No description provided for @chatErrModelEmpty.
  ///
  /// In zh, this message translates to:
  /// **'模型没有返回内容'**
  String get chatErrModelEmpty;

  /// No description provided for @chatErrEngineOutdated.
  ///
  /// In zh, this message translates to:
  /// **'这个模型需要新版引擎'**
  String get chatErrEngineOutdated;

  /// No description provided for @chatErrModelUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不可用'**
  String get chatErrModelUnsupported;

  /// No description provided for @chatErrTurn.
  ///
  /// In zh, this message translates to:
  /// **'本轮出错了'**
  String get chatErrTurn;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get commonBack;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get commonInstall;

  /// No description provided for @commonShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get commonShare;

  /// No description provided for @commonCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get commonCollapse;

  /// No description provided for @commonDetails.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get commonDetails;

  /// No description provided for @commonContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get commonContinue;

  /// No description provided for @commonStorageFull.
  ///
  /// In zh, this message translates to:
  /// **'存储空间不足'**
  String get commonStorageFull;

  /// No description provided for @commonConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get commonConnectionFailed;

  /// No description provided for @commonUntitledChat.
  ///
  /// In zh, this message translates to:
  /// **'未命名对话'**
  String get commonUntitledChat;

  /// No description provided for @commonThisPhone.
  ///
  /// In zh, this message translates to:
  /// **'本机'**
  String get commonThisPhone;

  /// No description provided for @commonStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get commonStopped;

  /// No description provided for @commonRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get commonRunning;

  /// No description provided for @commonStopping.
  ///
  /// In zh, this message translates to:
  /// **'正在停止'**
  String get commonStopping;

  /// No description provided for @commonViewLogs.
  ///
  /// In zh, this message translates to:
  /// **'查看日志'**
  String get commonViewLogs;

  /// Short date (month 1–12).
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String commonMonthDay(String month, int day);

  /// No description provided for @companionVoice.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get companionVoice;

  /// No description provided for @featuresScheduleRunLocation.
  ///
  /// In zh, this message translates to:
  /// **'在哪里运行'**
  String get featuresScheduleRunLocation;

  /// No description provided for @fileSharedText.
  ///
  /// In zh, this message translates to:
  /// **'分享的文字.txt'**
  String get fileSharedText;

  /// No description provided for @iosLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'iPhone / iPad 本机引擎'**
  String get iosLocalTitle;

  /// No description provided for @iosLocalScope.
  ///
  /// In zh, this message translates to:
  /// **'直接检查此设备内嵌的 Node.js；不连接电脑或远程引擎。'**
  String get iosLocalScope;

  /// No description provided for @iosLocalChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在读取本机状态'**
  String get iosLocalChecking;

  /// No description provided for @iosLocalProbeIdle.
  ///
  /// In zh, this message translates to:
  /// **'本地探针尚未运行'**
  String get iosLocalProbeIdle;

  /// No description provided for @iosLocalProbeIdleDetail.
  ///
  /// In zh, this message translates to:
  /// **'运行探针，验证此应用内嵌 Node.js 的实际执行能力。'**
  String get iosLocalProbeIdleDetail;

  /// No description provided for @iosLocalProbeRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在运行本地探针'**
  String get iosLocalProbeRunning;

  /// No description provided for @iosLocalProbeRunningDetail.
  ///
  /// In zh, this message translates to:
  /// **'由 iOS 原生层运行内嵌 Node.js，并读取本次执行的检测结果。'**
  String get iosLocalProbeRunningDetail;

  /// No description provided for @iosLocalProbePassed.
  ///
  /// In zh, this message translates to:
  /// **'内嵌 Node.js 探针已完成'**
  String get iosLocalProbePassed;

  /// No description provided for @iosLocalProbeCompatible.
  ///
  /// In zh, this message translates to:
  /// **'Node.js 版本与已检测能力符合当前要求。DSH 引擎适配仍在验证，尚未启动。'**
  String get iosLocalProbeCompatible;

  /// No description provided for @iosLocalProbeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'本地探针尚未就绪'**
  String get iosLocalProbeUnavailable;

  /// No description provided for @iosLocalNodeVersionMismatch.
  ///
  /// In zh, this message translates to:
  /// **'当前内嵌 Node.js 版本未满足 DSH 要求；需先更新原生运行时。'**
  String get iosLocalNodeVersionMismatch;

  /// No description provided for @iosLocalCapabilitiesMissing.
  ///
  /// In zh, this message translates to:
  /// **'当前内嵌 Node.js 的检测能力尚未满足 DSH 要求。'**
  String get iosLocalCapabilitiesMissing;

  /// No description provided for @iosLocalProbeTimeout.
  ///
  /// In zh, this message translates to:
  /// **'读取或运行探针已超时。可刷新状态查看原生层的实际结果。'**
  String get iosLocalProbeTimeout;

  /// No description provided for @iosLocalProbeFailed.
  ///
  /// In zh, this message translates to:
  /// **'本地探针执行失败。刷新状态后查看本次原生检测结果。'**
  String get iosLocalProbeFailed;

  /// No description provided for @iosLocalRuntimeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'此安装包的本机运行时状态不可用。刷新可重试读取；此处不会替换为远程引擎。'**
  String get iosLocalRuntimeUnavailable;

  /// No description provided for @iosLocalNodeVersion.
  ///
  /// In zh, this message translates to:
  /// **'实际 Node.js：{version}'**
  String iosLocalNodeVersion(String version);

  /// No description provided for @iosLocalRequiredNode.
  ///
  /// In zh, this message translates to:
  /// **'DSH 所需 Node.js：{range}'**
  String iosLocalRequiredNode(String range);

  /// No description provided for @iosLocalDshVersion.
  ///
  /// In zh, this message translates to:
  /// **'目标 DSH：{version}'**
  String iosLocalDshVersion(String version);

  /// No description provided for @iosLocalNotDetected.
  ///
  /// In zh, this message translates to:
  /// **'尚未检测'**
  String get iosLocalNotDetected;

  /// No description provided for @iosLocalDshNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'DSH 本机引擎未启动'**
  String get iosLocalDshNotStarted;

  /// No description provided for @iosLocalProbeOnly.
  ///
  /// In zh, this message translates to:
  /// **'探针通过仅证明内嵌 Node.js 已实际执行，不代表 DSH 已安装、已启动或网页已就绪。'**
  String get iosLocalProbeOnly;

  /// No description provided for @iosLocalCapabilitiesTitle.
  ///
  /// In zh, this message translates to:
  /// **'本次原生能力检测'**
  String get iosLocalCapabilitiesTitle;

  /// No description provided for @iosLocalCapabilityFileSystem.
  ///
  /// In zh, this message translates to:
  /// **'应用内文件读写'**
  String get iosLocalCapabilityFileSystem;

  /// No description provided for @iosLocalCapabilityIntl.
  ///
  /// In zh, this message translates to:
  /// **'Intl 国际化'**
  String get iosLocalCapabilityIntl;

  /// No description provided for @iosLocalCapabilityBuiltinModule.
  ///
  /// In zh, this message translates to:
  /// **'Node 内置模块访问'**
  String get iosLocalCapabilityBuiltinModule;

  /// No description provided for @iosLocalCapabilitySqlite.
  ///
  /// In zh, this message translates to:
  /// **'Node 内置 SQLite'**
  String get iosLocalCapabilitySqlite;

  /// No description provided for @iosLocalCapabilitySqliteFts.
  ///
  /// In zh, this message translates to:
  /// **'SQLite FTS5 全文检索'**
  String get iosLocalCapabilitySqliteFts;

  /// No description provided for @iosLocalCapabilityImportMain.
  ///
  /// In zh, this message translates to:
  /// **'ES 模块入口检测'**
  String get iosLocalCapabilityImportMain;

  /// No description provided for @iosLocalCapabilityImportFilename.
  ///
  /// In zh, this message translates to:
  /// **'ES 模块文件名'**
  String get iosLocalCapabilityImportFilename;

  /// No description provided for @iosLocalCapabilityImportDirname.
  ///
  /// In zh, this message translates to:
  /// **'ES 模块目录名'**
  String get iosLocalCapabilityImportDirname;

  /// No description provided for @iosLocalCheckPassed.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get iosLocalCheckPassed;

  /// No description provided for @iosLocalCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'未通过'**
  String get iosLocalCheckFailed;

  /// No description provided for @iosLocalCheckNotRun.
  ///
  /// In zh, this message translates to:
  /// **'未检测'**
  String get iosLocalCheckNotRun;

  /// No description provided for @iosLocalLoaderTitle.
  ///
  /// In zh, this message translates to:
  /// **'官方 DSH Loader 验证'**
  String get iosLocalLoaderTitle;

  /// No description provided for @iosLocalLoaderDetail.
  ///
  /// In zh, this message translates to:
  /// **'仅验证最小 Loader 的启动、服务、清理与错误基线，不代表完整本机引擎已就绪。'**
  String get iosLocalLoaderDetail;

  /// No description provided for @iosLocalLoaderBooted.
  ///
  /// In zh, this message translates to:
  /// **'Loader 已启动'**
  String get iosLocalLoaderBooted;

  /// No description provided for @iosLocalLoaderService.
  ///
  /// In zh, this message translates to:
  /// **'服务已验证'**
  String get iosLocalLoaderService;

  /// No description provided for @iosLocalLoaderDispose.
  ///
  /// In zh, this message translates to:
  /// **'Loader 清理已验证'**
  String get iosLocalLoaderDispose;

  /// No description provided for @iosLocalLoaderBadBaseline.
  ///
  /// In zh, this message translates to:
  /// **'错误启动基线已拦截'**
  String get iosLocalLoaderBadBaseline;

  /// No description provided for @iosLocalCoreTitle.
  ///
  /// In zh, this message translates to:
  /// **'DSH 核心验证（离线）'**
  String get iosLocalCoreTitle;

  /// No description provided for @iosLocalCoreDetail.
  ///
  /// In zh, this message translates to:
  /// **'仅使用内存存储和固定离线测试模型；非真实模型提供者，不发起模型 API 调用。核心检查通过仍不代表完整本机引擎已就绪或可正式聊天。'**
  String get iosLocalCoreDetail;

  /// No description provided for @iosLocalCoreBooted.
  ///
  /// In zh, this message translates to:
  /// **'核心已启动'**
  String get iosLocalCoreBooted;

  /// No description provided for @iosLocalCoreServices.
  ///
  /// In zh, this message translates to:
  /// **'核心服务已验证'**
  String get iosLocalCoreServices;

  /// No description provided for @iosLocalCoreFirstTurn.
  ///
  /// In zh, this message translates to:
  /// **'首轮流式消息已验证'**
  String get iosLocalCoreFirstTurn;

  /// No description provided for @iosLocalCoreSecondTurn.
  ///
  /// In zh, this message translates to:
  /// **'第二轮历史已验证'**
  String get iosLocalCoreSecondTurn;

  /// No description provided for @iosLocalCoreCancellation.
  ///
  /// In zh, this message translates to:
  /// **'取消后已收敛'**
  String get iosLocalCoreCancellation;

  /// No description provided for @iosLocalCoreError.
  ///
  /// In zh, this message translates to:
  /// **'错误后已收敛'**
  String get iosLocalCoreError;

  /// No description provided for @iosLocalCoreDispose.
  ///
  /// In zh, this message translates to:
  /// **'核心清理已验证'**
  String get iosLocalCoreDispose;

  /// No description provided for @iosLocalCoreBadBaseline.
  ///
  /// In zh, this message translates to:
  /// **'核心错误启动基线已拦截'**
  String get iosLocalCoreBadBaseline;

  /// No description provided for @iosLocalCoreEphemeral.
  ///
  /// In zh, this message translates to:
  /// **'仅内存存储'**
  String get iosLocalCoreEphemeral;

  /// No description provided for @iosLocalBackgroundObservation.
  ///
  /// In zh, this message translates to:
  /// **'原生层上次读取时，应用处于后台。'**
  String get iosLocalBackgroundObservation;

  /// No description provided for @iosLocalBackgroundLimit.
  ///
  /// In zh, this message translates to:
  /// **'后台暂停与系统终止后需重新确认本机状态；探针不承诺持续后台运行。'**
  String get iosLocalBackgroundLimit;

  /// No description provided for @iosLocalRunProbe.
  ///
  /// In zh, this message translates to:
  /// **'运行本地探针'**
  String get iosLocalRunProbe;

  /// No description provided for @iosLocalRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get iosLocalRefresh;

  /// No description provided for @localEnvThisPhoneDetail.
  ///
  /// In zh, this message translates to:
  /// **'存储约 {storage} MB · 内存约 {memory} MB'**
  String localEnvThisPhoneDetail(int storage, int memory);

  /// No description provided for @localEnvThisPhoneDetailShort.
  ///
  /// In zh, this message translates to:
  /// **'内存约 {memory} MB'**
  String localEnvThisPhoneDetailShort(int memory);

  /// No description provided for @localEnvLowStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储空间不足，需要约 {needed} MB'**
  String localEnvLowStorage(int needed);

  /// No description provided for @localEnvRemoteDetail.
  ///
  /// In zh, this message translates to:
  /// **'连接电脑或服务器上的 DSH'**
  String get localEnvRemoteDetail;

  /// No description provided for @localEnvInstallTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装本机运行环境'**
  String get localEnvInstallTitle;

  /// No description provided for @localEnvInstallMessage.
  ///
  /// In zh, this message translates to:
  /// **'在这台手机上运行 DSH'**
  String get localEnvInstallMessage;

  /// No description provided for @localEnvFactStorage.
  ///
  /// In zh, this message translates to:
  /// **'约 {storage} MB 存储空间'**
  String localEnvFactStorage(int storage);

  /// No description provided for @localEnvFactMemory.
  ///
  /// In zh, this message translates to:
  /// **'运行时约 {memory} MB 内存'**
  String localEnvFactMemory(int memory);

  /// No description provided for @localEnvNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'本机未安装运行环境'**
  String get localEnvNotInstalled;

  /// No description provided for @mediaVary.
  ///
  /// In zh, this message translates to:
  /// **'变体'**
  String get mediaVary;

  /// No description provided for @mediaEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get mediaEdit;

  /// No description provided for @mediaUpscale.
  ///
  /// In zh, this message translates to:
  /// **'放大'**
  String get mediaUpscale;

  /// No description provided for @phoneDiagnosticsCollecting.
  ///
  /// In zh, this message translates to:
  /// **'正在收集…'**
  String get phoneDiagnosticsCollecting;

  /// No description provided for @phoneDiagnosticsPacking.
  ///
  /// In zh, this message translates to:
  /// **'正在打包…'**
  String get phoneDiagnosticsPacking;

  /// No description provided for @phoneDiagnosticsSharing.
  ///
  /// In zh, this message translates to:
  /// **'正在打开分享…'**
  String get phoneDiagnosticsSharing;

  /// No description provided for @phoneDiagnosticsSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在存到「下载」…'**
  String get phoneDiagnosticsSaving;

  /// No description provided for @phoneDiagnosticsShare.
  ///
  /// In zh, this message translates to:
  /// **'分享诊断包'**
  String get phoneDiagnosticsShare;

  /// No description provided for @phoneDiagnosticsShareHint.
  ///
  /// In zh, this message translates to:
  /// **'附在问题反馈里'**
  String get phoneDiagnosticsShareHint;

  /// No description provided for @phoneDiagnosticsSave.
  ///
  /// In zh, this message translates to:
  /// **'存到「下载」'**
  String get phoneDiagnosticsSave;

  /// No description provided for @phoneDiagnosticsSaveHint.
  ///
  /// In zh, this message translates to:
  /// **'存进 下载/DeepSeek-harness'**
  String get phoneDiagnosticsSaveHint;

  /// No description provided for @phoneDiagnosticsNote.
  ///
  /// In zh, this message translates to:
  /// **'含版本、设备、日志和最近一次崩溃，不含 Key 和令牌'**
  String get phoneDiagnosticsNote;

  /// No description provided for @phoneDiagnosticsExport.
  ///
  /// In zh, this message translates to:
  /// **'导出诊断包'**
  String get phoneDiagnosticsExport;

  /// No description provided for @phoneSafeMode.
  ///
  /// In zh, this message translates to:
  /// **'安全模式'**
  String get phoneSafeMode;

  /// No description provided for @phoneEngineInstallRuntime.
  ///
  /// In zh, this message translates to:
  /// **'安装运行环境'**
  String get phoneEngineInstallRuntime;

  /// No description provided for @phoneEngineNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get phoneEngineNotInstalled;

  /// No description provided for @phoneEngineInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装'**
  String get phoneEngineInstalling;

  /// No description provided for @phoneEngineStoppedSafe.
  ///
  /// In zh, this message translates to:
  /// **'已停止 · 安全模式'**
  String get phoneEngineStoppedSafe;

  /// No description provided for @phoneEngineStartingSafe.
  ///
  /// In zh, this message translates to:
  /// **'正在以安全模式启动'**
  String get phoneEngineStartingSafe;

  /// No description provided for @phoneEngineStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动'**
  String get phoneEngineStarting;

  /// No description provided for @phoneEngineRunningProbation.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · 试用'**
  String get phoneEngineRunningProbation;

  /// No description provided for @phoneEngineStartupFailed.
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get phoneEngineStartupFailed;

  /// No description provided for @phoneEngineCrashed.
  ///
  /// In zh, this message translates to:
  /// **'已崩溃'**
  String get phoneEngineCrashed;

  /// No description provided for @phoneEngineKilled.
  ///
  /// In zh, this message translates to:
  /// **'被系统结束'**
  String get phoneEngineKilled;

  /// No description provided for @phoneEngineError.
  ///
  /// In zh, this message translates to:
  /// **'出错了'**
  String get phoneEngineError;

  /// No description provided for @phoneEngineRuntimeCorrupt.
  ///
  /// In zh, this message translates to:
  /// **'App 内的运行环境包已损坏，请重新安装 App'**
  String get phoneEngineRuntimeCorrupt;

  /// No description provided for @phoneEngineExited.
  ///
  /// In zh, this message translates to:
  /// **'引擎意外退出了'**
  String get phoneEngineExited;

  /// No description provided for @phoneEngineRuntimeMissing.
  ///
  /// In zh, this message translates to:
  /// **'运行环境还没有安装'**
  String get phoneEngineRuntimeMissing;

  /// No description provided for @phoneEngineSafeUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'这个版本的运行环境不支持安全模式，请更新 App'**
  String get phoneEngineSafeUnsupported;

  /// No description provided for @phoneEngineRuntimeIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'App 内的运行环境包不完整，请重新安装 App'**
  String get phoneEngineRuntimeIncomplete;

  /// No description provided for @phoneLogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有日志'**
  String get phoneLogEmpty;

  /// No description provided for @phoneLogShareTitle.
  ///
  /// In zh, this message translates to:
  /// **'DSH 引擎日志'**
  String get phoneLogShareTitle;

  /// No description provided for @phoneLogCopyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get phoneLogCopyAll;

  /// No description provided for @phoneFailureLaunch.
  ///
  /// In zh, this message translates to:
  /// **'本机运行环境未能启动'**
  String get phoneFailureLaunch;

  /// No description provided for @phoneAccentMist.
  ///
  /// In zh, this message translates to:
  /// **'雾蓝'**
  String get phoneAccentMist;

  /// No description provided for @phoneAccentDaiqing.
  ///
  /// In zh, this message translates to:
  /// **'黛青'**
  String get phoneAccentDaiqing;

  /// No description provided for @phoneAccentDusk.
  ///
  /// In zh, this message translates to:
  /// **'暮紫'**
  String get phoneAccentDusk;

  /// No description provided for @phoneAccentTurquoise.
  ///
  /// In zh, this message translates to:
  /// **'松石'**
  String get phoneAccentTurquoise;

  /// No description provided for @phoneAccentAmber.
  ///
  /// In zh, this message translates to:
  /// **'琥珀'**
  String get phoneAccentAmber;

  /// No description provided for @phoneAccentGraphite.
  ///
  /// In zh, this message translates to:
  /// **'石墨'**
  String get phoneAccentGraphite;

  /// No description provided for @phoneAccentCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get phoneAccentCustom;

  /// No description provided for @phoneEngineInstallPercent.
  ///
  /// In zh, this message translates to:
  /// **'正在安装 · {percent}%'**
  String phoneEngineInstallPercent(int percent);

  /// No description provided for @phoneEngineStatusSemantics.
  ///
  /// In zh, this message translates to:
  /// **'{prefix}引擎：{status}'**
  String phoneEngineStatusSemantics(String prefix, String status);

  /// No description provided for @phoneLogLineCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 行'**
  String phoneLogLineCount(int count);

  /// No description provided for @phoneLogCopiedLines.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {count} 行'**
  String phoneLogCopiedLines(int count);

  /// No description provided for @phoneEngineStorageDetails.
  ///
  /// In zh, this message translates to:
  /// **'存储空间不足：需要约 {needed} MB，当前可用 {free} MB'**
  String phoneEngineStorageDetails(String needed, String free);

  /// No description provided for @pluginsAllowHighPower.
  ///
  /// In zh, this message translates to:
  /// **'允许后台高耗电'**
  String get pluginsAllowHighPower;

  /// No description provided for @pluginsVivoBatteryPath.
  ///
  /// In zh, this message translates to:
  /// **'电池 › 后台耗电管理 › {app}'**
  String pluginsVivoBatteryPath(String app);

  /// No description provided for @pluginsXiaomiBatterySetting.
  ///
  /// In zh, this message translates to:
  /// **'省电策略：无限制'**
  String get pluginsXiaomiBatterySetting;

  /// No description provided for @pluginsXiaomiBatteryPath.
  ///
  /// In zh, this message translates to:
  /// **'应用管理 › {app} › 省电策略'**
  String pluginsXiaomiBatteryPath(String app);

  /// No description provided for @pluginsHuaweiBatterySetting.
  ///
  /// In zh, this message translates to:
  /// **'允许后台活动'**
  String get pluginsHuaweiBatterySetting;

  /// No description provided for @pluginsHuaweiBatteryPath.
  ///
  /// In zh, this message translates to:
  /// **'电池 › 应用启动管理 › {app}'**
  String pluginsHuaweiBatteryPath(String app);

  /// No description provided for @pluginsOppoBatterySetting.
  ///
  /// In zh, this message translates to:
  /// **'允许后台行为'**
  String get pluginsOppoBatterySetting;

  /// No description provided for @pluginsOppoBatteryPath.
  ///
  /// In zh, this message translates to:
  /// **'电池 › 应用耗电管理 › {app}'**
  String pluginsOppoBatteryPath(String app);

  /// No description provided for @pluginsQrCode.
  ///
  /// In zh, this message translates to:
  /// **'二维码'**
  String get pluginsQrCode;

  /// No description provided for @remoteConnectComputer.
  ///
  /// In zh, this message translates to:
  /// **'连接电脑或服务器'**
  String get remoteConnectComputer;

  /// No description provided for @remoteServerAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get remoteServerAddress;

  /// No description provided for @remoteHost.
  ///
  /// In zh, this message translates to:
  /// **'主机'**
  String get remoteHost;

  /// No description provided for @remoteDirectoryRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近'**
  String get remoteDirectoryRecent;

  /// No description provided for @remotePairCameraFailed.
  ///
  /// In zh, this message translates to:
  /// **'相机打不开。可以用「从相册识别」或「粘贴配对链接」'**
  String get remotePairCameraFailed;

  /// No description provided for @remotePairConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'要连接这台电脑吗？'**
  String get remotePairConfirmTitle;

  /// No description provided for @remotePairComputer.
  ///
  /// In zh, this message translates to:
  /// **'电脑'**
  String get remotePairComputer;

  /// No description provided for @phoneRuntimeUpgradeBase.
  ///
  /// In zh, this message translates to:
  /// **'新引擎与现有 Linux 环境不能确认兼容，更新已停止。原环境和已装工具没有删除。请先完整备份，再联系维护者迁移；不要直接重置或卸载 App。'**
  String get phoneRuntimeUpgradeBase;

  /// No description provided for @phoneRuntimeUpgradeManifest.
  ///
  /// In zh, this message translates to:
  /// **'无法安全识别运行时更新清单，更新已停止，原环境保留。请核对安装包并联系维护者，不要直接重置。'**
  String get phoneRuntimeUpgradeManifest;

  /// No description provided for @phoneRuntimeUpgradeInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'运行时升级尚未完成，数据与恢复现场已保留。请重试安装；仍失败时导出诊断并联系维护者，不要重置或删除恢复目录。'**
  String get phoneRuntimeUpgradeInterrupted;

  /// No description provided for @phoneRuntimeUpgradeSymlink.
  ///
  /// In zh, this message translates to:
  /// **'现有环境的系统路径已被自定义链接替换，无法安全更新。原环境保留，请先备份并联系维护者处理。'**
  String get phoneRuntimeUpgradeSymlink;

  /// No description provided for @phoneRuntimeUpgradeRunning.
  ///
  /// In zh, this message translates to:
  /// **'引擎或遗留进程尚未确认停止，更新未开始。请先停止本机引擎，等待清理完成后重试；不要重置环境。'**
  String get phoneRuntimeUpgradeRunning;

  /// No description provided for @setupCapsulePreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备运行环境'**
  String get setupCapsulePreparing;

  /// No description provided for @setupCapsuleProgress.
  ///
  /// In zh, this message translates to:
  /// **'运行环境 {percent}%'**
  String setupCapsuleProgress(int percent);

  /// No description provided for @setupCapsuleProgressSemantics.
  ///
  /// In zh, this message translates to:
  /// **'正在准备运行环境，已完成 {percent}%'**
  String setupCapsuleProgressSemantics(int percent);

  /// No description provided for @setupCapsuleReady.
  ///
  /// In zh, this message translates to:
  /// **'运行环境已就绪'**
  String get setupCapsuleReady;

  /// No description provided for @setupCapsuleFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装未完成'**
  String get setupCapsuleFailed;

  /// No description provided for @setupWaitingBody.
  ///
  /// In zh, this message translates to:
  /// **'完成后自动进入'**
  String get setupWaitingBody;

  /// No description provided for @setupNotifyWhenDone.
  ///
  /// In zh, this message translates to:
  /// **'完成时会通知你'**
  String get setupNotifyWhenDone;

  /// No description provided for @shellOnboardingStep.
  ///
  /// In zh, this message translates to:
  /// **'第 {step} 步，共 {steps} 步'**
  String shellOnboardingStep(int step, int steps);

  /// No description provided for @shellRuntimeUpdating.
  ///
  /// In zh, this message translates to:
  /// **'正在更新运行环境'**
  String get shellRuntimeUpdating;

  /// No description provided for @shellRuntimePreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备运行环境'**
  String get shellRuntimePreparing;

  /// No description provided for @shellRuntimeReady.
  ///
  /// In zh, this message translates to:
  /// **'准备就绪'**
  String get shellRuntimeReady;

  /// No description provided for @shellRuntimeIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'安装未完成'**
  String get shellRuntimeIncomplete;

  /// No description provided for @shellRuntimeFilesKept.
  ///
  /// In zh, this message translates to:
  /// **'对话和文件都会保留'**
  String get shellRuntimeFilesKept;

  /// No description provided for @shellRuntimeFirstSetup.
  ///
  /// In zh, this message translates to:
  /// **'首次准备约需一两分钟'**
  String get shellRuntimeFirstSetup;

  /// No description provided for @shellRuntimeContinuing.
  ///
  /// In zh, this message translates to:
  /// **'即将继续'**
  String get shellRuntimeContinuing;

  /// No description provided for @shellRuntimeRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能放回保留的内容'**
  String get shellRuntimeRestoreFailed;

  /// No description provided for @shellRuntimeExtractFailed.
  ///
  /// In zh, this message translates to:
  /// **'解压时出错'**
  String get shellRuntimeExtractFailed;

  /// No description provided for @shellInstallLogs.
  ///
  /// In zh, this message translates to:
  /// **'安装日志'**
  String get shellInstallLogs;

  /// No description provided for @shellRuntimeLocalOnly.
  ///
  /// In zh, this message translates to:
  /// **'全程在本机完成'**
  String get shellRuntimeLocalOnly;

  /// No description provided for @shellRuntimeContinueWithoutKept.
  ///
  /// In zh, this message translates to:
  /// **'不保留，继续安装'**
  String get shellRuntimeContinueWithoutKept;

  /// No description provided for @shellRuntimeAlmostDone.
  ///
  /// In zh, this message translates to:
  /// **'马上就好'**
  String get shellRuntimeAlmostDone;

  /// No description provided for @shellRuntimeSecondsRemaining.
  ///
  /// In zh, this message translates to:
  /// **'约 {count} 秒'**
  String shellRuntimeSecondsRemaining(int count);

  /// No description provided for @shellRuntimeMinutesRemaining.
  ///
  /// In zh, this message translates to:
  /// **'约 {count} 分钟'**
  String shellRuntimeMinutesRemaining(int count);

  /// No description provided for @shellEngineLogs.
  ///
  /// In zh, this message translates to:
  /// **'引擎日志'**
  String get shellEngineLogs;

  /// No description provided for @shellWelcomeMessage.
  ///
  /// In zh, this message translates to:
  /// **'把 DeepSeek 智能体\n装进口袋'**
  String get shellWelcomeMessage;

  /// No description provided for @shellGetStarted.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get shellGetStarted;

  /// No description provided for @phoneStartupFailureStopping.
  ///
  /// In zh, this message translates to:
  /// **'启动失败，正在停止'**
  String get phoneStartupFailureStopping;

  /// No description provided for @phoneStartupTokenTimeout.
  ///
  /// In zh, this message translates to:
  /// **'启动等待已超时（180 秒内未收到启动标记），请查看日志'**
  String get phoneStartupTokenTimeout;

  /// No description provided for @phoneStartupPortNotReady.
  ///
  /// In zh, this message translates to:
  /// **'已收到启动标记，但本机服务端口尚未就绪，请查看日志'**
  String get phoneStartupPortNotReady;

  /// No description provided for @stateDiagnosticsSubject.
  ///
  /// In zh, this message translates to:
  /// **'DeepSeek harness 诊断包'**
  String get stateDiagnosticsSubject;

  /// No description provided for @stateStoragePermission.
  ///
  /// In zh, this message translates to:
  /// **'没有存储权限，存不进「下载」'**
  String get stateStoragePermission;

  /// No description provided for @stateDiagnosticsStorageFull.
  ///
  /// In zh, this message translates to:
  /// **'存储空间不足，没能生成诊断包'**
  String get stateDiagnosticsStorageFull;

  /// No description provided for @stateDiagnosticsExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能导出诊断包'**
  String get stateDiagnosticsExportFailed;

  /// No description provided for @stateFileOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开这个文件'**
  String get stateFileOpenFailed;

  /// No description provided for @stateLinkOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开这个链接'**
  String get stateLinkOpenFailed;

  /// No description provided for @stateAlertPublicDone.
  ///
  /// In zh, this message translates to:
  /// **'有一轮完成了'**
  String get stateAlertPublicDone;

  /// No description provided for @stateAlertPublicFailed.
  ///
  /// In zh, this message translates to:
  /// **'有一轮出错了'**
  String get stateAlertPublicFailed;

  /// No description provided for @stateAlertPublicStopped.
  ///
  /// In zh, this message translates to:
  /// **'有一轮停下了'**
  String get stateAlertPublicStopped;

  /// No description provided for @stateAlertPublicApproval.
  ///
  /// In zh, this message translates to:
  /// **'有一步等你确认'**
  String get stateAlertPublicApproval;

  /// No description provided for @stateAlertPublicQuestion.
  ///
  /// In zh, this message translates to:
  /// **'有个问题等你回答'**
  String get stateAlertPublicQuestion;

  /// No description provided for @stateAlertTurnDone.
  ///
  /// In zh, this message translates to:
  /// **'这一轮已完成'**
  String get stateAlertTurnDone;

  /// No description provided for @stateAlertOutputLimit.
  ///
  /// In zh, this message translates to:
  /// **'已结束 · 达到单次输出长度上限'**
  String get stateAlertOutputLimit;

  /// No description provided for @stateAlertTurnBlocked.
  ///
  /// In zh, this message translates to:
  /// **'这一轮被拦截了'**
  String get stateAlertTurnBlocked;

  /// No description provided for @stateAlertEngineRestarted.
  ///
  /// In zh, this message translates to:
  /// **'已中断 · 引擎重启过'**
  String get stateAlertEngineRestarted;

  /// No description provided for @stateAlertMissingKey.
  ///
  /// In zh, this message translates to:
  /// **'出错了 · 还没有配置密钥'**
  String get stateAlertMissingKey;

  /// No description provided for @stateAlertTurnFailed.
  ///
  /// In zh, this message translates to:
  /// **'这一轮出错了'**
  String get stateAlertTurnFailed;

  /// No description provided for @stateRunCommand.
  ///
  /// In zh, this message translates to:
  /// **'运行命令'**
  String get stateRunCommand;

  /// No description provided for @stateWriteFile.
  ///
  /// In zh, this message translates to:
  /// **'写入文件'**
  String get stateWriteFile;

  /// No description provided for @stateEditFile.
  ///
  /// In zh, this message translates to:
  /// **'修改文件'**
  String get stateEditFile;

  /// No description provided for @stateOpenPage.
  ///
  /// In zh, this message translates to:
  /// **'打开网页'**
  String get stateOpenPage;

  /// No description provided for @stateWebSearch.
  ///
  /// In zh, this message translates to:
  /// **'联网搜索'**
  String get stateWebSearch;

  /// No description provided for @stateAlertQuestion.
  ///
  /// In zh, this message translates to:
  /// **'问你一个问题'**
  String get stateAlertQuestion;

  /// No description provided for @stateWallpaper.
  ///
  /// In zh, this message translates to:
  /// **'壁纸'**
  String get stateWallpaper;

  /// No description provided for @stateShareFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'有文件太大，未添加'**
  String get stateShareFileTooLarge;

  /// No description provided for @stateShareFileUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'有文件没能读取'**
  String get stateShareFileUnreadable;

  /// No description provided for @stateProviderUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'以 http:// 或 https:// 开头的完整地址'**
  String get stateProviderUrlInvalid;

  /// No description provided for @stateDiagnosticsSaved.
  ///
  /// In zh, this message translates to:
  /// **'已存到 {where}'**
  String stateDiagnosticsSaved(String where);

  /// No description provided for @stateDownloadsPrefix.
  ///
  /// In zh, this message translates to:
  /// **'下载/'**
  String get stateDownloadsPrefix;

  /// No description provided for @stateAlertCompletedReply.
  ///
  /// In zh, this message translates to:
  /// **'已完成 · {reply}'**
  String stateAlertCompletedReply(String reply);

  /// No description provided for @stateAlertErrorDetail.
  ///
  /// In zh, this message translates to:
  /// **'出错了 · {detail}'**
  String stateAlertErrorDetail(String detail);

  /// No description provided for @stateAlertUseTool.
  ///
  /// In zh, this message translates to:
  /// **'使用工具 {name}'**
  String stateAlertUseTool(String name);

  /// No description provided for @stateAlertApprovalAction.
  ///
  /// In zh, this message translates to:
  /// **'等你确认：{action}'**
  String stateAlertApprovalAction(String action);

  /// No description provided for @stateAlertApprovalReason.
  ///
  /// In zh, this message translates to:
  /// **'等你确认：{action} · {reason}'**
  String stateAlertApprovalReason(String action, String reason);

  /// No description provided for @stateAlertQuestions.
  ///
  /// In zh, this message translates to:
  /// **'问你：{question}（共 {count} 个）'**
  String stateAlertQuestions(String question, int count);

  /// No description provided for @stateAlertQuestionText.
  ///
  /// In zh, this message translates to:
  /// **'问你：{question}'**
  String stateAlertQuestionText(String question);

  /// No description provided for @stateAttachmentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」是空文件'**
  String stateAttachmentEmpty(String name);

  /// No description provided for @stateAttachmentImageLimit.
  ///
  /// In zh, this message translates to:
  /// **'图片「{name}」超过 20 MB'**
  String stateAttachmentImageLimit(String name);

  /// No description provided for @stateAttachmentFileLimit.
  ///
  /// In zh, this message translates to:
  /// **'文件「{name}」超过 200 MB'**
  String stateAttachmentFileLimit(String name);

  /// No description provided for @stateAttachmentTotalLimit.
  ///
  /// In zh, this message translates to:
  /// **'附件总大小超过 400 MB'**
  String get stateAttachmentTotalLimit;

  /// No description provided for @stateShareReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能读取「{name}」'**
  String stateShareReadFailed(String name);

  /// No description provided for @stateShareAttachmentLimit.
  ///
  /// In zh, this message translates to:
  /// **'每条消息最多 {count} 个附件'**
  String stateShareAttachmentLimit(int count);

  /// No description provided for @stateShareNamedFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」太大，未添加'**
  String stateShareNamedFileTooLarge(String name);

  /// No description provided for @stateAlertPreviewRun.
  ///
  /// In zh, this message translates to:
  /// **'运行：{value}'**
  String stateAlertPreviewRun(String value);

  /// No description provided for @stateAlertPreviewWrite.
  ///
  /// In zh, this message translates to:
  /// **'写入：{value}'**
  String stateAlertPreviewWrite(String value);

  /// No description provided for @stateAlertPreviewEdit.
  ///
  /// In zh, this message translates to:
  /// **'修改：{value}'**
  String stateAlertPreviewEdit(String value);

  /// No description provided for @stateAlertPreviewOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开：{value}'**
  String stateAlertPreviewOpen(String value);

  /// No description provided for @stateAlertPreviewUse.
  ///
  /// In zh, this message translates to:
  /// **'使用工具：{value}'**
  String stateAlertPreviewUse(String value);

  /// No description provided for @webConfigDocumentTitle.
  ///
  /// In zh, this message translates to:
  /// **'配置文件'**
  String get webConfigDocumentTitle;

  /// No description provided for @webConfigDocumentReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只读 · 当前运行配置'**
  String get webConfigDocumentReadOnly;

  /// No description provided for @webConfigDocumentReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'配置文件没有打开，请确认本机引擎仍在运行后重试。'**
  String get webConfigDocumentReadFailed;

  /// No description provided for @localWebExploreBeyond.
  ///
  /// In zh, this message translates to:
  /// **'探索未至之境'**
  String get localWebExploreBeyond;

  /// No description provided for @webComputerCheckConnection.
  ///
  /// In zh, this message translates to:
  /// **'检查手机与电脑的网络连接，并确认电脑网页服务已开启'**
  String get webComputerCheckConnection;

  /// No description provided for @webTitle.
  ///
  /// In zh, this message translates to:
  /// **'DSH 网页版'**
  String get webTitle;

  /// No description provided for @webLocalAppOnly.
  ///
  /// In zh, this message translates to:
  /// **'本机地址带启动令牌，只能在 App 内打开'**
  String get webLocalAppOnly;

  /// No description provided for @webEngineStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'引擎没能启动'**
  String get webEngineStartFailed;

  /// No description provided for @webAttachmentTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'附件太大，没能带进网页版'**
  String get webAttachmentTooLarge;

  /// No description provided for @webTextCopied.
  ///
  /// In zh, this message translates to:
  /// **'文字已复制，粘贴到输入框即可'**
  String get webTextCopied;

  /// No description provided for @webAttachmentFailed.
  ///
  /// In zh, this message translates to:
  /// **'附件没能带进网页版'**
  String get webAttachmentFailed;

  /// No description provided for @webPageClosed.
  ///
  /// In zh, this message translates to:
  /// **'网页已关闭'**
  String get webPageClosed;

  /// No description provided for @webChatsWorkspaces.
  ///
  /// In zh, this message translates to:
  /// **'对话与工作区'**
  String get webChatsWorkspaces;

  /// No description provided for @webRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get webRefresh;

  /// No description provided for @webOpenInBrowser.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器打开'**
  String get webOpenInBrowser;

  /// No description provided for @webBrowserUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不能在浏览器打开'**
  String get webBrowserUnavailable;

  /// No description provided for @webReopen.
  ///
  /// In zh, this message translates to:
  /// **'重新打开'**
  String get webReopen;

  /// No description provided for @webPageNotOpened.
  ///
  /// In zh, this message translates to:
  /// **'页面没有打开'**
  String get webPageNotOpened;

  /// No description provided for @webCheckConnection.
  ///
  /// In zh, this message translates to:
  /// **'检查网络或引擎状态后再试'**
  String get webCheckConnection;

  /// No description provided for @webTargetSessionMissing.
  ///
  /// In zh, this message translates to:
  /// **'网页版里没找到这个对话，已停在首页'**
  String get webTargetSessionMissing;

  /// No description provided for @webTargetNotLoaded.
  ///
  /// In zh, this message translates to:
  /// **'网页版没有加载完成'**
  String get webTargetNotLoaded;

  /// No description provided for @webTargetSettingsMissing.
  ///
  /// In zh, this message translates to:
  /// **'没找到这页设置，可能需要先登录或开启对应插件'**
  String get webTargetSettingsMissing;

  /// No description provided for @webTargetNewChatFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能新建对话，已停在网页版首页'**
  String get webTargetNewChatFailed;

  /// No description provided for @webTargetPageFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能直接打开这一页，已停在网页版首页'**
  String get webTargetPageFailed;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'zh':
      return L10nZh();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
