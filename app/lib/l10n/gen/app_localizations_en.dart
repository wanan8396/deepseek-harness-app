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
  String get iosLocalTitle => 'On-device engine for iPhone / iPad';

  @override
  String get iosLocalScope =>
      'Checks Node.js embedded in this device directly, without connecting to a computer or remote engine.';

  @override
  String get iosLocalChecking => 'Reading on-device status';

  @override
  String get iosLocalProbeIdle => 'Local probe has not run';

  @override
  String get iosLocalProbeIdleDetail => 'Run the probe to verify that Node.js embedded in this app actually executes.';

  @override
  String get iosLocalProbeRunning => 'Running the local probe';

  @override
  String get iosLocalProbeRunningDetail =>
      'The iOS native layer runs embedded Node.js and reads the result of this execution.';

  @override
  String get iosLocalProbePassed => 'Embedded Node.js probe completed';

  @override
  String get iosLocalProbeCompatible =>
      'The Node.js version and checked capabilities meet the current requirements. Individual DSH verification results are shown below.';

  @override
  String get iosLocalProbeUnavailable => 'Local probe is not ready';

  @override
  String get iosLocalNodeVersionMismatch =>
      'The embedded Node.js version does not meet DSH requirements. Update the native runtime first.';

  @override
  String get iosLocalCapabilitiesMissing =>
      'The checked capabilities of embedded Node.js do not yet meet DSH requirements.';

  @override
  String get iosLocalProbeTimeout =>
      'Reading or running the probe timed out. Refresh to read the native layer’s actual result.';

  @override
  String get iosLocalProbeFailed => 'The local probe failed. Refresh to read the result of this native check.';

  @override
  String get iosLocalRuntimeUnavailable =>
      'On-device runtime status is unavailable in this installation. Refresh to retry; no remote engine will replace it here.';

  @override
  String iosLocalNodeVersion(String version) {
    return 'Actual Node.js: $version';
  }

  @override
  String iosLocalRequiredNode(String range) {
    return 'Node.js required by DSH: $range';
  }

  @override
  String iosLocalDshVersion(String version) {
    return 'Target DSH: $version';
  }

  @override
  String get iosLocalNotDetected => 'Not checked yet';

  @override
  String get iosLocalDiagnosticsTitle => 'Diagnostics, not chat status';

  @override
  String get iosLocalProbeOnly =>
      'Diagnostics use separate test sessions that close when the checks finish. Open On-device chat to check the chat runtime and send a real message.';

  @override
  String get iosLocalCapabilitiesTitle => 'Native capability checks for this run';

  @override
  String get iosLocalCapabilityFileSystem => 'App-local file reads and writes';

  @override
  String get iosLocalCapabilityIntl => 'Intl internationalization';

  @override
  String get iosLocalCapabilityBuiltinModule => 'Node built-in module access';

  @override
  String get iosLocalCapabilitySqlite => 'Node built-in SQLite';

  @override
  String get iosLocalCapabilitySqliteFts => 'SQLite FTS5 full-text search';

  @override
  String get iosLocalCapabilityImportMain => 'ES module entry-point detection';

  @override
  String get iosLocalCapabilityImportFilename => 'ES module filename';

  @override
  String get iosLocalCapabilityImportDirname => 'ES module directory name';

  @override
  String get iosLocalCheckPassed => 'Passed';

  @override
  String get iosLocalCheckFailed => 'Not passed';

  @override
  String get iosLocalCheckNotRun => 'Not checked';

  @override
  String get iosLocalLoaderTitle => 'Official DSH Loader validation';

  @override
  String get iosLocalLoaderDetail =>
      'Checks only a minimal Loader’s boot, services, cleanup and failed baseline. This does not mean the full on-device engine is ready.';

  @override
  String get iosLocalLoaderBooted => 'Loader booted';

  @override
  String get iosLocalLoaderService => 'Service verified';

  @override
  String get iosLocalLoaderDispose => 'Loader cleanup verified';

  @override
  String get iosLocalLoaderBadBaseline => 'Failed boot baseline rejected';

  @override
  String get iosLocalCoreTitle => 'DSH core validation (offline)';

  @override
  String get iosLocalCoreDetail =>
      'Uses only in-memory storage and a fixed offline test model, not a real model provider. No model API calls are made. Passing core checks still does not mean the full on-device engine is ready for real chat.';

  @override
  String get iosLocalCoreBooted => 'Core booted';

  @override
  String get iosLocalCoreServices => 'Core services verified';

  @override
  String get iosLocalCoreFirstTurn => 'First-turn streaming verified';

  @override
  String get iosLocalCoreSecondTurn => 'Second-turn history verified';

  @override
  String get iosLocalCoreCancellation => 'Cancellation settled';

  @override
  String get iosLocalCoreError => 'Error settled';

  @override
  String get iosLocalCoreDispose => 'Core cleanup verified';

  @override
  String get iosLocalCoreBadBaseline => 'Failed core boot baseline rejected';

  @override
  String get iosLocalCoreEphemeral => 'In-memory storage only';

  @override
  String get iosLocalStorageTitle => 'On-device session storage validation';

  @override
  String get iosLocalStorageDetail =>
      'Uses temporary SQLite files in the app sandbox and an offline test model to check that history survives closing and reopening the session. Test data is removed and is not chat history.';

  @override
  String get iosLocalStorageBooted => 'SQLite session service booted';

  @override
  String get iosLocalStorageWriter => 'Concurrent writes to one session rejected';

  @override
  String get iosLocalStorageReader => 'Committed history readable during writes';

  @override
  String get iosLocalStorageAtomic => 'Invalid append batch rejected atomically';

  @override
  String get iosLocalStorageFlush => 'Session writes committed to disk';

  @override
  String get iosLocalStorageResume => 'Chat history recovered after reopening';

  @override
  String get iosLocalStorageDispose => 'Storage resources released';

  @override
  String get iosLocalStorageRejected => 'Damaged log rejected';

  @override
  String get iosLocalBackgroundObservation => 'The app was backgrounded when the native layer last read its status.';

  @override
  String get iosLocalBackgroundLimit =>
      'Recheck on-device status after background suspension or system termination. The probe does not promise continuous background execution.';

  @override
  String get iosLocalRunProbe => 'Run local probe';

  @override
  String get iosLocalRefresh => 'Refresh status';

  @override
  String get iosChatOpen => 'On-device chat';

  @override
  String get iosChatScope =>
      'DSH runs on this iPhone or iPad. It sends your messages to the official DeepSeek API over HTTPS for model responses.';

  @override
  String get iosChatKeyLabel => 'DeepSeek API key';

  @override
  String get iosChatKeyHelp =>
      'The key is kept only for this engine session. Stop the chat engine to change it. Starting again restores saved chat history from this device.';

  @override
  String get iosChatStart => 'Start chat engine';

  @override
  String get iosChatStop => 'Stop chat engine';

  @override
  String get iosChatUser => 'You';

  @override
  String get iosChatAssistant => 'DeepSeek';

  @override
  String get iosChatMessageHint => 'Enter a message';

  @override
  String get iosChatSend => 'Send message';

  @override
  String get iosChatCancel => 'Cancel response';

  @override
  String get iosChatStarting => 'Starting the on-device chat engine…';

  @override
  String get iosChatSending => 'Submitting your message…';

  @override
  String get iosChatCancelling => 'Cancelling the response…';

  @override
  String get iosChatStopping => 'Stopping the on-device chat engine…';

  @override
  String get iosChatStateUnknown => 'Chat status is unknown';

  @override
  String get iosChatStopped => 'Chat engine is stopped';

  @override
  String get iosChatReady => 'On-device chat engine is ready. Model access is checked when you send a message.';

  @override
  String get iosChatRunning => 'Waiting for a DeepSeek response…';

  @override
  String get iosChatRefreshNeeded => 'Refresh status before trying again.';

  @override
  String get iosChatPollingPaused => 'Automatic updates paused. Refresh status to continue viewing the response.';

  @override
  String get iosChatKeyInvalid => 'Enter a DeepSeek API key without spaces (up to 1,024 printable ASCII characters).';

  @override
  String get iosChatInputInvalid => 'Enter a message of no more than 8 KB.';

  @override
  String get iosChatBusyError => 'The chat engine is busy.';

  @override
  String get iosChatAuthError =>
      'DeepSeek did not accept the API key. Stop the chat engine, then start it with a valid key.';

  @override
  String get iosChatRateLimitError => 'The DeepSeek API rate or account limit was reached.';

  @override
  String get iosChatNetworkError =>
      'The on-device engine could not reach the DeepSeek API. Check your internet connection.';

  @override
  String get iosChatModelError => 'The DeepSeek API did not return a usable response.';

  @override
  String get iosChatStorageError => 'On-device chat history could not be read or saved.';

  @override
  String get iosChatTimeoutError => 'The request timed out.';

  @override
  String get iosChatUnavailableError => 'The on-device chat bridge is unavailable in this app.';

  @override
  String get iosChatStartupError => 'The on-device chat engine did not start.';

  @override
  String get iosChatSendError => 'The on-device engine did not confirm receipt of the message.';

  @override
  String get iosChatCancelError => 'The on-device engine did not confirm cancellation.';

  @override
  String get iosChatStopError => 'The on-device engine did not confirm that it stopped.';

  @override
  String get iosChatResponseLimitError => 'This chat is too large for the on-device bridge to display.';

  @override
  String get iosChatProtocolError => 'The on-device chat bridge returned an unexpected result.';

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
