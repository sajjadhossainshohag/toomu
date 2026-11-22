import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../services/download_service.dart';
import '../../../services/tiktok_service.dart';
import '../../../services/ytdlp_service.dart';

import '../../../core/utils/link_parser.dart';
import '../../../data/models/video_item.dart';
import '../../../data/providers/local_music_provider.dart';
import '../../../data/providers/local_video_provider.dart';
import '../../../routes/app_pages.dart';
import '../../browser/address.dart';
import '../../browser/controllers/browser_session.dart';
import '../../settings/views/settings_view.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../../extractors/direct_file_extractor.dart';
import '../../../services/floating_button_service.dart';
import '../../../services/permission_service.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/option_sheet.dart';
import '../../../data/models/media_format.dart';
import '../../../data/models/download_task.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../home_tabs.dart';
import '../../../widgets/app_snackbar.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  /// Links handed over by Android: "Download with Toomu" in the share sheet,
  /// or a tap on the floating bubble shown over YouTube.
  static const _intents = MethodChannel('toomu/intents');

  final tabIndex = 0.obs;

  /// Pages switch from the nav bar only (swiping switches a page's inner tabs).
  final pageController = PageController();

  final hubSearch = TextEditingController();

  String? _lastClipboardLink;
  DateTime _lastIntentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _intents.setMethodCallHandler((call) async {
      if (call.method == 'intent' && call.arguments is Map) {
        await _handleIntent(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  @override
  void onReady() {
    super.onReady();
    PermissionService.to.requestNotifications();
    unawaited(_initialIntent().then((_) => checkClipboard()));
  }

  @override
  void onClose() {
    pageController.dispose();
    hubSearch.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _intents.setMethodCallHandler(null);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkClipboard();
  }

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    ArtworkCache.clear();
    VideoThumbCache.clear();
    if (Get.isRegistered<YoutubeController>()) Get.find<YoutubeController>().trimFeedCache();
    if (Get.isRegistered<BrowserSession>()) BrowserSession.to.dropBackgroundPages();
  }

  /// Nav bar tap / programmatic switch: jump straight there (no scrolling
  /// through the tabs in between).
  void selectTab(int index) {
    tabIndex.value = index;
    if (pageController.hasClients && pageController.page?.round() != index) {
      pageController.jumpToPage(index);
    }
  }

  /// Swipe finished on a tab.
  void onPageChanged(int index) => tabIndex.value = index;

  /// Runs [action] once tab [id] is shown (now, or when the user gets
  /// there). Lets tabs defer work like permission prompts until visible,
  /// since swiping builds neighbouring tabs early.
  void whenTabShown(String id, VoidCallback action) {
    final index = HomeTabs.indexOf(id);
    if (tabIndex.value == index) {
      action();
      return;
    }
    late final Worker worker;
    worker = ever(tabIndex, (int i) {
      if (i != index) return;
      worker.dispose();
      action();
    });
  }

  void openTab(String id) => selectTab(HomeTabs.indexOf(id));

  void openSettings() => Get.to<void>(() => Scaffold(body: SettingsView(onBack: () => Get.back<void>())));

  Future<void> openFromHome(String input) async {
    final text = input.trim();
    if (text.isEmpty || await openLinkFrom(text)) return;
    // A link in the text opens it; anything else is an address or a Google search (the YouTube tab has its own).
    final url = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
    await openInBrowser(url ?? addressTarget(text));
  }

  @visibleForTesting
  Future<void> openInBrowser(String url) async => Get.toNamed<void>(Routes.browser, arguments: url);

  Future<void> pasteFromHome() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (text.isEmpty) {
      showSnack('Clipboard is empty', 'Copy a link first.', duration: const Duration(seconds: 2));
      return;
    }
    hubSearch.text = text;
    await openFromHome(text);
  }

  // ------------------------------------------------------- share & bubble

  Future<void> _initialIntent() async {
    final payload = await _intents.invokeMapMethod<String, dynamic>('initial');
    if (payload != null) await _handleIntent(payload);
  }

  Future<void> _handleIntent(Map<String, dynamic> payload) async {
    _lastIntentAt = DateTime.now();
    switch (payload['type']) {
      case 'openDownloads':
        // Tapped the download notification.
        openTab(HomeTabs.downloads);
      case 'video':
        // "Open with Toomu" from a file manager / gallery.
        final uri = payload['uri'] as String?;
        if (uri != null) {
          await Get.toNamed(
            Routes.videoPlayer,
            arguments: VideoPlaylist([
              VideoItem.file(uri, name: payload['name'] as String?),
            ]),
          );
        }
      case 'share':
        final text = (payload['text'] as String?) ?? '';
        if (!await openLinkFrom(text)) {
          showSnack(
            'Nothing to download',
            'The shared text has no video or file link.',
            duration: const Duration(seconds: 3),
          );
        }
      case 'bubble':
        // 1. YouTube's media session said what's playing (Notification access).
        final title = payload['title'] as String?;
        if (title != null && title.isNotEmpty) {
          Get.closeAllSnackbars();
          openTab(HomeTabs.youtube);
          final ms = (payload['durationMs'] as num?)?.toInt() ?? 0;
          unawaited(
            Get.find<YoutubeController>().openPlaying(
              title: title,
              artist: payload['artist'] as String?,
              duration: ms > 0 ? Duration(milliseconds: ms) : null,
              mediaId: payload['mediaId'] as String?,
            ),
          );
          return;
        }
        // 2. A copied link (Toomu is in front now, so it may read the clipboard).
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        final ok = clip?.text != null && await openLinkFrom(clip!.text!);
        if (!ok) {
          final access = await FloatingButtonService.to.hasNowPlayingAccess();
          await showNoticeDialog(
            title: access ? 'Nothing playing' : 'Turn on one-tap download',
            message: access
                ? 'Play a video in YouTube, then tap the download bubble.'
                : 'To open the download options straight from the bubble, allow Toomu '
                      '"Notification access" in Settings → YouTube app → Floating download button.\n\n'
                      'Or in YouTube tap Share → "Download with Toomu".',
          );
        }
    }
  }

  /// A TikTok link: the video (no watermark) or just its sound, then Downloads.
  Future<void> _downloadTiktok(String url) async {
    final format = await showOptionSheet<MediaFormat>(
      title: 'Download TikTok',
      options: [
        for (final f in MediaFormat.tiktokOptions)
          SheetOption(
            value: f,
            label: f.name,
            subtitle: f.detail,
            icon: f.kind == DownloadKind.audio ? Icons.music_note_outlined : Icons.movie_outlined,
          ),
      ],
    );
    if (format == null) return;
    showSnack(
      'TikTok',
      'Getting the video…',
      duration: const Duration(seconds: 2),
    );
    final item = await TiktokService.itemFromUrl(url);
    if (item == null) {
      showSnack(
        "Can't download this TikTok",
        "This link doesn't lead to a TikTok video.",
        duration: const Duration(seconds: 4),
      );
      return;
    }
    await DownloadService.to.enqueueTiktok(item, format: format);
    openTab(HomeTabs.downloads);
    showSnack(
      'Download started',
      item.caption.isEmpty ? '@${item.authorId}' : item.caption,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _downloadSocial(String url) async {
    final site = url.contains('instagram.com') ? 'Instagram' : 'Facebook';
    showSnack(site, 'Getting the video…', duration: const Duration(seconds: 2));
    try {
      final cookies = await DownloadService.webCookies(url);
      final info = await YtDlpService.to.pageInfo(
        url,
        DownloadService.headerArgs({if (cookies.isNotEmpty) 'Cookie': cookies}),
      );
      await DownloadService.to.enqueueStream(
        url: url,
        title: info.title,
        // H.264 first: older phones can't decode VP9 in hardware.
        format: 'bv*[vcodec^=avc1]+ba/b[vcodec^=avc1]/bv*+ba/b',
        thumbnailUrl: info.thumbnail ?? '',
        pageUrl: url,
      );
      openTab(HomeTabs.downloads);
      showSnack('Download started', info.title, duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[Download] $site link failed: $e');
      // Usually a sign-in wall: signing in in the browser gives yt-dlp the cookies it needs.
      showSnack(
        "Can't get this $site video yet",
        'Opening it in the browser. Sign in if $site asks, then tap Download.',
        duration: const Duration(seconds: 5),
      );
      await Get.toNamed<void>(Routes.browser, arguments: url);
    }
  }

  /// Opens the download flow for the first supported link in [text].
  Future<bool> openLinkFrom(String text) async {
    final tiktok = TiktokService.linkIn(text);
    if (tiktok != null) {
      Get.closeAllSnackbars();
      unawaited(_downloadTiktok(tiktok));
      return true;
    }
    final social = LinkParser.socialVideo(text);
    if (social != null) {
      Get.closeAllSnackbars();
      unawaited(_downloadSocial(social));
      return true;
    }
    final list = LinkParser.youtubeCollection(text);
    if (list != null) {
      Get.closeAllSnackbars();
      openTab(HomeTabs.youtube);
      unawaited(Get.find<YoutubeController>().openCollection(list));
      return true;
    }
    final id = LinkParser.youtubeVideoId(text);
    if (id != null) {
      _lastClipboardLink = id; // don't also offer it via the clipboard snackbar
      Get.closeAllSnackbars();
      openTab(HomeTabs.youtube);
      unawaited(Get.find<YoutubeController>().openVideo(id));
      return true;
    }
    final url = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && const DirectFileExtractor().canHandle(uri)) {
        unawaited(DirectFileExtractor.startDownload(url));
        return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------ clipboard

  /// 1DM/Snaptube-style: offer to download a link the user just copied.
  Future<void> checkClipboard() async {
    if (!SettingsService.to.clipboardLinks.value) return;
    // A share/bubble intent may arrive right after resume; let it win.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (DateTime.now().difference(_lastIntentAt) < const Duration(seconds: 2)) {
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    final id = LinkParser.youtubeVideoId(text);
    if (id == null || id == _lastClipboardLink) return;
    _lastClipboardLink = id;

    showSnack(
      'Link detected',
      'Download the YouTube video you copied?',
      duration: const Duration(seconds: 6),
      mainButton: TextButton(
        onPressed: () {
          Get.closeCurrentSnackbar();
          openTab(HomeTabs.youtube);
          Get.find<YoutubeController>().openVideo(id);
        },
        child: const Text('Download'),
      ),
    );
  }
}
