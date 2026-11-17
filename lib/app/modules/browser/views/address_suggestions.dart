import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../address.dart';
import '../controllers/browser_controller.dart';
import 'site_icon.dart';

/// Under the address bar while typing: what you typed, bookmarks, history
/// and Google's suggestions. Before typing: the current page, to copy or
/// edit its address.
class AddressSuggestions extends StatelessWidget {
  const AddressSuggestions({required this.tab, super.key});

  final BrowserController tab;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    return ColoredBox(
      color: ColorConstants.pageOn(dark),
      child: Obx(() {
        final list = tab.suggestions.toList();
        final showPage = list.isEmpty && !tab.showingNewTab.value;
        return ListView(
          padding: EdgeInsets.symmetric(vertical: 6 * scale),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: <Widget>[
            if (showPage)
              _Row(
                leading: SiteIcon(url: tab.url.value, size: 22),
                title: tab.title.value.isEmpty ? displayAddress(tab.url.value) : tab.title.value,
                subtitle: tab.url.value,
                onTap: () => tab.addressFocus.unfocus(),
                trailing: IconButton(
                  tooltip: 'Copy link',
                  onPressed: tab.copyPageLink,
                  icon: Icon(Icons.copy_rounded, size: 19 * scale, color: ink.withValues(alpha: 0.6)),
                ),
              ),
            for (final s in list)
              _Row(
                leading: switch (s.kind) {
                  SuggestionKind.bookmark => Icon(
                    Icons.star_rounded,
                    size: 21 * scale,
                    color: ink.withValues(alpha: 0.55),
                  ),
                  SuggestionKind.history => Icon(
                    Icons.history_rounded,
                    size: 21 * scale,
                    color: ink.withValues(alpha: 0.55),
                  ),
                  SuggestionKind.typed when looksLikeAddress(s.text) => Icon(
                    Icons.public_rounded,
                    size: 21 * scale,
                    color: ink.withValues(alpha: 0.55),
                  ),
                  _ => Icon(Icons.search_rounded, size: 21 * scale, color: ink.withValues(alpha: 0.55)),
                },
                title: s.kind == SuggestionKind.bookmark || s.kind == SuggestionKind.history
                    ? (s.title.isEmpty ? s.text : s.title)
                    : s.text,
                subtitle: s.kind == SuggestionKind.bookmark || s.kind == SuggestionKind.history ? s.text : null,
                onTap: () => tab.navigate(s.url),
                // Chrome's ↖: put the words in the bar to keep typing.
                trailing: s.kind == SuggestionKind.search || s.kind == SuggestionKind.typed
                    ? IconButton(
                        tooltip: 'Edit',
                        onPressed: () {
                          tab.address.text = '${s.text} ';
                          tab.address.selection = TextSelection.collapsed(offset: tab.address.text.length);
                          tab.onAddressChanged(tab.address.text);
                        },
                        icon: Icon(Icons.north_west_rounded, size: 18 * scale, color: ink.withValues(alpha: 0.5)),
                      )
                    : null,
              ),
          ],
        );
      }),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.title, required this.onTap, this.subtitle, this.trailing});

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18 * scale, 10 * scale, 6 * scale, 10 * scale),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24 * scale,
              child: Center(child: leading),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5 * scale, fontWeight: FontWeight.w500, color: ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.5)),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
