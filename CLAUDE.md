# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Toomu is a Flutter app (Android first, iOS in progress): YouTube/TikTok/web video downloader, ad-free YouTube player, music player and 1DM-style in-app browser that catches media on any page.

## Commands

```bash
flutter pub get
flutter analyze                                   # CI fails on any issue (flutter_lints)
flutter test                                      # unit tests in test/
flutter test test/stream_plan_test.dart           # one file
flutter test test/stream_plan_test.dart --plain-name "segment list"   # one test
tool/build_release.sh                             # release APKs per ABI (arm64, armv7), obfuscated
flutter test integration_test/stream_pipeline_test.dart -d <iphone-id>   # iOS stream pipeline on a real device (Mac)
```

- CI (`.github/workflows/build.yml`, Flutter 3.41.1): push to `main` builds the arm64 APK (armv7 too on tags) while a parallel `check` job runs `flutter analyze` + `flutter test`; iOS (unsigned `.ipa`) only on `v*` tags or manual dispatch; every successful main build publishes a GitHub Release under a new tag (`vYYYY.MM.DD-HHMM`, Bangladesh time); a pushed `v*` tag publishes one under that tag with armv7 + iOS too.
- `--dart-define=TOOMU_BUILD=...` labels the build in Settings → Diagnostics.
- Release signing: `android/key.properties` or `ANDROID_KEYSTORE_*` env/secrets; otherwise the debug key.
- The Gradle `merge*NativeLibs` tasks run `tool/trim_ytdlp_bundles.py` (needs `python3`; skipped with a warning if missing) to strip unused files from yt-dlp's bundled Python/FFmpeg archives.
- Debug builds package only `arm64-v8a` (add `x86_64` in `android/app/build.gradle.kts` for Intel emulators).

## Bug fixes

Every fix ships with a regression test so the issue can't come back: write the test first, run it and see it fail for the reported reason, then fix and see it pass. Name the test after the symptom (e.g. `'grey top bar does not return after reopening'`) and keep it in `test/` (Kotlin: `android/app/src/test/`). If a bug truly can't be reproduced in a test (device-only, CI config), say so in the commit message. Changes that only remove something (a feature, a notification) need no test.

## Architecture

**GetX everywhere.** App-lifetime services are registered in `lib/app/services/app_services.dart` in dependency order (some in parallel; anything used by another service's `init` must come first). Feature modules live in `lib/app/modules/<feature>/{bindings,controllers,views}`; routes in `lib/app/routes/app_pages.dart`, main tabs in `modules/home/home_tabs.dart`. Persistence is GetStorage via `StorageService`; settings in `SettingsService` with keys in `core/values/app_constants.dart`.

**Native layer via method channels named `toomu/*`.** Android (`android/.../MainActivity.kt` and siblings): `toomu/ytdlp` (+ `toomu/ytdlp/progress` events) → `YtDlpBridge.kt` (youtubedl-android: yt-dlp + Python + QuickJS + FFmpeg + aria2c, run as executables, hence `useLegacyPackaging` and minSdk 24), plus `download_notify`, `media_library`, `media_scanner`, `video` (PiP/background play), `intents` (share/open-with), `bubble` (floating button), `update` (self-install). iOS (`ios/Runner/AppDelegate.swift`) answers `nil` to the Android-only channels and implements `toomu/media_merge` (`merge`, `finish`, `probe`, `decrypt`). Dart guards Android-only features with `Platform.isAndroid`; for iOS-only behaviour use `Platform.isIOS` (tests run on a desktop host, where `!Platform.isAndroid` would switch them to iOS behaviour).

**YouTube.** `YoutubeProvider.fastLinks` is a fast lookup without yt-dlp (~0.3 s, whole-file links when available); `YtDlpService` is the fallback and the Android downloader, auto-updating yt-dlp from GitHub daily, with extra args from remote config. `StreamProxy` (127.0.0.1) sits between players and YouTube: it slices requests into ≤ ~10 MB `range=` pieces (YouTube throttles or 403s large ranges), matches the link's IP version, and swaps fast-lookup links for yt-dlp's mid-playback. Android yt-dlp downloads are routed through it too (`routeInfoJson`).

**Downloads (`DownloadService`).** One queue, sources in `DownloadTask.source`:
- `youtube`: Android = yt-dlp (fast-lookup info JSON first, client fallbacks after); iOS = `_downloadNative` (fast links + AVFoundation merge, H.264/AAC ≤ 1080p).
- `direct`: own engine, 10 MB chunks over N connections, resumable, end-game splitting of the slowest piece; browser downloads carry the page's User-Agent/Referer and fresh WebView cookies.
- `tiktok` / `stream`: Android = yt-dlp on the URL (HLS/DASH manifest or page); iOS `stream` = `StreamDownloader`.
- Network errors mark a task "Connection lost" and it auto-resumes when a real connection works again; expired browser links offer "Refresh link" (reopens the page in `BrowserController` with the task and matches the recaptured file).
- Partial data of yt-dlp tasks lives in `YtDlpService.workRoot/<taskId>`; direct tasks use `<file>.part` (+ `.chunks/`).

**In-app browser (`modules/browser`).** InAppWebView with an injected script (`media_sniffer.dart`, runs in all frames) that reports media candidates to `MediaCapture`, which probes, parses HLS/DASH qualities (`core/utils/media_manifest.dart`), drops segments/tiny files and marks DRM; the result shows in `views/media_sheet.dart`. `redirect_guard.dart` blocks ad redirects/popups (popups load in the same tab, so all go through `shouldOverrideUrlLoading`): a cross-site jump right after a tap not on a link to that site, or any navigation to a host on the downloaded blocklist (StevenBlack hosts + gambling, refreshed weekly). Ad resources aren't blocked: the plugin's Android content blocker sends a HEAD request per resource. On Android the page is paused (`pause` + process-wide `pauseTimers`) while the app is hidden or Toomu's player is open over it. The top bar's downloads button (`views/downloads_sheet.dart`) shows progress and the download list in a sheet so the page stays open. `extractors/` handles pages with a dedicated flow (YouTube, direct file links).

**iOS HLS/DASH without yt-dlp/FFmpeg.** `StreamDownloader` → `StreamPlanner` (`core/utils/stream_plan.dart`: pieces grouped into runs at discontinuities, init changes and DASH periods) → fetch (AES-128 via native `decrypt`) → pure-Dart muxer in `lib/app/core/media/` (fMP4/MP4, MPEG-TS H.264+AAC and packed AAC readers; codec-agnostic fragmented-MP4 writer) → native `finish` rewrites to a regular MP4 when AVFoundation can play it. The `core/media` and planner code has no Flutter imports. Status and verification notes: `docs/ios-support.md` (not yet verified on an iPhone).

**App updates (Android).** CI passes the release tag as `--dart-define=TOOMU_TAG`; `UpdateService` checks GitHub's latest release (daily, and Settings → Check for updates), downloads the APK for the phone's ABI and installs it through a `PackageInstaller` session (`toomu/update` → `UpdateReceiver.kt`, `REQUEST_INSTALL_PACKAGES`); on Android 12+ only the first update asks for confirmation, later ones are silent because Toomu is then the installer of record. Builds without a tag (local/dev) never auto-check. Phones only accept an update signed with the same key, so CI needs the `ANDROID_KEYSTORE_*` secrets.

**Remote config.** `RemoteConfigService` fetches a static JSON at startup (shape in `remote_config.example.json`): yt-dlp args/channel, connections, start-page sites, feed categories, browser blocklist URL; every field optional.
