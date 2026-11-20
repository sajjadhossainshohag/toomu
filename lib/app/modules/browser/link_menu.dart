/// What a long-pressed link offers (Chrome's link menu).
enum LinkAction {
  openNewTab('Open in new tab'),
  openIncognito('Open in incognito tab'),
  copyAddress('Copy link address'),
  copyText('Copy link text'),
  download('Download link'),
  share('Share link');

  const LinkAction(this.label);

  final String label;
}

class PageLink {
  const PageLink({required this.href, this.text = ''});

  final String href;

  /// The words of the link on the page.
  final String text;

  String get _scheme => href.split(':').first.toLowerCase();
  bool get isWebLink => _scheme == 'http' || _scheme == 'https';

  /// Header line: the link's words, else its address.
  String get title {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isNotEmpty ? t : href;
  }
}

/// Web links get everything; mailto:, tel: and the like can only be
/// copied or shared (they don't open as pages or download). In an [incognito] tab "Open in new tab" is
/// incognito already.
List<LinkAction> linkActions(PageLink link, {bool incognito = false}) => [
  if (link.isWebLink) LinkAction.openNewTab,
  if (link.isWebLink && !incognito) LinkAction.openIncognito,
  LinkAction.copyAddress,
  if (link.text.trim().isNotEmpty) LinkAction.copyText,
  if (link.isWebLink) LinkAction.download,
  LinkAction.share,
];

/// Script that finds the words of the link to `href` on the page.
const linkTextJs = '''
var list = document.links;
for (var i = 0; i < list.length; i++) {
  if (list[i].href === href) return String(list[i].innerText || list[i].title || '').trim().slice(0, 300);
}
return '';
''';
