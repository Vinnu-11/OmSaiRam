/// Language-independent group reading units, retaining Marathi numbering.
class ChapterUnits {
  static const totalChapters = 53;
  static const combined = {16: 17, 18: 19, 43: 44, 51: 53};

  static int start(int number) {
    for (final range in combined.entries) {
      if (number >= range.key && number <= range.value) return range.key;
    }
    return number;
  }

  static int end(int number) => combined[start(number)] ?? number;

  static String label(int number) {
    final first = start(number);
    final last = end(number);
    return first == last ? '$first' : '$first-$last';
  }

  static int next(int number) => end(number) + 1;
  static int previous(int number) => start(start(number) - 1);

  static int advance(int number, int slots) {
    var result = start(number);
    for (var i = 0; i < slots; i++) {
      result = next(result);
    }
    return result;
  }
}