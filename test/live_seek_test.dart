import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/video_player/controllers/live_seek.dart';

void main() {
  late List<String> sent;
  late LiveSeek seek;

  void setUpSeek() {
    sent = [];
    seek = LiveSeek(fast: (d) => sent.add('fast ${d.inSeconds}'), exact: (d) => sent.add('exact ${d.inSeconds}'));
  }

  testWidgets('dragging the seek bar shows frames as it moves, a few a second', (tester) async {
    setUpSeek();
    // A finger moving for 0.6 s, one event every 20 ms (1 s of video each).
    for (var i = 0; i <= 30; i++) {
      seek.drag(Duration(seconds: i));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    final fast = sent.where((e) => e.startsWith('fast')).toList();
    expect(fast.first, 'fast 0', reason: 'the first move shows a frame at once');
    expect(fast.length, inInclusiveRange(4, 6), reason: 'about one seek per 150 ms, not one per finger event');
    expect(fast.last, 'fast 30', reason: 'where the finger stopped is shown, not dropped');
  });

  testWidgets('letting go seeks exactly to where the finger stopped, and nothing after', (tester) async {
    setUpSeek();
    seek.drag(const Duration(seconds: 5));
    seek.drag(const Duration(seconds: 9));
    seek.end(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 1));
    expect(sent, ['fast 5', 'exact 9']);
  });
}
