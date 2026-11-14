import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/mini_player.dart';
import '../controllers/home_controller.dart';
import '../home_tabs.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Nav pages switch from the bottom bar only; swiping is for the tabs
      // inside a page. Each page is kept alive (scroll positions survive).
      body: PageView.builder(
        controller: controller.pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: controller.onPageChanged,
        itemCount: HomeTabs.all.length,
        itemBuilder: (context, i) => _KeepAlive(child: HomeTabs.all[i].builder(context)),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const MiniPlayer(),
          Obx(
            () => AppBottomNav(
              items: HomeTabs.all.map((t) => t.nav).toList(),
              index: controller.tabIndex.value,
              onTap: controller.selectTab,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a tab's widgets (and scroll position) alive when swiped away.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
