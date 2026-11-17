/// The browser's media button (bottom-right corner).
enum MediaButtonMode {
  /// Nothing to offer (yt-dlp can't read pages here).
  hidden,

  /// Nothing found yet: a small grey button that asks yt-dlp to read the page.
  scan,

  /// Videos / audio caught on the page: coloured, with their count.
  found,

  /// A page a site extractor supports (YouTube, TikTok…): "Download".
  download,
}

MediaButtonMode mediaButtonMode({required bool supportedPage, required int found, required bool canScan}) {
  if (supportedPage) return MediaButtonMode.download;
  if (found > 0) return MediaButtonMode.found;
  return canScan ? MediaButtonMode.scan : MediaButtonMode.hidden;
}

/// Slides the button away while the page scrolls down (reading) and back
/// when it scrolls up or reaches the top, like a phone browser's toolbar.
class ScrollHider {
  ScrollHider({this.threshold = 24, this.topZone = 64});

  /// Pixels of movement in one direction before the button reacts (so a
  /// jittery finger doesn't make it flicker).
  final int threshold;

  /// Near the top of the page the button always shows.
  final int topZone;

  bool visible = true;
  int _anchor = 0;

  /// The page's new scroll position [y]; returns whether to show the button.
  bool update(int y) {
    if (y <= topZone) {
      _anchor = y;
      return visible = true;
    }
    final moved = y - _anchor;
    if (moved > threshold) {
      visible = false;
      _anchor = y;
    } else if (moved < -threshold) {
      visible = true;
      _anchor = y;
    } else if ((visible && moved < 0) || (!visible && moved > 0)) {
      // Still going the way it already went: measure the turn from here.
      _anchor = y;
    }
    return visible;
  }

  /// The page jumped by itself (the top bar's show/hide resized it): take
  /// [y] as the new starting point without showing or hiding anything.
  void rebase(int y) => _anchor = y;

  /// A new page: start shown.
  void reset() {
    visible = true;
    _anchor = 0;
  }
}
