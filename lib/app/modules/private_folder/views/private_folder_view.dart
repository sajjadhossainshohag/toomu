import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/host_os.dart';
import '../../../data/models/download_task.dart';
import '../../../services/private_vault.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/round_icon_button.dart';
import '../controllers/private_folder_controller.dart';

class PrivateFolderView extends GetView<PrivateFolderController> {
  const PrivateFolderView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final stage = controller.stage.value;
          return Column(
            children: <Widget>[
              PageBackHeader(
                title: 'Private folder',
                actions: <Widget>[
                  if (stage == PrivateStage.open)
                    HeaderAction(icon: Icons.password_rounded, tooltip: 'Change PIN', onTap: controller.changePin),
                ],
              ),
              Expanded(
                child: switch (stage) {
                  PrivateStage.loading => const SizedBox.shrink(),
                  PrivateStage.open => const _Files(),
                  _ => const _PinPad(),
                },
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PinPad extends GetView<PrivateFolderController> {
  const _PinPad();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      final stage = controller.stage.value;
      final entered = controller.pin.value.length;
      final error = controller.error.value;
      final title = switch (stage) {
        PrivateStage.create => 'Create a ${PrivateFolderController.pinLength}-digit PIN',
        PrivateStage.confirm => 'Enter the PIN again',
        _ => 'Enter your PIN',
      };
      Widget key(String label, {VoidCallback? onTap, IconData? icon, String? tooltip}) => SizedBox(
            width: 76 * scale,
            height: 64 * scale,
            child: onTap == null
                ? null
                : Tooltip(
                    message: tooltip ?? label,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onTap,
                      child: Center(
                        child: icon != null
                            ? Icon(icon, size: 26 * scale, color: ink)
                            : Text(label, style: TextStyle(fontSize: 26 * scale, fontWeight: FontWeight.w600, color: ink)),
                      ),
                    ),
                  ),
          );
      Widget digit(String d) => key(d, onTap: () => controller.press(d));
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: DesignMetrics.gutter * scale, vertical: 12 * scale),
        child: Column(
          children: <Widget>[
            Icon(Icons.lock_rounded, size: 40 * scale, color: ColorConstants.primary),
            SizedBox(height: 12 * scale),
            Text(title, style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w700, color: ink)),
            SizedBox(height: 18 * scale),
            Semantics(
              label: '$entered of ${PrivateFolderController.pinLength} digits entered',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < PrivateFolderController.pinLength; i++)
                    Container(
                      width: 14 * scale,
                      height: 14 * scale,
                      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < entered ? ColorConstants.primary : Colors.transparent,
                        border: Border.all(color: ColorConstants.primary, width: 2),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12 * scale),
            SizedBox(
              height: 56 * scale,
              child: Text(
                error ??
                    (stage == PrivateStage.create && HostOs.isWindows
                        ? 'Forgot it? Windows Hello can reset it.\nUninstalling asks whether to keep private files.'
                        : stage == PrivateStage.create
                        ? "Forgot it? Only your fingerprint or face can reset it, not the phone's PIN.\n"
                            'Uninstalling Toomu deletes private files unless you tick "Keep app data".'
                        : ''),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5 * scale,
                  color: error != null ? ColorConstants.error : ink.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) digit(d)]),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                stage == PrivateStage.locked && controller.canUseBiometrics.value
                    ? key('', icon: Icons.fingerprint_rounded, tooltip: 'Unlock with fingerprint', onTap: controller.unlockWithBiometrics)
                    : key(''),
                digit('0'),
                key('', icon: Icons.backspace_outlined, tooltip: 'Delete digit', onTap: controller.backspace),
              ],
            ),
            if (stage == PrivateStage.locked) ...<Widget>[
              SizedBox(height: 8 * scale),
              TextButton(onPressed: controller.forgotPin, child: const Text('Forgot PIN?')),
            ],
          ],
        ),
      );
    });
  }
}

class _Files extends GetView<PrivateFolderController> {
  const _Files();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      final files = controller.files.toList();
      if (files.isEmpty) {
        return const EmptyState(
          icon: Icons.lock_rounded,
          title: 'Nothing here yet',
          message: 'In Videos, Music or Downloads, open a file\'s menu and pick "Move to private folder".',
        );
      }
      return ListView.builder(
        padding: EdgeInsets.only(bottom: 24 * scale),
        itemCount: files.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: EdgeInsets.fromLTRB(DesignMetrics.gutter * scale, 0, DesignMetrics.gutter * scale, 8 * scale),
              child: Text(
                HostOs.isWindows
                    ? 'Only Toomu can see these. Uninstalling asks whether to keep private files.'
                    : 'Only Toomu can see these. Uninstalling Toomu deletes them unless you tick "Keep app data" '
                        '(Android 10 and newer).',
                style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.6)),
              ),
            );
          }
          final File f = files[i - 1];
          final kind = PrivateVault.kindOf(f.path);
          return ListTile(
            leading: Icon(
              switch (kind) {
                DownloadKind.video => Icons.movie_outlined,
                DownloadKind.audio => Icons.music_note_outlined,
                DownloadKind.file => Icons.insert_drive_file_outlined,
              },
              color: ColorConstants.primary,
            ),
            title: Text(PrivateFolderController.nameOf(f), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(Formatters.bytes(f.lengthSync())),
            trailing: RoundIconButton(
              icon: Icons.more_vert_rounded,
              size: 36,
              tooltip: 'More',
              onTap: () => controller.showItemMenu(f),
            ),
            onTap: () => controller.openItem(f),
            onLongPress: () => controller.showItemMenu(f),
          );
        },
      );
    });
  }
}
