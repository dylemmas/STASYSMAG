// ============================================
// Test file: test/unit/utils/ring_buffer_test.dart
// ============================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/Utils/ring_buffer.dart';

void main() {
  group('RingBuffer', () {
    test('creates with specified capacity', () {
      final buffer = RingBuffer<int>(5);
      expect(buffer.capacity, 5);
      expect(buffer.length, 0);
      expect(buffer.isEmpty, true);
      expect(buffer.isFull, false);
    });

    test('add increases length', () {
      final buffer = RingBuffer<int>(5);
      buffer.add(1);
      expect(buffer.length, 1);
      expect(buffer.isEmpty, false);
    });

    test('toList returns added items in order', () {
      final buffer = RingBuffer<int>(5);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      expect(buffer.toList(), [1, 2, 3]);
    });

    test('overwrites oldest when full', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // Should overwrite 1

      expect(buffer.length, 3);
      expect(buffer.toList(), [2, 3, 4]);
    });

    test('clear resets buffer', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.clear();

      expect(buffer.length, 0);
      expect(buffer.isEmpty, true);
      expect(buffer.toList(), []);
    });

    test('resize to larger capacity keeps data', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.resize(5);

      expect(buffer.capacity, 5);
      expect(buffer.toList(), [1, 2]);
    });

    test('resize to smaller capacity keeps newest data', () {
      final buffer = RingBuffer<int>(5);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4);
      buffer.add(5);
      buffer.resize(3);

      expect(buffer.capacity, 3);
      expect(buffer.toList(), [3, 4, 5]);
    });

    test('resize to zero does nothing', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.resize(0);

      expect(buffer.capacity, 3);
      expect(buffer.toList(), [1, 2]);
    });

    test('resize to negative does nothing', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.resize(-1);

      expect(buffer.capacity, 3);
      expect(buffer.toList(), [1, 2]);
    });

    test('handles mixed types', () {
      final buffer = RingBuffer<String>(3);
      buffer.add('a');
      buffer.add('b');
      buffer.add('c');

      expect(buffer.toList(), ['a', 'b', 'c']);
    });

    test('wraps around correctly', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4);
      buffer.add(5);

      // Should be [3, 4, 5] (oldest overwritten)
      expect(buffer.toList(), [3, 4, 5]);
    });
  });
}
