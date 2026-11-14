import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../services/download_service.dart';
import '../../../services/tiktok_service.dart';

import '../../../core/utils/link_parser.dart';
import '../../../data/models/video_item.dart';
import '../../../routes/app_pages.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../../extractors/direct_file_extractor.dart';
import '../../../services/floating_button_service.dart';
import '../../../services/permission_service.dart';
import '../../../widgets/app_dialog.dart';
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
    WidgetsBinding.instance.removeObserver(this);
    _intents.setMethodCallHandler(null);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkClipboard();
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

  /// A TikTok link: straight to Downloads (no watermark).
  Future<void> _downloadTiktok(String url) async {
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
    await DownloadService.to.enqueueTiktok(item);
    openTab(HomeTabs.downloads);
    showSnack(
      'Download started',
      item.caption.isEmpty ? '@${item.authorId}' : item.caption,
      duration: const Duration(seconds: 2),
    );
  }

  /// Opens the download flow for the first supported link in [text].
  Future<bool> openLinkFrom(String text) async {
    final tiktok = TiktokService.linkIn(text);
    if (tiktok != null) {
      Get.closeAllSnackbars();
      unawaited(_downloadTiktok(tiktok));
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
        unawaited(DirectFileExtractor.confirmAndDownload(url));
        return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------ clipboard

  /// 1DM/Snaptube-style: offer to download a link the user just copied.
  Future<void> checkClipboard() async {
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
