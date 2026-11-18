import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/services/diagnostics_service.dart';

void main() {
  // Android's ApplicationExitInfo, as the toomu/diagnostics channel sends it.
  Map<String, Object?> exit(int reason, {int status = 0, String? description, int importance = 100}) => {
    'time': DateTime(2026, 11, 18, 14, 11, 40).millisecondsSinceEpoch,
    'reason': reason,
    'status': status,
    'description': description,
    'importance': importance,
    'rssKb': 812 * 1024,
    'process': 'com.example.toomu',
  };

  test('a native crash names its signal, so a kick-out can be told from a kill', () {
    expect(
      DiagnosticsService.exitLine(exit(5, status: 11, description: 'crash')),
      '[Exit] last run ended 11-18 14:11:40: native crash (signal 11, SIGSEGV), in front, 812 MB — crash',
    );
  });

  test('the system killing the app for memory or heat reads as such', () {
    expect(DiagnosticsService.exitLine(exit(3, importance: 400)), contains('out of memory (killed by Android), in background'));
    expect(DiagnosticsService.exitLine(exit(9)), contains('too much CPU or battery (killed by Android)'));
    expect(DiagnosticsService.exitLine(exit(6)), contains('froze (not responding)'));
    expect(DiagnosticsService.exitLine(exit(10)), contains('closed by the user'));
    expect(DiagnosticsService.exitLine(exit(42)), contains('reason 42'));
  });

  test('phone heat levels from Android\'s thermal status', () {
    expect(DiagnosticsService.heat(0), 'normal');
    expect(DiagnosticsService.heat(2), 'hot (moderate)');
    expect(DiagnosticsService.heat(3), 'very hot (severe, slowed down)');
    expect(DiagnosticsService.heat(-1), 'unknown');
  });
}
