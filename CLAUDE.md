# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Toomu is a Flutter app for Android and Windows (no iOS/macOS): YouTube/TikTok/web video downloader, ad-free YouTube player, music player and 1DM-style in-app browser that catches media on any page.

## Commands

```bash
flutter pub get
flutter analyze                                   # CI fails on any issue (flutter_lints)
flutter test                                      # unit tests in test/ (~20 s; timers are shortened in tests via @visibleForTesting statics)
flutter test $(tool/test_shard.sh 0 3)            # one CI shard (0..2 of 3)
flutter test test/windows_ytdlp_test.dart         # one file
flutter test test/windows_ytdlp_test.dart --plain-name "drops the Android aria2c option"   # one test
tool/build_release.sh                             # release APKs per ABI (arm64, armv7), obfuscated
flutter build windows --release                   # Windows x64 (needs a Windows PC with Visual Studio's C++ workload)
```

- CI (`.github/workflows/build.yml`, Flutter 3.41.1): push to `main` builds the arm64 APK (armv7 too on tags) and Windows x64 as a zip plus an Inno Setup installer (`windows/installer/toomu.iss`; the Windows job attaches both to the release when done), while parallel jobs run `flutter analyze`, the Dart tests split by file into 3 shards (`tool/test_shard.sh`, all CPU cores each) and the Kotlin tests; every successful main build publishes a GitHub Release under a new tag (`vYYYY.MM.DD-HHMM`, Bangladesh time); a pushed `v*` tag publishes one under that tag with armv7 too. The repo is public, so Actions minutes are free (Linux and Windows runners).
- `--dart-define=TOOMU_BUILD=...` labels the build in Settings → Diagnostics.
- Release signing: `android/key.properties` or `ANDROID_KEYSTORE_*` env/secrets; otherwise the debug key.
- The Gradle `merge*NativeLibs` tasks run `tool/trim_ytdlp_bundles.py` (needs `python3`; skipped with a warning if missing) to strip unused files from yt-dlp's bundled Python/FFmpeg archives.
- Debug builds package only `arm64-v8a` (add `x86_64` in `android/app/build.gradle.kts` for Intel emulators).

## Releases

What a push to `main` does depends on the newest pushed commit's message (CI reads only that one):

| Push | Checks (analyze, Dart + Kotlin tests) | APK + Windows builds | Release / phones update |
|---|---|---|---|
| Normal commit | yes | yes | yes, new `vYYYY.MM.DD-HHMM` tag |
| `[skip build]` in the message | yes | no | no |
| `[skip ci]` in the message | no | no | no |
| `v*` tag | yes | yes, armv7 too | yes, under that tag |
| By hand: `gh workflow run build.yml --ref main` | yes | yes (ignores messages) | yes |

- Skipped commits aren't lost: every build compiles all of `main`, so the next full build releases everything since the last release. Use `[skip build]` for in-between work (tests, docs, a run of small commits, a change already tried with a local APK); leave it off the commit people should get.
- The flag matches anywhere in the message, so never write it just to describe it; if a release was skipped by mistake, start the build by hand.
- A newer push cancels an older run of the same kind only: a `[skip build]` run never cancels a full build, but a full build cancels an older full build still running (its commits ship in the newer one).
- Phones and Windows PCs compare their `TOOMU_TAG` (one `tag` job sets it for both builds) with GitHub's latest release (every app open, on return after an hour, or Settings → Check for updates); phones only get builds signed with the release key, so CI needs the `ANDROID_KEYSTORE_*` secrets. Windows copies installed with the installer update themselves (silent installer, `/relaunch=yes` starts the new version); a portable copy gets its zip opened in the browser. Windows is offered a release only once its files are attached.
- The release publishes once Android and the checks pass (~5 min); the Windows job attaches its zip and installer a few minutes later.

## Bug fixes

Every fix ships with a regression test so the issue can't come back: write the test first, run it and see it fail for the reported reason, then fix and see it pass. Name the test after the symptom (e.g. `'grey top bar does not return after reopening'`) and keep it in `test/` (Kotlin: `android/app/src/test/`). If a bug truly can't be reproduced in a test (device-only, CI config), say so in the commit message. Changes that only remove something (a feature, a notification) need no test.

## Architecture

**GetX everywhere.** App-lifetime services are registered in `lib/app/services/app_services.dart` in dependency order (some in parallel; anything used by another service's `init` must come first). Feature modules live in `lib/app/modules/<feature>/{bindings,controllers,views}`; routes in `lib/app/routes/app_pages.dart`, main tabs in `modules/home/home_tabs.dart`. Persistence is GetStorage via `StorageService`; settings in `SettingsService` with keys in `core/values/app_constants.dart`.

**Native layer via method channels named `toomu/*`.** Android (`android/.../MainActivity.kt` and siblings): `toomu/ytdlp` (+ `toomu/ytdlp/progress` events) → `YtDlpBridge.kt` (youtubedl-android: yt-dlp + Python + QuickJS + FFmpeg + aria2c, run as executables, hence `useLegacyPackaging` and minSdk 24), plus `download_notify`, `media_library`, `media_scanner`, `video` (PiP/background play), `intents` (share/open-with), `bubble` (floating button), `update` (self-install). Windows has no native channels of its own: `YtDlpBridge` switches to `WindowsYtDlp` (`data/providers/ytdlp/windows_ytdlp.dart`), which downloads `yt-dlp.exe` from GitHub on first launch (FFmpeg + Deno follow in the background; downloads wait for FFmpeg, lookups don't), runs it with `Process`, kills the process tree on cancel and updates it daily like the Android bridge; no aria2c (`--toomu-aria2c` is dropped). Dart guards Android-only features with `Platform.isAndroid`; Windows decisions go through `HostOs` (`core/utils/host_os.dart`: `isWindows`, `hasYtDlp`, …), whose `override` lets tests on the macOS/Linux host check the Windows path. `WindowsYtDlp` takes its folder, GitHub URL, launcher, unzip and kill steps as parameters; `test/windows_ytdlp_install_test.dart` drives it against a local fake GitHub with a shell-script yt-dlp. On Windows: just_audio plays through `just_audio_media_kit`, `audio_session`/`just_audio_background`/`open_filex` are skipped (files open via Explorer, `core/utils/shell_open.dart`), downloads go to `%USERPROFILE%\Downloads\Toomu`, and the window opens phone-shaped (430×860, min 360×600, `windows/runner/`).

**YouTube.** `YoutubeProvider.fastLinks` is a fast lookup without yt-dlp (~0.3 s, whole-file links when available); `YtDlpService` is the fallback and the Android downloader, auto-updating yt-dlp from GitHub daily, with extra args from remote config. `StreamProxy` (127.0.0.1) sits between players and YouTube: it slices requests into ≤ ~10 MB `range=` pieces (YouTube throttles or 403s large ranges), matches the link's IP version, and swaps fast-lookup links for yt-dlp's mid-playback. Android yt-dlp downloads are routed through it too (`routeInfoJson`).

**Downloads (`DownloadService`).** One queue, sources in `DownloadTask.source`:
- `youtube`: yt-dlp (fast-lookup info JSON first, client fallbacks after).
- `direct`: own engine, 10 MB chunks over N connections, resumable, end-game splitting of the slowest piece; browser downloads carry the page's User-Agent/Referer and fresh WebView cookies.
- `tiktok` / `stream`: yt-dlp on the URL (HLS/DASH manifest or page).
- Network errors mark a task "Connection lost" and it auto-resumes when a real connection works again; expired browser links offer "Refresh link" (reopens the page in `BrowserController` with the task and matches the recaptured file).
- Partial data of yt-dlp tasks lives in `YtDlpService.workRoot/<taskId>`; direct tasks use `<file>.part` (+ `.chunks/`).

**In-app browser (`modules/browser`).** Chrome-like and tabbed: `BrowserSession` (route controller) owns the tabs, one `BrowserController` per tab (tag = tab id); `tab_session.dart` holds the pure tab rules (order, opener, the last 4 pages kept loaded, 2 on low-end phones, others reload when shown). Incognito tabs (`incognito.dart`) get their own cookies and site data, deleted when the last one closes: on Android a WebView profile per session (`toomu/incognito` → `IncognitoBridge.kt`, set before the tab's first page, so its WebView starts empty and `onCreated` loads it), on Windows WebView2 InPrivate; they skip history and aren't restored. Tabs, history and bookmarks persist in `BrowserStore` (own GetStorage box `browser`; pure rules in `browsing_data.dart`). The new-tab page (`toomu://newtab`) is a Flutter screen; `address.dart` has what the bar shows (just the site), URL-vs-search, and suggestion merging (bookmarks, history, Google suggest). ⋮ menu (`browser_menu.dart`), tab switcher, History/Bookmarks pages, find in page and pull to refresh (Android), Desktop site, long-press link and image menus (`link_menu.dart`, `image_menu.dart`). On Android 7–9 a page that fails for a non-network reason shows why (`engine_notice.dart`: no more WebView updates there). Each tab's page is an InAppWebView with an injected script (`media_sniffer.dart`, runs in all frames) that reports media candidates to `MediaCapture`, which probes, parses HLS/DASH qualities (`core/utils/media_manifest.dart`), drops segments/tiny files and marks DRM; the result shows in `views/media_sheet.dart`. `redirect_guard.dart` blocks ad redirects/popups (popups load in the same tab, so all go through `shouldOverrideUrlLoading`): a cross-site jump right after a tap not on a link to that site, or any navigation to a host on the downloaded blocklist (StevenBlack hosts + gambling, refreshed weekly). Ad resources aren't blocked: the plugin's Android content blocker sends a HEAD request per resource. On Android the page is paused (`pause` + process-wide `pauseTimers`) while the app is hidden or Toomu's player is open over it. The top bar's downloads button (`views/downloads_sheet.dart`) shows progress and the download list in a sheet so the page stays open. `extractors/` handles pages with a dedicated flow (YouTube, direct file links).

**App updates.** CI passes the release tag as `--dart-define=TOOMU_TAG` (Android and Windows); `UpdateService` checks GitHub's latest release (every app open, again on return after an hour, and Settings → Check for updates); on Windows it downloads `toomu-windows-setup.exe` and runs it silently if Toomu was installed with it (`unins000.exe` beside the exe), else opens the zip link. On Android it downloads the APK for the phone's ABI and installs it through a `PackageInstaller` session (`toomu/update` → `UpdateReceiver.kt`, `REQUEST_INSTALL_PACKAGES`); on Android 12+ only the first update asks for confirmation, later ones are silent because Toomu is then the installer of record. Builds without a tag (local/dev) never auto-check. Phones only accept an update signed with the same key, so CI needs the `ANDROID_KEYSTORE_*` secrets.

**Remote config.** `RemoteConfigService` fetches a static JSON at startup (shape in `remote_config.example.json`): yt-dlp args/channel, connections, start-page sites, feed categories, browser blocklist URL; every field optional.
