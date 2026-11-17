import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/browser_store.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/empty_state.dart';
import '../controllers/browser_session.dart';
import 'history_page.dart';

/// Starred pages: open one, search, or remove it.
class BookmarksPage extends StatelessWidget {
  BookmarksPage({required this.session, super.key});

  final BrowserSession session;
  final _query = ''.obs;

  @override
  Widget build(BuildContext context) {
    final store = BrowserStore.to;
    return Scaffold(
      backgroundColor: ColorConstants.pageOn(context.isDark),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AppHeader(
              title: 'Bookmarks',
              onBack: Get.back,
              bottom: AppSearchField(hint: 'Search bookmarks', onChanged: (v) => _query.value = v),
            ),
            Expanded(
              child: Obx(() {
                store.bookmarksVersion.value;
                final items = store.bookmarks.search(_query.value);
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.star_border_rounded,
                    title: _query.value.isEmpty ? 'No bookmarks yet' : 'Nothing found',
                    message: _query.value.isEmpty ? 'Tap ☆ in the ⋮ menu to save a page here.' : 'Try other words.',
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.only(top: 8 * context.scale, bottom: 24 * context.scale),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final b = items[i];
                    return PageRow(
                      key: ObjectKey(b),
                      visit: b,
                      onTap: () {
                        Get.back<void>();
                        session.tab.navigate(b.url);
                      },
                      onRemove: () => store.removeBookmark(b.url),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
