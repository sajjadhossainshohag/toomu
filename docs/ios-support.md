# Supporting iOS

What it takes to make Toomu work on iPhone. Toomu is a Flutter app, so its
UI and most of its logic are shared. What doesn't carry over is the **native
Android layer** (Kotlin) and the **yt-dlp engine**, which is bundled for
Android only. This document lists each piece, what replaces it on iOS, and a
suggested order of work.

Status (Nov 2026): CI can build an **unsigned `.ipa`** (`.github/workflows/build.yml`,
iOS job on `v*` tags or by hand). That build has not been run yet, so the
first run may need iOS setup fixes. Even when it builds, downloading, the
bubble and the media library are missing (see below).

## 1. Distribution comes first

Apple's App Review rejects apps that download from YouTube and similar
services (Guideline 5.2.3, third-party content), and apps that download
and run new code (Guideline 2.5.2; yt-dlp updates itself). So the App
Store isn't an option. Ways to install:

| Way | Needs | Lasts |
|---|---|---|
| AltStore / SideStore / Sideloadly | A free Apple ID | 7 days, then re-sign (AltStore can refresh by itself) |
| Same tools with a paid account | Apple Developer Program, $99/year | 1 year |
| AltStore PAL (EU only) | Notarization by Apple (still reviewed) | — |
| TrollStore | Specific older iOS versions only | Permanent |

Signing in CI needs an Apple certificate and provisioning profile as Secrets
(e.g. with fastlane `match`). The current CI job builds unsigned on purpose.

## 2. What already works on iOS (shared Dart code)

Expected to work once the build runs, with small fixes at most:

- YouTube search, home feed, categories, signed-in Home/Subscriptions
  (`youtube_provider.dart`, `account_feed.dart`)
- YouTube sign-in pages (`flutter_inappwebview`, iOS supported)
- **Watching YouTube ad-free**: fast visionOS lookup (pure Dart) + the local
  stream proxy (`stream_proxy.dart`, pure Dart) + the video player
  (`media_kit`, iOS supported)
- **Play audio** from YouTube (`just_audio`, iOS supported)
- Settings, theme, diagnostics log

Needed for these on iOS:

- **Info.plist**
  - `NSAppTransportSecurity` → `NSAllowsLocalNetworking: true`. The players
    reach the stream proxy over plain `http://127.0.0.1`, which ATS blocks
    by default.
  - `UIBackgroundModes: audio` for playback with the screen off.
  - `NSPhotoLibraryAddUsageDescription` once saving videos to Photos exists.
- **Audio session** set to `.playback` (via `audio_session`) so sound plays
  in silent mode and in the background.
- The deployment target is iOS 13.0; check that every plugin's minimum
  (media_kit, flutter_inappwebview) is met. Raise it if a plugin needs more.

## 3. What has to be rebuilt

The Dart side talks to Android through these channels. Each needs an iOS
implementation (Swift), an iOS alternative, or to be hidden on iOS.

| Channel | Android does | On iOS |
|---|---|---|
| `toomu/ytdlp` + `toomu/ytdlp/progress` | Runs yt-dlp (Python, FFmpeg, aria2c, QuickJS) | **The big one**; see §4 |
| `toomu/download_notify` | Foreground service + progress notifications | Local notifications; Live Activity for progress (optional) |
| `toomu/media_library` | Lists device music/videos (MediaStore), thumbnails, artwork, delete | Toomu's own files instead (see §5); Photos for videos |
| `toomu/media_scanner` | Adds finished downloads to the gallery | Save to Photos (`PHPhotoLibrary`) / Files app |
| `toomu/video` | Picture-in-picture, background-play notification, media buttons | Media controls via `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`. PiP needs `AVPictureInPictureController`, which mpv can't drive: either no PiP, or an AVPlayer-based player for PiP |
| `toomu/intents` | "Share to Toomu", "Open with Toomu" | A **Share Extension** target (Swift) handing the link to the app through an App Group; document types for "Open in" |
| `toomu/bubble` | Floating button over the YouTube app | **Not possible on iOS** (no overlays over other apps). Hide it; the Share Extension replaces it |

Android-only settings to hide on iOS: floating button, one-tap download
(notification access), connections per download (aria2c), and folder
choice. Check `Platform.isAndroid` in `settings_view.dart`.

## 4. Downloading without yt-dlp's Android bundle

iOS forbids starting other programs (`fork`/`exec`), so the Android setup
(Python, FFmpeg and aria2c run as executables) can't be copied. Two routes:

### Route A: Dart downloader + AVFoundation (recommended)

Most of the pieces already exist in Dart:

1. **Links:** the visionOS fast lookup (`YoutubeProvider.fastLinks`) gives
   whole-file links with no JS challenge or PO token. TikTok:
   `TiktokService.itemFromUrl` gives the file link (`playAddr`); it needs
   the page's cookies and Referer.
2. **Transfer:** the stream proxy's piece logic (≤ 8 MB `range=` requests,
   retries, IPv4/IPv6 matching) reused as a file downloader writing
   video and audio parts to disk. Parallel pieces are optional.
3. **Joining video + audio:** a small Swift plugin using AVFoundation
   (`AVMutableComposition` + `AVAssetExportSession` with the passthrough
   preset; no re-encoding).
   - AVFoundation only joins MP4-family streams, so on iOS pick **H.264 +
     AAC** (itag 137/136… + 140); VP9/AV1/Opus (WebM) can't be joined there.
   - 1440p/4K on YouTube are mostly VP9/AV1: on iOS offer up to 1080p, or
     add FFmpeg (Route B).
4. **Audio:** iOS has no MP3 encoder. Offer **M4A** (the original AAC, no
   conversion), or bundle LAME (small, LGPL) for MP3.
5. **In the background:** iOS suspends apps. Use background `URLSession`
   transfers (e.g. the `background_downloader` plugin). It takes whole
   requests, so queue the ≤ 8 MB pieces as separate tasks, or accept that a
   download pauses while the app is closed.

What's lost compared with Android: yt-dlp's breadth (other sites, its
fallback clients when visionOS stops working) and its daily fixes. If
YouTube changes visionOS, iOS breaks until the app is updated.

### Route B: embed Python + yt-dlp

- **Python:** run it in-process from
  [Python-Apple-support](https://github.com/beeware/Python-Apple-support),
  as BeeWare and Pyto do. No subprocesses, so yt-dlp is called as a library
  (`yt_dlp.YoutubeDL(...)`).
- **JS challenge:** a small yt-dlp plugin (a `JsChallengeProvider`) that
  calls iOS's own JavaScriptCore instead of QuickJS. Most videos don't need
  it (visionOS).
- **FFmpeg** as an xcframework library (ffmpeg-kit was retired in 2025;
  build FFmpeg or use a maintained fork), called in-process, not as a
  program.
- **Cost:** about +40 MB, slow start-up, the most work. In exchange it keeps
  yt-dlp's coverage and fixes. It's fine for sideloading, but never App
  Store compatible.

## 5. Media library

iOS gives apps no general access to the user's music or video files.

- **Toomu's library = its own downloads:** files in the app's Documents
  folder. Set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`
  so they also show in the Files app.
- **Videos:** optionally "Save to Photos" (`PHPhotoLibrary`).
- **Music:** Apple Music / the iTunes library (`MPMediaLibrary`) can be read
  for playback, but apps can't add songs to it. Downloaded audio stays in
  Toomu.
- The Music and Videos tabs then list Toomu's folder instead of MediaStore.
  It's best to put `media_library` behind one interface with an Android
  implementation (MediaStore) and an iOS one (app folder).

## 6. Suggested order

| Step | Work | Result |
|---|---|---|
| 1 | Run the CI iOS build; fix plugin and config errors; Info.plist (ATS local networking, background audio) | An iPhone build that opens |
| 2 | Hide Android-only UI; guard each `toomu/*` channel with `Platform.isAndroid` | No crashes from missing native code |
| 3 | Check watching + Play audio on a device; media controls (`MPNowPlayingInfoCenter`) | A working ad-free YouTube player |
| 4 | Route A downloader: piece transfer to files + Swift AVFoundation join; H.264/AAC only; M4A audio | Downloads up to 1080p |
| 5 | Library from the app folder; Files sharing; Save to Photos | Downloads are playable and findable |
| 6 | Share Extension (YouTube/TikTok links) | Replaces the floating bubble |
| 7 | Background transfers, notifications | Downloads survive leaving the app |
| 8 (optional) | Route B (Python + yt-dlp + FFmpeg) for 4K, MP3, other sites | Android-level coverage |

Rough effort for steps 1–7 with Route A: a few weeks of focused work.
Route B adds about as much again.

## 7. Testing

- A real iPhone is needed. The Simulator can't check background transfers,
  PiP or the Share Extension well.
- CI only builds. Signed test builds need an Apple certificate and profile
  as Secrets, plus a way to install them (AltStore, or TestFlight while
  sideloading isn't needed).
