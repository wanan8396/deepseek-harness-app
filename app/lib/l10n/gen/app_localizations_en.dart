// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get accessRootPermissions => 'Local permissions and Root';

  @override
  String get accessRootDone => 'Done';

  @override
  String get accessFeatureFiles => 'Read and write phone files';

  @override
  String get accessFeatureFilesNeeds => 'Needs file access';

  @override
  String get accessFeatureBackground => 'Keep running in background';

  @override
  String get accessFeatureBackgroundNeeds => 'Tells you when tasks finish; needs notifications and background access';

  @override
  String get accessTurnOn => 'Turn on';

  @override
  String get accessViewSettings => 'View settings';

  @override
  String get accessConfirmEnabled => 'I\'ve enabled it';

  @override
  String get accessStateConfirmed => 'Confirmed enabled';

  @override
  String get accessOpenFailed => 'Couldn\'t open system settings';

  @override
  String get accessStorageTitle => 'Allow file access';

  @override
  String get accessStorageWhy => 'Lets AI read and write photos, downloads and documents';

  @override
  String get accessNotifyTitle => 'Allow notifications';

  @override
  String get accessNotifyWhy => 'Tells you when a task finishes or needs you';

  @override
  String get accessBatteryTitle => 'Allow background running';

  @override
  String get accessBatteryWhy => 'Tasks keep going when you switch apps';

  @override
  String get accessVendorBackgroundWhy => 'Keeps the system from cutting tasks off in the background';

  @override
  String get accessAutostartTitle => 'Allow auto-start';

  @override
  String get accessAutostartWhy => 'Lets DeepSeek harness come back after the system clears it';

  @override
  String accessVivoAutostartPath(String app) {
    return 'Permission management › Auto-start › $app';
  }

  @override
  String accessXiaomiAutostartPath(String app) {
    return 'Manage apps › $app › Autostart';
  }

  @override
  String get accessStateOn => 'On';

  @override
  String get accessStateOff => 'Off';

  @override
  String get accessStateVisited => 'Visited';

  @override
  String get accessStateUnknown => 'Set up';

  @override
  String get accessFinishFailed => 'Couldn’t finish setup';

  @override
  String get accessPageTitle => 'System permissions';

  @override
  String get accessPageSubtitle => 'What each feature needs from Android';

  @override
  String get botsDiscardTitle => 'Discard changes?';

  @override
  String get botsKeepEditing => 'Keep editing';

  @override
  String get botsDiscard => 'Discard';

  @override
  String get botsProgress => 'Progress';

  @override
  String get chatErrReasoningEffortUnsupported =>
      'This model does not support the selected reasoning effort. Change the effort or model.';

  @override
  String get chatComposerHint => 'Message DSH…';

  @override
  String get chatErrApiKey => 'API key is invalid or expired';

  @override
  String get chatErrBalance => 'Insufficient balance';

  @override
  String get chatErrAccountQuota => 'Account quota used up';

  @override
  String get chatErrRateLimit => 'Too many requests. Try again later.';

  @override
  String get chatErrContextLength => 'Chat too long. Send /compact, then try again.';

  @override
  String get chatErrModelUnavailable => 'Model service temporarily unavailable';

  @override
  String get chatErrModelTimeout => 'Model response timed out';

  @override
  String get chatErrModelConnection => 'Couldn’t reach the model service';

  @override
  String get chatErrModelEmpty => 'The model returned no content';

  @override
  String get chatErrEngineOutdated => 'This model needs a newer engine';

  @override
  String get chatErrModelUnsupported => 'This model isn’t available';

  @override
  String get chatErrTurn => 'Something went wrong this turn';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonInstall => 'Install';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCollapse => 'Show less';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonStorageFull => 'Not enough storage';

  @override
  String get commonConnectionFailed => 'Couldn’t connect';

  @override
  String get commonUntitledChat => 'Untitled chat';

  @override
  String get commonThisPhone => 'This phone';

  @override
  String get commonStopped => 'Stopped';

  @override
  String get commonRunning => 'Running';

  @override
  String get commonStopping => 'Stopping';

  @override
  String get commonViewLogs => 'View logs';

  @override
  String commonMonthDay(String month, int day) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '$month',
    });
    return '$_temp0 $day';
  }

  @override
  String get companionVoice => 'Voice';

  @override
  String get featuresScheduleRunLocation => 'Run in';

  @override
  String get fileSharedText => 'Shared text.txt';

  @override
  String localEnvThisPhoneDetail(int storage, int memory) {
    return '$storage MB storage · $memory MB memory';
  }

  @override
  String localEnvThisPhoneDetailShort(int memory) {
    return '$memory MB memory while running';
  }

  @override
  String localEnvLowStorage(int needed) {
    return 'Needs about $needed MB free';
  }

  @override
  String get localEnvRemoteDetail => 'Use DSH on your computer or server';

  @override
  String get localEnvInstallTitle => 'Install on this phone';

  @override
  String get localEnvInstallMessage => 'Run DSH right on this phone';

  @override
  String localEnvFactStorage(int storage) {
    return 'About $storage MB of storage';
  }

  @override
  String localEnvFactMemory(int memory) {
    return 'About $memory MB of memory while running';
  }

  @override
  String get localEnvNotInstalled => 'Not installed on this phone';

  @override
  String get mediaVary => 'Vary';

  @override
  String get mediaEdit => 'Edit';

  @override
  String get mediaUpscale => 'Upscale';

  @override
  String get phoneDiagnosticsCollecting => 'Collecting…';

  @override
  String get phoneDiagnosticsPacking => 'Packing…';

  @override
  String get phoneDiagnosticsSharing => 'Opening share sheet…';

  @override
  String get phoneDiagnosticsSaving => 'Saving to Downloads…';

  @override
  String get phoneDiagnosticsShare => 'Share diagnostics bundle';

  @override
  String get phoneDiagnosticsShareHint => 'Attach to a bug report';

  @override
  String get phoneDiagnosticsSave => 'Save to Downloads';

  @override
  String get phoneDiagnosticsSaveHint => 'Save in Downloads/DeepSeek-harness';

  @override
  String get phoneDiagnosticsNote =>
      'Includes versions, device info, logs and the latest crash. No API keys or tokens.';

  @override
  String get phoneDiagnosticsExport => 'Export diagnostics bundle';

  @override
  String get phoneSafeMode => 'Safe mode';

  @override
  String get phoneEngineInstallRuntime => 'Install runtime';

  @override
  String get phoneEngineNotInstalled => 'Not installed';

  @override
  String get phoneEngineInstalling => 'Installing';

  @override
  String get phoneEngineStoppedSafe => 'Stopped · Safe mode';

  @override
  String get phoneEngineStartingSafe => 'Starting in Safe mode';

  @override
  String get phoneEngineStarting => 'Starting';

  @override
  String get phoneEngineRunningProbation => 'Running · Trial';

  @override
  String get phoneEngineStartupFailed => 'Couldn’t start';

  @override
  String get phoneEngineCrashed => 'Crashed';

  @override
  String get phoneEngineKilled => 'Stopped by Android';

  @override
  String get phoneEngineError => 'Something went wrong';

  @override
  String get phoneEngineRuntimeCorrupt => 'The bundled runtime is damaged. Reinstall DSH.';

  @override
  String get phoneEngineExited => 'The engine quit unexpectedly';

  @override
  String get phoneEngineRuntimeMissing => 'The runtime isn’t installed yet';

  @override
  String get phoneEngineSafeUnsupported => 'This runtime doesn’t support Safe mode. Update DSH.';

  @override
  String get phoneEngineRuntimeIncomplete => 'The bundled runtime is incomplete. Reinstall DSH.';

  @override
  String get phoneLogEmpty => 'No logs yet';

  @override
  String get phoneLogShareTitle => 'DSH engine logs';

  @override
  String get phoneLogCopyAll => 'Copy all';

  @override
  String get phoneFailureLaunch => 'Local runtime couldn’t start';

  @override
  String get phoneAccentMist => 'Mist';

  @override
  String get phoneAccentDaiqing => 'Teal';

  @override
  String get phoneAccentDusk => 'Dusk';

  @override
  String get phoneAccentTurquoise => 'Aqua';

  @override
  String get phoneAccentAmber => 'Amber';

  @override
  String get phoneAccentGraphite => 'Slate';

  @override
  String get phoneAccentCustom => 'Custom';

  @override
  String phoneEngineInstallPercent(int percent) {
    return 'Installing · $percent%';
  }

  @override
  String phoneEngineStatusSemantics(String prefix, String status) {
    return '$prefix engine: $status';
  }

  @override
  String phoneLogLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count lines', one: '1 line');
    return '$_temp0';
  }

  @override
  String phoneLogCopiedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copied $count lines',
      one: 'Copied 1 line',
    );
    return '$_temp0';
  }

  @override
  String phoneEngineStorageDetails(String needed, String free) {
    return 'Not enough storage: about $needed MB needed, $free MB available';
  }

  @override
  String get pluginsAllowHighPower => 'Allow high background power usage';

  @override
  String pluginsVivoBatteryPath(String app) {
    return 'Battery › Background power consumption management › $app';
  }

  @override
  String get pluginsXiaomiBatterySetting => 'Battery saver: No restrictions';

  @override
  String pluginsXiaomiBatteryPath(String app) {
    return 'Manage apps › $app › Battery saver';
  }

  @override
  String get pluginsHuaweiBatterySetting => 'Allow background activity';

  @override
  String pluginsHuaweiBatteryPath(String app) {
    return 'Battery › App launch › $app';
  }

  @override
  String get pluginsOppoBatterySetting => 'Allow background activity';

  @override
  String pluginsOppoBatteryPath(String app) {
    return 'Battery › App battery management › $app';
  }

  @override
  String get pluginsQrCode => 'QR code';

  @override
  String get remoteConnectComputer => 'Connect a computer or server';

  @override
  String get remoteServerAddress => 'Server address';

  @override
  String get remoteHost => 'Host';

  @override
  String get remoteDirectoryRecent => 'Recent';

  @override
  String get remotePairCameraFailed => 'The camera didn’t open. Use From photos or Paste pairing link.';

  @override
  String get remotePairConfirmTitle => 'Connect to this computer?';

  @override
  String get remotePairComputer => 'Computer';

  @override
  String get phoneRuntimeUpgradeBase =>
      'The new engine cannot be confirmed compatible with your Linux environment, so the update stopped. Your environment and installed tools were not deleted. Make a full backup and contact the maintainer for migration; do not reset or uninstall the app.';

  @override
  String get phoneRuntimeUpgradeManifest =>
      'The runtime update manifest could not be safely identified. The update stopped and your environment was kept. Check the APK and contact the maintainer; do not reset the environment.';

  @override
  String get phoneRuntimeUpgradeInterrupted =>
      'The runtime upgrade is incomplete. Your data and recovery state were kept. Retry installation. If it still fails, export diagnostics and contact the maintainer; do not reset or delete recovery directories.';

  @override
  String get phoneRuntimeUpgradeSymlink =>
      'A system path was replaced by a custom link, so the environment cannot be updated safely. Your environment was kept. Back it up and contact the maintainer.';

  @override
  String get phoneRuntimeUpgradeRunning =>
      'The engine or a leftover process has not been confirmed stopped. The update has not started. Stop the local engine and wait for cleanup before retrying; do not reset the environment.';

  @override
  String get setupCapsulePreparing => 'Preparing runtime';

  @override
  String setupCapsuleProgress(int percent) {
    return 'Runtime $percent%';
  }

  @override
  String setupCapsuleProgressSemantics(int percent) {
    return 'Preparing the runtime, $percent% done';
  }

  @override
  String get setupCapsuleReady => 'Runtime ready';

  @override
  String get setupCapsuleFailed => 'Install failed';

  @override
  String get setupWaitingBody => 'Continues on its own when ready';

  @override
  String get setupNotifyWhenDone => 'We’ll notify you when it’s done';

  @override
  String shellOnboardingStep(int step, int steps) {
    return 'Step $step of $steps';
  }

  @override
  String get shellRuntimeUpdating => 'Updating runtime';

  @override
  String get shellRuntimePreparing => 'Preparing runtime';

  @override
  String get shellRuntimeReady => 'Ready';

  @override
  String get shellRuntimeIncomplete => 'Installation incomplete';

  @override
  String get shellRuntimeFilesKept => 'Your chats and files stay';

  @override
  String get shellRuntimeFirstSetup => 'First setup takes a minute or two';

  @override
  String get shellRuntimeContinuing => 'Continuing shortly';

  @override
  String get shellRuntimeRestoreFailed => 'Couldn’t restore saved content';

  @override
  String get shellRuntimeExtractFailed => 'Couldn’t extract files';

  @override
  String get shellInstallLogs => 'Installation logs';

  @override
  String get shellRuntimeLocalOnly => 'Everything runs on this phone';

  @override
  String get shellRuntimeContinueWithoutKept => 'Continue without restoring';

  @override
  String get shellRuntimeAlmostDone => 'Almost done';

  @override
  String shellRuntimeSecondsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'About $count seconds',
      one: 'About 1 second',
    );
    return '$_temp0';
  }

  @override
  String shellRuntimeMinutesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'About $count minutes',
      one: 'About 1 minute',
    );
    return '$_temp0';
  }

  @override
  String get shellEngineLogs => 'Engine logs';

  @override
  String get shellWelcomeMessage => 'The DeepSeek agent,\nin your pocket';

  @override
  String get shellGetStarted => 'Start';

  @override
  String get phoneStartupFailureStopping => 'Startup failed; stopping';

  @override
  String get phoneStartupTokenTimeout =>
      'Startup timed out: no startup token arrived within 180 seconds. Check the logs.';

  @override
  String get phoneStartupPortNotReady =>
      'The startup token arrived, but the local service port did not become ready. Check the logs.';

  @override
  String get stateDiagnosticsSubject => 'DeepSeek harness diagnostics bundle';

  @override
  String get stateStoragePermission => 'No storage permission to save to Downloads';

  @override
  String get stateDiagnosticsStorageFull => 'Not enough storage to create the diagnostics bundle';

  @override
  String get stateDiagnosticsExportFailed => 'Couldn’t export diagnostics bundle';

  @override
  String get stateFileOpenFailed => 'Can’t open this file';

  @override
  String get stateLinkOpenFailed => 'Can’t open this link';

  @override
  String get stateAlertPublicDone => 'A turn finished';

  @override
  String get stateAlertPublicFailed => 'A turn failed';

  @override
  String get stateAlertPublicStopped => 'A turn stopped';

  @override
  String get stateAlertPublicApproval => 'A step needs your approval';

  @override
  String get stateAlertPublicQuestion => 'A question needs your answer';

  @override
  String get stateAlertTurnDone => 'This turn finished';

  @override
  String get stateAlertOutputLimit => 'Ended · Output limit reached';

  @override
  String get stateAlertTurnBlocked => 'This turn was blocked';

  @override
  String get stateAlertEngineRestarted => 'Interrupted · Engine restarted';

  @override
  String get stateAlertMissingKey => 'Error · No API key set';

  @override
  String get stateAlertTurnFailed => 'This turn failed';

  @override
  String get stateRunCommand => 'Run command';

  @override
  String get stateWriteFile => 'Write file';

  @override
  String get stateEditFile => 'Edit file';

  @override
  String get stateOpenPage => 'Open web page';

  @override
  String get stateWebSearch => 'Web search';

  @override
  String get stateAlertQuestion => 'A question for you';

  @override
  String get stateWallpaper => 'Wallpaper';

  @override
  String get stateShareFileTooLarge => 'A file was too large and wasn’t added';

  @override
  String get stateShareFileUnreadable => 'Couldn’t read a file';

  @override
  String get stateProviderUrlInvalid => 'Enter a full URL starting with http:// or https://';

  @override
  String stateDiagnosticsSaved(String where) {
    return 'Saved to $where';
  }

  @override
  String get stateDownloadsPrefix => 'Downloads/';

  @override
  String stateAlertCompletedReply(String reply) {
    return 'Completed · $reply';
  }

  @override
  String stateAlertErrorDetail(String detail) {
    return 'Error · $detail';
  }

  @override
  String stateAlertUseTool(String name) {
    return 'Use tool $name';
  }

  @override
  String stateAlertApprovalAction(String action) {
    return 'Needs approval: $action';
  }

  @override
  String stateAlertApprovalReason(String action, String reason) {
    return 'Needs approval: $action · $reason';
  }

  @override
  String stateAlertQuestions(String question, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Question for you: $question ($count total)',
      one: 'Question for you: $question (1 total)',
    );
    return '$_temp0';
  }

  @override
  String stateAlertQuestionText(String question) {
    return 'Question for you: $question';
  }

  @override
  String stateAttachmentEmpty(String name) {
    return '“$name” is empty';
  }

  @override
  String stateAttachmentImageLimit(String name) {
    return 'Image “$name” exceeds 20 MB';
  }

  @override
  String stateAttachmentFileLimit(String name) {
    return 'File “$name” exceeds 200 MB';
  }

  @override
  String get stateAttachmentTotalLimit => 'Attachments exceed 400 MB in total';

  @override
  String stateShareReadFailed(String name) {
    return 'Couldn’t read “$name”';
  }

  @override
  String stateShareAttachmentLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Up to $count attachments per message',
      one: 'Up to 1 attachment per message',
    );
    return '$_temp0';
  }

  @override
  String stateShareNamedFileTooLarge(String name) {
    return '“$name” is too large and wasn’t added';
  }

  @override
  String stateAlertPreviewRun(String value) {
    return 'Run: $value';
  }

  @override
  String stateAlertPreviewWrite(String value) {
    return 'Write: $value';
  }

  @override
  String stateAlertPreviewEdit(String value) {
    return 'Edit: $value';
  }

  @override
  String stateAlertPreviewOpen(String value) {
    return 'Open: $value';
  }

  @override
  String stateAlertPreviewUse(String value) {
    return 'Use tool: $value';
  }

  @override
  String get webConfigDocumentTitle => 'Configuration file';

  @override
  String get webConfigDocumentReadOnly => 'Read only · Current running configuration';

  @override
  String get webConfigDocumentReadFailed =>
      'The configuration file did not open. Check that the local engine is still running and retry.';

  @override
  String get localWebExploreBeyond => 'Explore beyond the known';

  @override
  String get webComputerCheckConnection =>
      'Check the phone and computer network connection and that the computer web service is running';

  @override
  String get webTitle => 'DSH Web';

  @override
  String get webLocalAppOnly => 'This phone’s link has a launch token and only opens in the app';

  @override
  String get webEngineStartFailed => 'Couldn’t start the engine';

  @override
  String get webAttachmentTooLarge => 'Attachment is too large for DSH Web';

  @override
  String get webTextCopied => 'Text copied. Paste it into the input box.';

  @override
  String get webAttachmentFailed => 'Couldn’t add attachments to DSH Web';

  @override
  String get webPageClosed => 'Page closed';

  @override
  String get webChatsWorkspaces => 'Chats and workspaces';

  @override
  String get webRefresh => 'Refresh';

  @override
  String get webOpenInBrowser => 'Open in browser';

  @override
  String get webBrowserUnavailable => 'Can’t open in browser';

  @override
  String get webReopen => 'Reopen';

  @override
  String get webPageNotOpened => 'Couldn’t open the page';

  @override
  String get webCheckConnection => 'Check your network or engine status and try again';

  @override
  String get webTargetSessionMissing => 'Couldn’t find this chat in DSH Web. You’re on the home page.';

  @override
  String get webTargetNotLoaded => 'DSH Web hasn’t finished loading';

  @override
  String get webTargetSettingsMissing => 'Couldn’t find these settings. You may need to sign in or enable the plugin.';

  @override
  String get webTargetNewChatFailed => 'Couldn’t start a chat. You’re on the DSH Web home page.';

  @override
  String get webTargetPageFailed => 'Couldn’t open this page. You’re on the DSH Web home page.';
}
