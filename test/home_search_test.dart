import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';

class _Home extends HomeController {
  final browsed = <String>[];

  @override
  // ignore: must_call_super
  void onReady() {}

  @override
  Future<bool> openLinkFrom(String text) async => false; // not a video/download link

  @override
  Future<void> openInBrowser(String url) async => browsed.add(url);
}

void main() {
  late _Home home;

  setUp(() => home = Get.put(_Home()));
  tearDown(Get.reset);

  test("words typed in Home's search bar search Google in the browser (YouTube has its own search)", () async {
    await home.openFromHome('lofi beats');
    expect(home.browsed, ['https://www.google.com/search?q=lofi+beats']);
  });

  test('a web address typed there opens that site', () async {
    await home.openFromHome('example.com/page');
    expect(home.browsed, ['https://example.com/page']);
  });

  test('a pasted link inside text opens that link', () async {
    await home.openFromHome('look at this https://news.example.org/a?b=1 wow');
    expect(home.browsed, ['https://news.example.org/a?b=1']);
  });
}
