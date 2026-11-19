import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/widgets/selection_header.dart';

void main() {
  test('selection toggles, selects all, picks the selected items and clears', () {
    final s = Selection();
    expect(s.active, isFalse);
    s.toggle('a');
    s.toggle('b');
    s.toggle('a');
    expect((s.active, s.count, s.contains('b')), (true, 1, true));
    s.selectAll(['a', 'b', 'c']);
    expect(s.count, 3);
    expect(s.pick([1, 2, 3, 4], (n) => 'abcd'[n - 1]), [1, 2, 3]);
    s.clear();
    expect(s.active, isFalse);
  });
}
