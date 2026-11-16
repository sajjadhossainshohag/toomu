class AppRelease {
  const AppRelease({required this.tag, required this.notes, required this.apkUrl, required this.apkSize});

  final String tag;
  final String notes;
  final String? apkUrl;
  final int apkSize;

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

  static AppRelease fromGitHub(Map<String, dynamic> json, List<String> abis) {
    final assets = (json['assets'] as List? ?? const []).whereType<Map>().toList();
    Map? apk;
    for (final abi in abis) {
      apk = assets.where((a) => a['name'] == 'toomu-$abi.apk').firstOrNull;
      if (apk != null) break;
    }
    return AppRelease(
      tag: '${json['tag_name'] ?? ''}',
      notes: '${json['body'] ?? ''}'.trim(),
      apkUrl: apk?['browser_download_url'] as String?,
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
    );
  }
}
