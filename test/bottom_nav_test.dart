import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:toomu/app/core/theme/app_theme.dart';
import 'package:toomu/app/widgets/app_bottom_nav.dart';

const _items = [
  AppNavItem(label: 'Home', icon: Iconsax.home_2_copy, activeIcon: Iconsax.home_2),
  AppNavItem(label: 'Downloads', icon: Iconsax.document_download_copy, activeIcon: Iconsax.document_download),
  AppNavItem(label: 'Videos', icon: Iconsax.video_play_copy, activeIcon: Iconsax.video_play),
  AppNavItem(label: 'Music', icon: Iconsax.music_copy, activeIcon: Iconsax.music),
  AppNavItem(label: 'Settings', icon: Iconsax.setting_2_copy, activeIcon: Iconsax.setting_2),
];

void main() {
  for (final width in [320.0, 393.0]) {
    testWidgets('5 tabs fit at ${width.toInt()} dp with any tab selected (no overflow)', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var i = 0; i < _items.length; i++) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(items: _items, index: i, onTap: (_) {}),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tab $i selected');
        expect(find.text('Downloads'), findsOneWidget);
      }
    });
  }
}
