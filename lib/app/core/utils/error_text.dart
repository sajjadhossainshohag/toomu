import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../data/providers/ytdlp/ytdlp_bridge.dart';

/// Turns exceptions into short messages a user can act on.
abstract class ErrorText {
  static String _ytdlp(String m) {
    final l = m.toLowerCase();
    if (l.contains('not a bot') || l.contains('sign in to confirm')) {
      return "YouTube is asking this network to prove it's not a bot. Try again later, or switch between Wi-Fi and mobile data.";
    }
    if (l.contains('http error 403') || l.contains('forbidden')) {
      return 'YouTube refused the download (403). The downloader updates itself daily; try again later.';
    }
    if (l.contains('requested format is not available')) {
      return "That quality isn't available right now. Pick another one.";
    }
    if (l.contains('private video')) return 'This video is private.';
    if (l.contains('age')) return 'This video is age-restricted and needs a signed-in account.';
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
