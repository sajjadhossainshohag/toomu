import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/services/update_service.dart';

void main() {
  const hour = 60 * 60 * 1000;
  final now = DateTime(2026, 11, 20, 12).millisecondsSinceEpoch;

  test('every app open checks for a new version, even if checked a minute ago', () {
    expect(UpdateService.shouldAutoCheck(launch: true, lastCheckMs: now - 60 * 1000, nowMs: now), isTrue);
  });

  test('coming back to the app checks again once an hour has passed', () {
    expect(UpdateService.shouldAutoCheck(launch: false, lastCheckMs: now - 10 * 60 * 1000, nowMs: now), isFalse);
    expect(UpdateService.shouldAutoCheck(launch: false, lastCheckMs: now - hour, nowMs: now), isTrue);
    expect(UpdateService.shouldAutoCheck(launch: false, lastCheckMs: 0, nowMs: now), isTrue);
  });
}
