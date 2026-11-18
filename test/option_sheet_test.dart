import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/widgets/option_sheet.dart';

void main() {
  Future<void> open(WidgetTester tester, {String? selected}) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    showOptionSheet<String>(
      title: 'Sheet',
      selected: selected,
      options: const [
        SheetOption(value: 'a', label: 'Download', icon: Icons.download_rounded),
        SheetOption(value: 'b', label: 'Share', icon: Icons.share_rounded),
        SheetOption(value: 'c', label: 'Copy link', icon: Icons.link_rounded),
      ],
    );
    await tester.pumpAndSettle();
  }

  // The empty radio circles were what made every sheet look like a list of settings to pick from.
  Finder markers() => find.byWidgetPredicate((w) => w is AnimatedContainer || (w is Icon && w.icon == Icons.check_rounded));

  testWidgets('an action menu (no current choice) is plain rows, nothing that looks selectable', (tester) async {
    await open(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(markers(), findsNothing);
  });

  testWidgets('a choice list marks only the current choice, with a check', (tester) async {
    await open(tester, selected: 'b');
    expect(markers(), findsOneWidget);
    final row = find.ancestor(of: find.text('Share'), matching: find.byType(InkWell));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
    expect(tester.getSemantics(find.text('Share')).flagsCollection.isSelected, Tristate.isTrue);
  });
}
