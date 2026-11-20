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

  group('Windows', () {
    const env = {'ProgramFiles': r'C:\Program Files', 'ProgramW6432': r'C:\Program Files'};

    test('a copy installed for all users updates there, a per-user copy in its own folder', () {
      expect(UpdateService.installedForAllUsers(r'C:\Program Files\Toomu\toomu.exe', env), isTrue);
      expect(UpdateService.installedForAllUsers(r'c:\program files\Toomu\toomu.exe', env), isTrue);
      expect(UpdateService.installedForAllUsers(r'C:\Users\a\AppData\Local\Programs\Toomu\toomu.exe', env), isFalse);
      expect(UpdateService.installedForAllUsers(r'C:\Program Files (x86)\Toomu\toomu.exe', env), isFalse);
      expect(UpdateService.installedForAllUsers(r'C:\Program Files\Toomu\toomu.exe', const {}), isFalse);
    });

    test('the installer runs silently and starts the new version when done', () {
      final args = UpdateService.installerArgs(allUsers: false);
      expect(args, containsAll(['/SILENT', '/SUPPRESSMSGBOXES', '/relaunch=yes', '/CURRENTUSER']));
      expect(UpdateService.installerArgs(allUsers: true), contains('/ALLUSERS'));
    });
  });
}
