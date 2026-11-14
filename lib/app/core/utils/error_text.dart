import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../data/providers/ytdlp/ytdlp_bridge.dart';

/// Turns exceptions into short messages a user can act on.
abstract class ErrorText {
  static String _ytdlp(String m) {
    final local = localFileProblem(m);
    if (local != null) return local;
    final l = m.toLowerCase();
    if (l.contains('cookies are no longer valid')) {
      return 'Your YouTube sign-in has expired. Sign in again in Settings → YouTube account.';
    }
    // Whole phrases: a bare 'age' also matches "page", "storage", "image".
    if (l.contains('age-restricted') || l.contains('age restricted') || l.contains('confirm your age') ||
        l.contains('inappropriate for some users')) {
      return 'This video is age-restricted. Sign in to YouTube (Settings → YouTube account) to watch or download it.';
    }
    // "Sign in to confirm you're not a bot" — not every "sign in to
    // confirm…" (that's also how YouTube asks for your age).
    if (l.contains('not a bot')) {
      return "YouTube is asking this network to prove it's not a bot. Try again later, or switch between Wi-Fi and mobile data.";
    }
    if (l.contains('http error 403') || l.contains('forbidden')) {
      return 'YouTube refused the download (403). The downloader updates itself daily; try again later.';
    }
    if (l.contains('requested format is not available')) {
      return "That quality isn't available right now. Pick another one.";
    }
    if (l.contains('private video')) return 'This video is private.';
    if (l.contains('unable to download') && l.contains('network')) return 'Network error. Check your connection.';
    return m.length > 160 ? '${m.substring(0, 160)}…' : m;
  }

  static String of(Object e) {
    if (e is YtDlpException) return _ytdlp(e.message);
    if (e is VideoRequiresPurchaseException) return 'This video requires a purchase.';
    if (e is VideoUnplayableException) {
      return "This video can't be downloaded (private, age-restricted or blocked in your region).";
    }
    if (e is RequestLimitExceededException) {
      return 'YouTube is limiting requests right now. Try again in a few minutes.';
    }
    if (e is SocketException || e is HandshakeException) return 'No internet connection.';
    if (e is TimeoutException) {
      return e.message == null ? 'The connection timed out.' : '${e.message}. Try again in a moment.';
    }
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 403) return 'YouTube refused the download (403). Tap retry.';
      if (code != null) return 'Server error ($code).';
      if (e.error is SocketException) return 'No internet connection.';
      return 'Network error. Check your connection.';
    }
    if (e is FileSystemException) {
      return 'Could not save the file: ${e.osError?.message ?? e.message}';
    }
    if (e is PlatformException) return e.message ?? e.code;
    if (e is StateError) return e.message;
    final text = e.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }
}
