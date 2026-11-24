DateTime? utcScheduleDate(DateTime? value) {
  if (value == null) return null;
  if (!value.isUtc || value.year < 1 || value.year > 9999) {
    throw const FormatException('Select an explicit UTC date within years 1-9999.');
  }
  return DateTime.fromMillisecondsSinceEpoch(value.millisecondsSinceEpoch, isUtc: true);
}