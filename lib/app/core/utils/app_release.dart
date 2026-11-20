class AppRelease {
  const AppRelease({required this.tag, required this.notes, required this.fileUrl, required this.fileSize});

  final String tag;
  final String notes;

  /// The release's file for this device (APK, Windows installer or zip); null if it has none (yet: the Windows
  /// files are attached a few minutes after the release is published).
  final String? fileUrl;
  final int fileSize;

  /// Release files for this device, best first: the APK for the phone's CPU types, or on Windows the installer
  /// (a copy installed with it updates itself) or the portable zip.
  static List<String> fileNames({required bool windows, bool installed = false, List<String> abis = const []}) =>
      windows
          ? [installed ? 'toomu-windows-setup.exe' : 'toomu-windows-x64.zip']
          : [for (final abi in abis) 'toomu-$abi.apk'];

  static final _dated = RegExp(r'^v\d{4}\.\d{2}\.\d{2}-\d{4}$');

  static bool isNewer(String latest, String current) {
    if (current.isEmpty) return true;
    // A build that failed its checks has a tag that never got released, so
    // dated tags are compared, not just told apart.
    if (_dated.hasMatch(latest) && _dated.hasMatch(current)) return latest.compareTo(current) > 0;
    return latest != current;
  }

  static final _tagPath = RegExp(r'/releases/tag/([^/?#]+)');

  static String? tagFromLocation(String? location) {
    final tag = location == null ? null : _tagPath.firstMatch(location)?.group(1);
    return tag == null ? null : Uri.decodeComponent(tag);
  }

  /// [names]: see [fileNames].
  static AppRelease fromGitHub(Map<String, dynamic> json, List<String> names) {
    final assets = (json['assets'] as List? ?? const []).whereType<Map>().toList();
    Map? file;
    for (final name in names) {
      file = assets.where((a) => a['name'] == name).firstOrNull;
      if (file != null) break;
    }
    return AppRelease(
      tag: '${json['tag_name'] ?? ''}',
      notes: '${json['body'] ?? ''}'.trim(),
      fileUrl: file?['browser_download_url'] as String?,
      fileSize: (file?['size'] as num?)?.toInt() ?? 0,
    );
  }
}
