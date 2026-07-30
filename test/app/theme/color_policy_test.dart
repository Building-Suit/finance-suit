import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product Dart code contains no local color literals', () {
    final violations = <String>[];
    final literal = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)|#[0-9A-Fa-f]{6,8}\b');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('building_suit_colors.dart')) continue;
      if (entity.path.contains('/l10n/generated/')) continue;
      final contents = entity.readAsStringSync();
      if (literal.hasMatch(contents)) violations.add(entity.path);
    }

    expect(violations, isEmpty);
  });

  test('raw Building Suit palette stays behind the theme boundary', () {
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('/app/theme/')) continue;
      if (entity.path.endsWith('/app/branding/finance_suit_brand.dart')) {
        continue;
      }
      if (entity.readAsStringSync().contains('BuildingSuitColors')) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty);
  });

  test('retired navy product roles are no longer referenced', () {
    final violations = <String>[];
    const retired = [
      'midnightBackground',
      'navySurface',
      'navySurfaceRaised',
      'steelBorder',
    ];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('building_suit_colors.dart')) continue;
      final contents = entity.readAsStringSync();
      if (retired.any(contents.contains)) violations.add(entity.path);
    }

    expect(violations, isEmpty);
  });

  test('non-Dart color literals stay inside the documented allowlist', () {
    const officialArtwork = {
      'assets/branding/finance_suit_app_icon.svg',
      'assets/branding/finance_suit_mark.svg',
      'android/app/src/main/res/drawable/finance_suit_splash_mark.xml',
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
      'android/app/src/main/res/values/colors.xml',
    };
    const legalAdapters = {
      'legal/styles.css',
      'legal/index.html',
      'legal/privacy-policy.html',
      'legal/terms.html',
      'legal/delete-account.html',
    };
    final literal = RegExp(
      r'#[0-9A-Fa-f]{6,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)',
    );
    final violations = <String>[];

    for (final root in ['assets', 'android/app/src/main/res', 'legal']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (!['.css', '.html', '.svg', '.xml'].any(path.endsWith)) continue;
        if (!literal.hasMatch(entity.readAsStringSync())) continue;
        if (!officialArtwork.contains(path) && !legalAdapters.contains(path)) {
          violations.add(path);
        }
      }
    }

    expect(violations, isEmpty);
  });
}
