import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/browser/media_title.dart';
import 'package:toomu/app/services/download_service.dart';

void main() {
  group('browser download names', () {
    test('a long video name with a dot inside still saves as a video, not a file', () {
      final n = DownloadService.directName(
        'Episode 3. The long return of the king, full movie in HD with every extra scene',
        mimeType: 'video/mp4',
      );
      expect(n.kind, DownloadKind.video);
      expect(n.ext, 'mp4');
      expect(n.base, 'Episode 3. The long return of the king, full movie in HD with every extra scene');
    });

    test('a coded server name with a dot saves as a video by its type, not as a file', () {
      final n = DownloadService.directName(
        'KSUxH_Go3rh9CGC8.cVrpFcHHEofk5a7tfmXdadJKId_nBWtvp4HoZeeQgzub6hJBFItrReBYP692Z2AghyOgVUMyWgt',
        mimeType: 'video/mp4',
      );
      expect(n.kind, DownloadKind.video);
      expect(n.ext, 'mp4');
    });

    test('release-style names keep their dots and get the real extension', () {
      final n = DownloadService.directName('Movie.2024.1080p.WEB-DL.x264', mimeType: 'video/x-matroska');
      expect(n.ext, 'mkv');
      expect(n.base, 'Movie.2024.1080p.WEB-DL.x264');
      expect(n.kind, DownloadKind.video);
    });

    test('a type with parameters is still read', () {
      expect(DownloadService.directName('clip', mimeType: 'video/mp4; charset=binary').ext, 'mp4');
    });

    test('a very long title ending in .mp4 keeps .mp4 and is cut to fit the phone', () {
      final n = DownloadService.directName('${'Very long title ' * 20}.mp4');
      expect(n.ext, 'mp4');
      expect(n.kind, DownloadKind.video);
      expect(utf8.encode(n.base).length, lessThanOrEqualTo(150));
    });

    test('a real extension wins over a vague server type', () {
      final n = DownloadService.directName('song.mp3', mimeType: 'application/octet-stream');
      expect(n.ext, 'mp3');
      expect(n.kind, DownloadKind.audio);
    });

    test('other files keep their own extension', () {
      expect(DownloadService.directName('report.final.docx').ext, 'docx');
      expect(DownloadService.directName('backup.tar.gz').ext, 'gz');
      expect(DownloadService.directName('app.apk', mimeType: 'application/vnd.android.package-archive').ext, 'apk');
    });

    test('a film from a file page saves under its title as a video, not a coded file', () {
      final name = downloadName(
        suggested: 'KSUxH_Go3rh9CGC8.cVrpFcHHEofk5a7tfmXdadJKId_nBWtvp4HoZeeQgzub6hJBFItrReBYP692Z2AghyOgVUMyWgt.mkv',
        url: 'https://cdn.example.net/d/KSUxH_Go3rh9CGC8.cVrpFcHHEofk5a7tfmXdadJKId',
        pageTitle: 'MovieLinkBD.com - The.Odyssey.2026.1080p.Dual[Hindi-English].AAC.AMZN.HEVC.h265.ESub.mkv',
        pageUrl: 'https://jfn5pa.movielinkbd.at/file/BDfOz1zjAn9ZgH_DPSTAarz-fTz1jp8_NoN7FDtRFD9GmI94h3VGv1vdef17D6lrqgCnbtL8jFuW',
      );
      final n = DownloadService.directName(name, mimeType: 'application/octet-stream');
      expect(n.base, 'The.Odyssey.2026.1080p.Dual[Hindi-English].AAC.AMZN.HEVC.h265.ESub');
      expect(n.ext, 'mkv');
      expect(n.kind, DownloadKind.video);
    });

    test('no extension and no type stays a plain file', () {
      final n = DownloadService.directName('download');
      expect(n.ext, 'bin');
      expect(n.kind, DownloadKind.file);
      expect(n.base, 'download');
    });
  });
}
