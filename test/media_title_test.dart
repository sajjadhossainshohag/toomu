import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/media_title.dart';

/// Regression: videos from movie sites downloaded with random names. The
/// video plays in an embedded player frame (another site) whose title is
/// empty or a code, and the fallback was the stream's file ("master.m3u8").
void main() {
  const page = 'https://fmovies.to/movie/inception-2010-19764';
  const pageTitle = 'Watch Inception (2010) Full Movie Online Free | FMovies';

  group('media found in a player frame', () {
    test('is named after the page, not the frame', () {
      for (final frameTitle in ['', 'Video Player', 'JW Player', 'x7KpQ2mZ9wLq4', 'embed']) {
        expect(
          mediaTitle(
            frameTitle: frameTitle,
            frameUrl: 'https://vidplay.online/e/x7KpQ2mZ9wLq4',
            pageTitle: pageTitle,
            pageUrl: page,
            mediaUrl: 'https://cdn.vid.net/hls/a8f7e6d2c1b0/master.m3u8',
          ),
          'Inception (2010)',
          reason: 'frame title "$frameTitle"',
        );
      }
    });

    test('the frame title is used when the page has none worth using', () {
      expect(
        mediaTitle(
          frameTitle: 'Inception.2010.1080p',
          frameUrl: 'https://vidplay.online/e/x7KpQ2mZ9wLq4',
          pageTitle: 'Loading...',
          pageUrl: page,
          mediaUrl: 'https://cdn.vid.net/master.m3u8',
        ),
        'Inception.2010.1080p',
      );
    });

    test('then a real file name, then "Video" — never a code', () {
      String named(String mediaUrl) => mediaTitle(
            frameTitle: '',
            frameUrl: 'https://player.net/e/1',
            pageTitle: '',
            pageUrl: page,
            mediaUrl: mediaUrl,
          );
      expect(named('https://cdn.x/files/The_Matrix_1999.mp4'), 'The Matrix 1999');
      expect(named('https://cdn.x/hls/a8f7e6d2c1b0f9e8/master.m3u8'), 'Video');
      expect(named('https://cdn.x/v/9f8e7d6c5b4a3f2e1d0c.mp4'), 'Video');
    });
  });

  test('media in the page itself keeps the page\'s title', () {
    expect(
      mediaTitle(
        frameTitle: 'My Holiday Clip - Vimeo',
        frameUrl: 'https://vimeo.com/123',
        pageTitle: 'My Holiday Clip - Vimeo',
        pageUrl: 'https://vimeo.com/123',
        mediaUrl: 'https://vod.vimeocdn.com/x/master.m3u8',
      ),
      'My Holiday Clip',
    );
  });

  group('page title cleaning', () {
    String clean(String t, [String url = page]) => cleanPageTitle(t, pageUrl: url);

    test('site name and streaming filler go', () {
      expect(clean(pageTitle), 'Inception (2010)');
      expect(clean('FMovies - Watch Dune: Part Two (2024) HD'), 'Dune: Part Two (2024)');
      expect(clean('Breaking Bad S01E02 - Watch Online | fmovies.to'), 'Breaking Bad S01E02');
      expect(clean('Oppenheimer 2023 Full Movie 1080p — MyFlixer', 'https://myflixer.tv/x'), 'Oppenheimer 2023');
    });

    test('dashes and colons inside a name stay', () {
      expect(clean('Mission: Impossible - Dead Reckoning | FMovies'), 'Mission: Impossible - Dead Reckoning');
      expect(clean('Spider-Man: Across the Spider-Verse'), 'Spider-Man: Across the Spider-Verse');
    });

    test('nothing left but the site → treated as no name', () {
      expect(looksGeneric(clean('FMovies')), isFalse); // the site's own name, kept if it's all there is
      expect(looksGeneric(clean('Watch Online Free')), isTrue);
    });
  });

  group('file downloads', () {
    test('a code from the server becomes the page title', () {
      expect(
        downloadName(
          suggested: '7f3a9c2e1b8d4f60.mp4',
          url: 'https://dl.host.net/7f3a9c2e1b8d4f60.mp4',
          pageTitle: pageTitle,
          pageUrl: page,
        ),
        'Inception (2010).mp4',
      );
      expect(
        downloadName(suggested: null, url: 'https://dl.host.net/get/a1b2c3d4e5f6g7h8.mkv', pageTitle: pageTitle, pageUrl: page),
        'Inception (2010).mkv',
      );
    });

    test('a real file name is kept', () {
      expect(
        downloadName(suggested: 'Inception.2010.1080p.BluRay.mkv', url: 'https://x/y', pageTitle: pageTitle, pageUrl: page),
        'Inception.2010.1080p.BluRay.mkv',
      );
      expect(downloadName(suggested: 'setup.exe', url: 'https://x/setup.exe', pageTitle: 'Download', pageUrl: page), 'setup.exe');
    });

    test('a coded file name with a dot in the middle shows the page title, not a random string', () {
      const film = 'The.Odyssey.2026.1080p.Dual[Hindi-English].AAC.AMZN.HEVC.h265.ESub.mkv';
      const title = 'MovieLinkBD.com - $film';
      const code = 'KSUxH_Go3rh9CGC8.cVrpFcHHEofk5a7tfmXdadJKId_nBWtvp4HoZeeQgzub6hJBFItrReBYP692Z2AghyOgVUMyWgt'
          '-GOU8iuiom02-DxcKO3sRFSpCnnwx58RhUECYXxu86Nwn5jjpNTT1dvEOd';
      for (final filePage in [
        'https://jfn5pa.movielinkbd.at/file/BOD4rHF82ExwRonzlohO6jEVOZqrEUYdLJAKVVr-JxDPqjUo9SVvGQuPXQI-NZ-bef5p4TKp5srZPrMyF2HM8qIP29F4zGed604HXYxQKmQ',
        'https://jfn5pa.movielinkbd.at/file/BDfOz1zjAn9ZgH_DPSTAarz-fTz1jp8_NoN7FDtRFD9GmI94h3VGv1vdef17D6lrqgCnbtL8jFuW-rl65TR2bShO_SxARdq6H-R7hxESe1I',
      ]) {
        for (final suggested in [code, '$code.mkv', 'BDfOz1zjAn9ZgH_DPSTAarz-fTz1jp8_NoN7FDtRFD9GmI94h3VGv1vdef17D6lrqgCnbtL8jFuW']) {
          expect(
            downloadName(suggested: suggested, url: 'https://cdn.example.net/d/$suggested', pageTitle: title, pageUrl: filePage),
            film,
            reason: suggested,
          );
        }
      }
    });

    test('a page title that already ends in the extension does not get it twice', () {
      expect(
        downloadName(
          suggested: 'a1b2c3d4e5f6a7b8c9d0.mkv',
          url: 'https://cdn.example.net/a1b2c3d4e5f6a7b8c9d0.mkv',
          pageTitle: 'MyFiles - Dune.Part.Two.2024.1080p.mkv',
          pageUrl: 'https://myfiles.example/file/abc',
        ),
        'Dune.Part.Two.2024.1080p.mkv',
      );
    });

    test('a real release name with dots is still kept', () {
      expect(
        downloadName(
          suggested: 'The.Odyssey.2026.1080p.WEB-DL.H264.mkv',
          url: 'https://x/y',
          pageTitle: 'MovieLinkBD.com - Something else',
          pageUrl: 'https://jfn5pa.movielinkbd.at/file/x',
        ),
        'The.Odyssey.2026.1080p.WEB-DL.H264.mkv',
      );
    });

    test('kept as is when the page has no usable title either', () {
      expect(
        downloadName(suggested: '7f3a9c2e1b8d4f60.mp4', url: 'https://x/y', pageTitle: 'Just a moment...', pageUrl: page),
        '7f3a9c2e1b8d4f60.mp4',
      );
    });
  });

  test('what counts as no name', () {
    for (final t in ['', 'master', 'index.m3u8', 'Video Player', 'a8f7e6d2c1b0', 'x7KpQ2_mZ9wLq4', 'https://x.com/v']) {
      expect(looksGeneric(t), isTrue, reason: t);
    }
    for (final t in ['Inception (2010)', 'The Matrix 1999', 'S01E02', 'Dune']) {
      expect(looksGeneric(t), isFalse, reason: t);
    }
  });
}
