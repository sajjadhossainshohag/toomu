import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/speed_meter.dart';

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('quarter-second ticks report bytes per second, not per tick', () {
    final m = SpeedMeter(0, Duration.zero);
    expect(m.add(250000, _ms(250)), 1000000);
    expect(m.add(500000, _ms(500)), 1000000);
    expect(m.add(1000000, _ms(1000)), 1000000);
  });

  test('speed covers about the last second only', () {
    final m = SpeedMeter(0, Duration.zero);
    for (var t = 250; t <= 2000; t += 250) {
      m.add(t * 1000, _ms(t)); // 1 MB/s for 2 s
    }
    // Then a stall: within a second the speed falls to 0.
    var speed = 0;
    for (var t = 2250; t <= 3000; t += 250) {
      speed = m.add(2000000, _ms(t));
    }
    expect(speed, 0);
  });

  test('one late burst does not show as a huge spike', () {
    final m = SpeedMeter(0, Duration.zero);
    for (var t = 250; t <= 1000; t += 250) {
      m.add(0, _ms(t));
    }
    // aria2c-style: bytes arrive once a second.
    expect(m.add(2000000, _ms(1250)), lessThanOrEqualTo(2000000));
  });
}
