import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import 'app_header.dart';

class Selection {
  final ids = <String>{}.obs;

  bool get active => ids.isNotEmpty;
  int get count => ids.length;
  bool contains(String id) => ids.contains(id);
  void toggle(String id) => ids.contains(id) ? ids.remove(id) : ids.add(id);
  void selectAll(Iterable<String> all) => ids.addAll(all);
  void clear() => ids.clear();
  List<Worker> clearOnChange(Iterable<RxInterface<Object?>> triggers) => [
        for (final t in triggers) ever(t, (_) => clear()),
      ];
  List<T> pick<T>(Iterable<T> items, String Function(T) idOf) => items.where((e) => ids.contains(idOf(e))).toList();
}

class SelectionHeader extends StatelessWidget {
  const SelectionHeader({
    required this.selection,
    required this.header,
    required this.onSelectAll,
    required this.onPrivate,
    required this.onDelete,
    super.key,
  });

  final Selection selection;
  final Widget Function() header;
  final VoidCallback onSelectAll;
  final VoidCallback onPrivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Obx(() {
        final normal = header();
        return PopScope(
          canPop: !selection.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) selection.clear();
          },
          child: !selection.active
              ? normal
              : AppHeader(
                  title: '${selection.count} selected',
                  onBack: selection.clear,
                  backIcon: Icons.close_rounded,
                  // The same search field, so its text survives entering and leaving selection.
                  bottom: normal is AppHeader ? normal.bottom : null,
                  actions: <Widget>[
                    HeaderAction(icon: Icons.select_all_rounded, tooltip: 'Select all', onTap: onSelectAll),
                    HeaderAction(icon: Icons.lock_outline_rounded, tooltip: 'Move to private folder', onTap: onPrivate),
                    HeaderAction(icon: Icons.delete_outline_rounded, tooltip: 'Delete', onTap: onDelete),
                  ],
                ),
        );
      });
}

class SelectionMark extends StatelessWidget {
  const SelectionMark({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 36 * context.scale,
        child: Icon(
          selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 24 * context.scale,
          color: selected
              ? (context.isDark ? BrandColors.of(context).accent : BrandColors.of(context).primary)
              : ColorConstants.textOn(context.isDark).withValues(alpha: 0.4),
        ),
      );
}
