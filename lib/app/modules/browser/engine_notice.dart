/// Android 7–9 no longer get web engine (WebView) updates: Chrome 119 was
/// the last for Android 7, Chrome 138 for Android 8 and 9. When a page
/// fails to load there for a reason other than the network, say why.
library;

/// Error kinds that mean "no network", not "old engine".
const _networkErrors = {
  'HOST_LOOKUP',
  'CANNOT_CONNECT_TO_HOST',
  'TIMEOUT',
  'CANCELLED',
  'NOT_CONNECTED_TO_INTERNET',
  'NETWORK_CONNECTION_LOST',
  'CONNECT',
  'IO',
};

/// First Android SDK whose web engine still gets updates (Android 10).
const updatedEngineSdk = 29;

String androidName(int sdk) => switch (sdk) {
  24 => '7.0',
  25 => '7.1',
  26 => '8.0',
  27 => '8.1',
  28 => '9',
  _ => '$sdk',
};

/// The notice for a page that failed with [errorType] (WebResourceErrorType
/// name), or null when it isn't the engine's age. [webViewVersion]:
/// "119.0.6045.193" → "Chrome 119".
String? outdatedEngineNotice({required int androidSdk, required String webViewVersion, required String errorType}) {
  if (androidSdk <= 0 || androidSdk >= updatedEngineSdk) return null;
  if (_networkErrors.contains(errorType.toUpperCase())) return null;
  final major = RegExp(r'^\d+').firstMatch(webViewVersion.trim())?.group(0);
  final engine = major == null ? '' : ' (yours is Chrome $major)';
  return 'Android ${androidName(androidSdk)} no longer gets web engine updates$engine, '
      'so some sites may not open. Phones with Android 10 or newer open every site.';
}
