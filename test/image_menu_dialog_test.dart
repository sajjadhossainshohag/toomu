import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/image_menu.dart';
import 'package:toomu/app/modules/browser/link_menu.dart';
import 'package:toomu/app/modules/browser/views/image_menu_dialog.dart';

// Widget tests apart from image_menu_test.dart: their binding answers every
// real HTTP request there with 400.

/// 1×1 transparent PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  const inline = PageImage(src: 'data:image/png;base64,$_png', alt: 'Poster of Avatar');
  const blob = PageImage(src: 'blob:https://movies.example.com/1234-5678');
  const link = PageLink(href: 'https://movies.example.com/avatar', text: 'Avatar: The Last Airbender');

  Future<List<Object>> pumpMenu(WidgetTester tester, {PageLink? link, PageImage? image}) async {
    final picked = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageMenuDialog(
            link: link,
            image: image,
            entries: pageMenuEntries(link: link, image: image, canCopyImage: true),
            onPick: picked.add,
          ),
        ),
      ),
    );
    return picked;
  }

  List<String?> texts(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

  testWidgets('an image: its alt text, then the image actions in order', (tester) async {
    await pumpMenu(tester, image: inline);
    expect(texts(tester), ['Poster of Avatar', 'Preview image', 'Copy image', 'Download image', 'Share image']);
    expect(find.byType(Image), findsOneWidget, reason: 'inline thumbnail from its bytes');
  });

  testWidgets('a link: its words and address, then Chrome\'s link actions', (tester) async {
    await pumpMenu(tester, link: link);
    expect(texts(tester), [
      'Avatar: The Last Airbender',
      'https://movies.example.com/avatar',
      'Open in new tab',
      'Open in incognito tab',
      'Copy link address',
      'Copy link text',
      'Download link',
      'Share link',
    ]);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
  });

  test('an image inside a link: the link\'s actions, then the image\'s', () {
    const web = PageImage(src: 'https://img.example.com/p.jpg');
    final entries = pageMenuEntries(link: link, image: web, canCopyImage: true);
    expect(entries.map((e) => e.action), [
      LinkAction.openNewTab,
      LinkAction.openIncognito,
      LinkAction.copyAddress,
      LinkAction.copyText,
      LinkAction.download,
      LinkAction.share,
      ImageAction.open,
      ImageAction.preview,
      ImageAction.copy,
      ImageAction.copyLink,
      ImageAction.download,
      ImageAction.lens,
      ImageAction.share,
    ]);
    expect(ImageAction.open.label, 'Open image in new tab');
  });

  testWidgets('tapping a row picks that action', (tester) async {
    final picked = await pumpMenu(tester, link: link);
    await tester.tap(find.text('Open in new tab'));
    expect(picked, [LinkAction.openNewTab]);
  });

  testWidgets('a script-made picture shows an image icon instead', (tester) async {
    await pumpMenu(tester, image: blob);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
