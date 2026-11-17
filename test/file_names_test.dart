import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/error_text.dart';
import 'package:toomu/app/core/utils/formatters.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';

void main() {
  // The title that failed with "[Errno 36] File name too long".
  const bengali = '৩৭ হাজার টাকায় বিক্রি হলো ২৬ সালের দানব! বেপারীর টাইম নাই হাড্ডা হাড্ডি নিলামে বড়লোক।'
      'Today fishing. ৩৭ হাজার টাকায় বিক্রি হলো ২৬ সালের দানব! বেপারীর টাইম নাই হাড্ডা হাড্ডি নিলামে বড়লোক।';

  group('file names', () {
    test('long Bengali titles fit Android with room for yt-dlp\'s endings', () {
      final name = Formatters.fileName(bengali);
      expect(utf8.encode(name).length, lessThanOrEqualTo(150));
      // Base + quality + "(12)" + yt-dlp/aria2c temp endings stays < 255.
      final worst = '$name (1080p60) (12).f299-drc.webm.part.aria2';
      expect(utf8.encode(worst).length, lessThan(255));
      expect(name, startsWith('৩৭ হাজার টাকায়'));
    });

    test('a video titled like a Windows device name still saves', () {
      expect(Formatters.fileName('CON'), 'CON_');
      expect(Formatters.fileName('nul'), 'nul_');
      expect(Formatters.fileName('COM1'), 'COM1_');
      expect(Formatters.fileName('Concert'), 'Concert');
    });

    test('never cuts inside a letter (Bengali conjuncts, emoji)', () {
      final title = '${'ক্ষ' * 30}🎵🎵🎵👨‍👩‍👧';
      for (var max = 1; max < 120; max++) {
        final cut = Formatters.fitBytes(title, max);
        expect(utf8.encode(cut).length, lessThanOrEqualTo(max));
        expect(title.startsWith(cut), isTrue);
        // Every letter in the cut is a whole letter of the original.
        expect(cut.characters.every((c) => title.characters.contains(c)), isTrue);
      }
    });

    test('short names are unchanged; unsafe characters and edge dots removed', () {
      expect(Formatters.fileName('My Song'), 'My Song');
      expect(Formatters.fileName('a/b:c*d?"e<f>g|h'), 'abcdefgh');
      expect(Formatters.fileName('...hidden'), 'hidden');
      expect(Formatters.fileName('ends with dots...'), 'ends with dots');
      expect(Formatters.fileName('***'), 'download');
    });
  });

  group('local file problems', () {
    test('are recognised so downloads stop instead of retrying', () {
      expect(localFileProblem('ERROR: unable to open for writing: [Errno 36] File name too long: x'), isNotNull);
      expect(localFileProblem('OSError: [Errno 28] No space left on device'), contains('storage'));
      expect(localFileProblem('PermissionError: [Errno 13] Permission denied'), isNotNull);
      expect(localFileProblem('ERROR: unable to download video data: HTTP Error 403: Forbidden'), isNull);
    });

    test('messages: "page" or "storage" is not read as age-restricted', () {
      expect(ErrorText.of(YtDlpException('ERROR: [youtube] x: The page needs to be reloaded.')),
          isNot(contains('age-restricted')));
      expect(ErrorText.of(YtDlpException('OSError: [Errno 28] No space left on device')),
          'Not enough free storage on the phone.');
      expect(ErrorText.of(YtDlpException('ERROR: Sign in to confirm your age')), contains('age-restricted'));
    });
  });
}
