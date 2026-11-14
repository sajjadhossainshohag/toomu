import 'package:get/get.dart';

import '../../../core/utils/formatters.dart';
import '../../../services/audio_player_service.dart';
import '../views/widgets/equalizer_sheet.dart';
import '../views/widgets/queue_sheet.dart';
import '../views/widgets/sleep_timer_sheet.dart';
import '../views/widgets/speed_sheet.dart';

class PlayerController extends GetxController {
  final AudioPlayerService audio = AudioPlayerService.to;

  /// While dragging the seek bar we show the drag position, not playback.
  final dragValue = RxnDouble();

  void onSeekChanged(double ms) => dragValue.value = ms;

  void onSeekEnd(double ms) {
    dragValue.value = null;
    audio.seek(Duration(milliseconds: ms.round()));
  }

  void openQueue() => Get.bottomSheet(const QueueSheet(), isScrollControlled: true);
  void openEqualizer() => Get.bottomSheet(const EqualizerSheet(), isScrollControlled: true);
  void openSpeed() => Get.bottomSheet(const SpeedSheet(), isScrollControlled: true);

  String get sleepLabel => switch (audio.sleepMode.value) {
        SleepMode.off => 'Sleep',
        SleepMode.endOfTrack => 'End',
        SleepMode.timer => Formatters.duration(audio.sleepRemaining.value),
      };

  Future<void> openSleepTimer() => showSleepTimerSheet();

  String get abLabel {
    if (audio.abStart.value == null) return 'A-B';
    if (audio.abEnd.value == null) return 'A-?';
    return 'A↔B';
  }
}
