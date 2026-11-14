import '../../../../services/audio_player_service.dart';
import '../../../../widgets/option_sheet.dart';

Future<void> showSleepTimerSheet() async {
  final audio = AudioPlayerService.to;
  const off = -1, end = 0;
  final picked = await showOptionSheet<int>(
    title: 'Sleep timer',
    options: const <SheetOption<int>>[
      SheetOption(value: off, label: 'Off'),
      SheetOption(value: 10, label: '10 minutes'),
      SheetOption(value: 15, label: '15 minutes'),
      SheetOption(value: 30, label: '30 minutes'),
      SheetOption(value: 45, label: '45 minutes'),
      SheetOption(value: 60, label: '1 hour'),
      SheetOption(value: end, label: 'End of current track'),
    ],
    selected: switch (audio.sleepMode.value) {
      SleepMode.off => off,
      SleepMode.endOfTrack => end,
      SleepMode.timer => null,
    },
  );
  if (picked == null) return;
  if (picked == off) {
    audio.cancelSleepTimer();
  } else if (picked == end) {
    audio.sleepAtEndOfTrack();
  } else {
    audio.setSleepTimer(Duration(minutes: picked));
  }
}
