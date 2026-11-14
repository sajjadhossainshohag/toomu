import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Swipe left/right between a page's inner tabs (the pill tabs above it).
/// Kept in sync both ways with [index]: tapping a pill slides here, swiping
/// here selects the pill.
class SwipeTabView extends StatefulWidget {
  const SwipeTabView({
    required this.index,
    required this.count,
    required this.itemBuilder,
    super.key,
  });

  final RxInt index;
  final int count;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<SwipeTabView> createState() => _SwipeTabViewState();
}

class _SwipeTabViewState extends State<SwipeTabView> {
  late final PageController _pages = PageController(
    initialPage: widget.index.value,
  );
  late final StreamSubscription<int> _sub;

  /// True while sliding after a pill tap, so the pages passed on the way
  /// don't get selected.
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.index.listen(_goTo);
  }

  Future<void> _goTo(int i) async {
    if (!_pages.hasClients) return;
    final current = _pages.page?.round() ?? i;
    if (current == i) return;
    _programmatic = true;
    if ((current - i).abs() == 1) {
      await _pages.animateToPage(
        i,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(i);
    }
    _programmatic = false;
  }

  @override
  void dispose() {
    _sub.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pages,
      itemCount: widget.count,
      onPageChanged: (i) {
        if (!_programmatic) widget.index.value = i;
      },
      itemBuilder: (context, i) =>
          _KeepAlive(child: widget.itemBuilder(context, i)),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// For tab bars whose content can't be paged (one shared list): a quick
/// horizontal fling calls [onNext] / [onPrevious].
class SwipeToSwitch extends StatelessWidget {
  const SwipeToSwitch({
    required this.child,
    required this.onNext,
    required this.onPrevious,
    super.key,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) onNext();
        if (v > 300) onPrevious();
      },
      child: child,
    );
  }
}
