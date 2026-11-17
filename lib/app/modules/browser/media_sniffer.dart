const mediaSnifferJs = r'''
(function () {
  // Filters in the page so only media candidates reach Dart (onLoadResource
  // would send every request); iframes without the bridge use postMessage.
  if (window.__toomuSniffer) return;
  window.__toomuSniffer = true;
  var MEDIA = /\.(m3u8|mpd|mp4|m4v|webm|mov|mkv|3gp|mp3|m4a|aac|ogg|oga|opus|flac|wav)(\?|#|$)/i;
  var SKIP = /\.(ts|m4s|cmfv|cmfa|vtt|srt|key|jpg|jpeg|png|gif|webp)(\?|#|$)|[?&](range|bytestart)=\d|googlevideo\.com|youtube\.com|doubleclick\.net|googlesyndication|imasdk\.googleapis/i;
  var TYPES = /mpegurl|dash\+xml|^video\/(?!mp2t)|^audio\//i;
  var seen = {};
  var queue = [];
  var timer = 0;

  function bridge() {
    return window.flutter_inappwebview && window.flutter_inappwebview.callHandler;
  }

  function flush() {
    timer = 0;
    if (bridge()) {
      while (queue.length) window.flutter_inappwebview.callHandler('toomuMedia', queue.shift());
    } else if (window.top !== window) {
      try {
        while (queue.length) window.top.postMessage({ toomuMedia: queue.shift() }, '*');
      } catch (e) {}
    } else {
      timer = setTimeout(flush, 400);
    }
  }

  function send(m) {
    queue.push(m);
    if (!timer) timer = setTimeout(flush, 0);
  }

  function report(url, source, extra) {
    if (!url || typeof url !== 'string' || url.indexOf('blob:') === 0) return;
    try { url = new URL(url, location.href).href; } catch (e) { return; }
    if (!/^https?:/i.test(url) || url.length > 4000 || SKIP.test(url)) return;
    var key = url + '|' + (extra.duration ? Math.round(extra.duration) : '') + '|' + (extra.height || '') + '|' + (extra.subs ? extra.subs.length : '');
    if (seen[key]) return;
    seen[key] = 1;
    var m = { url: url, source: source, page: location.href, title: document.title || '', ua: navigator.userAgent };
    for (var k in extra) m[k] = extra[k];
    send(m);
  }

  function scan() {
    var els = document.querySelectorAll('video, audio');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var extra = {
        tag: el.tagName.toLowerCase(),
        poster: el.poster || '',
        duration: isFinite(el.duration) ? el.duration : 0,
        width: el.videoWidth || 0,
        height: el.videoHeight || 0,
        subs: []
      };
      var tracks = el.querySelectorAll('track');
      for (var t = 0; t < tracks.length; t++) {
        extra.subs.push({ url: tracks[t].src, lang: tracks[t].srclang, kind: tracks[t].kind });
      }
      report(el.currentSrc || el.src, 'element', extra);
      var sources = el.querySelectorAll('source');
      for (var j = 0; j < sources.length; j++) report(sources[j].src, 'element', extra);
    }
    var og = document.querySelector('meta[property="og:video:secure_url"], meta[property="og:video:url"], meta[property="og:video"]');
    if (og && og.content) report(og.content, 'meta', {});
  }

  try {
    new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) {
        if (MEDIA.test(e.name)) report(e.name, 'request', {});
      });
    }).observe({ type: 'resource', buffered: true });
  } catch (e) {}

  var nativeFetch = window.fetch;
  if (nativeFetch) {
    window.fetch = function () {
      var p = nativeFetch.apply(this, arguments);
      p.then(function (r) {
        try {
          var t = r.headers.get('content-type') || '';
          if (TYPES.test(t)) report(r.url, 'request', { type: t });
        } catch (e) {}
      }, function () {});
      return p;
    };
  }

  var nativeOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    var xhr = this;
    xhr.addEventListener('readystatechange', function () {
      if (xhr.readyState !== 2) return;
      try {
        var t = xhr.getResponseHeader('content-type') || '';
        if (TYPES.test(t)) report(xhr.responseURL || String(url), 'request', { type: t });
      } catch (e) {}
    });
    return nativeOpen.apply(this, arguments);
  };

  var pending = 0;
  function scanSoon() {
    if (pending) return;
    pending = setTimeout(function () { pending = 0; scan(); }, 500);
  }
  ['loadedmetadata', 'play', 'durationchange'].forEach(function (type) {
    document.addEventListener(type, scanSoon, true);
  });
  document.addEventListener('DOMContentLoaded', function () {
    scan();
    try {
      new MutationObserver(scanSoon).observe(document.documentElement, { childList: true, subtree: true });
    } catch (e) {}
  });

  if (window.top === window) {
    window.addEventListener('message', function (e) {
      var d = e.data;
      if (d && d.toomuMedia && typeof d.toomuMedia.url === 'string') send(d.toomuMedia);
    });
  }
})();
''';
