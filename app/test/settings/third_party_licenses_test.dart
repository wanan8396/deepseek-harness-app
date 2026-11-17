// Current phone-shell and native dependency notices stay aligned with the root inventory.

import 'dart:io';

import 'package:dsh_app/ui/common/third_party_licenses.dart';
import 'package:dsh_app/ui/settings/font_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _expected = <String, String>{
  'PiPilot': 'Copyright (c) 2026 CikeSeven',
  'DeepSeek Harness': 'Copyright (c) 2026 DeepSeek',
  'Phosphor Icons': 'Copyright (c) 2023 Phosphor Icons',
  'Material Icons': 'Material Icons',
  'AndroidX WebKit': 'AndroidX WebKit',
  'XZ for Java': 'Copyright (C) The XZ for Java authors and contributors',
  'Google ML Kit Barcode Scanning': 'com.google.mlkit:barcode-scanning:17.3.0',
  'JetBrains Mono': 'Copyright 2020 The JetBrains Mono Project Authors',
};

const _mit = 'Permission is hereby granted, free of charge';
const _apache = 'Apache License\n                           Version 2.0, January 2004';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<LicenseEntryWithLineBreaks> entries;

  setUpAll(() async {
    LicenseRegistry.reset();
    registerThirdPartyLicenses();
    registerFontLicenses();
    entries = (await LicenseRegistry.licenses.toList()).cast<LicenseEntryWithLineBreaks>();
  });
  tearDownAll(LicenseRegistry.reset);

  String textOf(String package) => entries.singleWhere((entry) => entry.packages.contains(package)).text;

  test('only current shell source and native-library notices are registered', () {
    final names = {for (final entry in entries) ...entry.packages};
    expect(names, _expected.keys.toSet());
    for (final package in _expected.keys) {
      expect(entries.where((entry) => entry.packages.contains(package)), hasLength(1), reason: package);
    }
  });

  test('attribution lines agree with THIRD_PARTY_NOTICES.md', () {
    final notices = File('../THIRD_PARTY_NOTICES.md').readAsStringSync();
    for (final MapEntry(key: package, value: marker) in _expected.entries) {
      expect(textOf(package), contains(marker), reason: package);
      expect(notices, contains(marker), reason: package);
    }
  });

  test('MIT and Apache entries carry their corresponding terms', () {
    for (final package in ['PiPilot', 'DeepSeek Harness', 'Phosphor Icons']) {
      expect(textOf(package), contains(_mit), reason: package);
      expect(textOf(package), isNot(contains(_apache)), reason: package);
    }
    for (final package in ['Material Icons', 'AndroidX WebKit']) {
      expect(textOf(package), contains(_apache), reason: package);
    }
  });

  test('XZ, ML Kit, and JetBrains Mono retain their current notices', () {
    expect(textOf('XZ for Java'), contains('Permission to use, copy, modify, and/or distribute'));
    final mlKit = textOf('Google ML Kit Barcode Scanning');
    expect(mlKit, contains('https://developers.google.com/ml-kit/terms'));
    expect(mlKit, contains('https://developers.google.com/ml-kit/android-data-disclosure'));
    expect(mlKit, contains('com.google.mlkit:common:18.11.0'));
    expect(mlKit, isNot(contains(_apache)));

    final font = textOf('JetBrains Mono');
    expect(font, contains('SIL OPEN FONT LICENSE Version 1.1'));
    // The asset keeps CRLF; the registered notice carries it too, so compare
    // normalized text instead of rewriting the license body.
    String lf(String value) => value.replaceAll('\r\n', '\n').trim();
    expect(lf(font), contains(lf(File('assets/fonts/OFL.txt').readAsStringSync())));
  });
}
