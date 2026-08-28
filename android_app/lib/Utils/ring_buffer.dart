// ============================================
// File: utils/ring_buffer.dart
// Ring Buffer untuk sliding window yang efisien
// ============================================

class RingBuffer<T> {
  late List<T?> _buffer;
  late int _capacity;
  int _head = 0;
  int _tail = 0;
  int _size = 0;

  RingBuffer(int capacity) {
    _capacity = capacity;
    _buffer = List<T?>.filled(capacity, null);
  }

  /// Tambah item ke buffer (O(1) operation)
  void add(T item) {
    _buffer[_tail] = item;
    _tail = (_tail + 1) % _capacity;

    if (_size < _capacity) {
      _size++;
    } else {
      // Buffer penuh, geser head
      _head = (_head + 1) % _capacity;
    }
  }

  /// Ambil semua data sebagai List (untuk chart)
  List<T> toList() {
    if (_size == 0) return [];

    final result = <T>[];
    for (int i = 0; i < _size; i++) {
      final index = (_head + i) % _capacity;
      final item = _buffer[index];
      if (item != null) {
        result.add(item);
      }
    }
    return result;
  }

  /// Clear buffer
  void clear() {
    _head = 0;
    _tail = 0;
    _size = 0;
    _buffer = List<T?>.filled(_capacity, null);
  }

  /// Getter
  int get length => _size;
  int get capacity => _capacity;
  bool get isEmpty => _size == 0;
  bool get isFull => _size == _capacity;

  /// Resize buffer capacity (optional, untuk dynamic resizing)
  void resize(int newCapacity) {
    if (newCapacity <= 0) return;

    final currentData = toList();
    _capacity = newCapacity;
    _buffer = List<T?>.filled(newCapacity, null);
    _head = 0;
    _tail = 0;
    _size = 0;

    // Re-add data sampai kapasitas baru
    final itemsToAdd = currentData.length > newCapacity
        ? currentData.sublist(currentData.length - newCapacity)
        : currentData;

    for (final item in itemsToAdd) {
      add(item);
    }
  }
}
