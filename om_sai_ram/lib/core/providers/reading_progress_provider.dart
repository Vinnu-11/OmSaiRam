// Om Sai Ram
// Reading progress — streak tracking, completed chapters, bookmarks, resume position.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCompletedKey = 'completed_chapters';
const _kResumeChapterKey = 'resume_chapter';
const _kResumePositionKey = 'resume_position';
const _kBookmarksKey = 'bookmarks';
const _kStreakDatesKey = 'streak_dates';

class ReadingProgressState {
  final Set<int> completedChapters;
  final Set<int> bookmarks;
  final int currentStreak; // week streak
  final int longestStreak; // longest week streak
  final int readingsThisWeek; // distinct days read in current ISO week
  final int? resumeChapter;
  final double resumePosition;
  final List<String> streakDates; // ISO date strings of read days

  const ReadingProgressState({
    this.completedChapters = const {},
    this.bookmarks = const {},
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.readingsThisWeek = 0,
    this.resumeChapter,
    this.resumePosition = 0.0,
    this.streakDates = const [],
  });

  ReadingProgressState copyWith({
    Set<int>? completedChapters,
    Set<int>? bookmarks,
    int? currentStreak,
    int? longestStreak,
    int? readingsThisWeek,
    int? resumeChapter,
    double? resumePosition,
    List<String>? streakDates,
  }) {
    return ReadingProgressState(
      completedChapters: completedChapters ?? this.completedChapters,
      bookmarks: bookmarks ?? this.bookmarks,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      readingsThisWeek: readingsThisWeek ?? this.readingsThisWeek,
      resumeChapter: resumeChapter ?? this.resumeChapter,
      resumePosition: resumePosition ?? this.resumePosition,
      streakDates: streakDates ?? this.streakDates,
    );
  }
}

class ReadingProgressNotifier extends StateNotifier<ReadingProgressState> {
  ReadingProgressNotifier() : super(const ReadingProgressState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final completedRaw = prefs.getStringList(_kCompletedKey) ?? [];
    final bookmarksRaw = prefs.getStringList(_kBookmarksKey) ?? [];
    final streakDates = prefs.getStringList(_kStreakDatesKey) ?? [];
    final resumeChapter = prefs.getInt(_kResumeChapterKey);
    final resumePosition = prefs.getDouble(_kResumePositionKey) ?? 0.0;

    final streaks = _computeStreaks(streakDates);

    state = ReadingProgressState(
      completedChapters: completedRaw.map(int.parse).toSet(),
      bookmarks: bookmarksRaw.map(int.parse).toSet(),
      currentStreak: streaks.$1,
      longestStreak: streaks.$2,
      readingsThisWeek: streaks.$3,
      resumeChapter: resumeChapter,
      resumePosition: resumePosition,
      streakDates: streakDates,
    );
  }

  /// Records today as a reading day and recomputes streak.
  Future<void> recordReadingToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final dates = List<String>.from(state.streakDates);
    if (!dates.contains(today)) {
      dates.add(today);
      await prefs.setStringList(_kStreakDatesKey, dates);
      final streaks = _computeStreaks(dates);
      state = state.copyWith(
        currentStreak: streaks.$1,
        longestStreak: streaks.$2,
        readingsThisWeek: streaks.$3,
        streakDates: dates,
      );
    }
  }

  Future<void> markChapterCompleted(int chapterNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = Set<int>.from(state.completedChapters)..add(chapterNumber);
    await prefs.setStringList(
        _kCompletedKey, updated.map((e) => e.toString()).toList());
    await recordReadingToday();
    state = state.copyWith(completedChapters: updated);
  }

  Future<void> saveResumePosition(int chapterNumber, double position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kResumeChapterKey, chapterNumber);
    await prefs.setDouble(_kResumePositionKey, position);
    state = state.copyWith(
        resumeChapter: chapterNumber, resumePosition: position);
  }

  Future<void> toggleBookmark(int chapterNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = Set<int>.from(state.bookmarks);
    if (updated.contains(chapterNumber)) {
      updated.remove(chapterNumber);
    } else {
      updated.add(chapterNumber);
    }
    await prefs.setStringList(
        _kBookmarksKey, updated.map((e) => e.toString()).toList());
    state = state.copyWith(bookmarks: updated);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Returns (currentWeekStreak, longestWeekStreak, readingsThisWeek).
  // A "week" is the ISO week (Mon–Sun). The streak counts consecutive weeks
  // where at least one reading happened. readingsThisWeek is the number of
  // distinct days read in the current ISO week.
  (int, int, int) _computeStreaks(List<String> dates) {
    if (dates.isEmpty) return (0, 0, 0);

    final unique = dates.toSet().map(DateTime.parse).toList()..sort();

    // Map each date to its ISO year+week key "yyyy-Www"
    String isoWeekKey(DateTime d) {
      // ISO week: week containing Thursday. weekday Mon=1..Sun=7.
      final thursday = d.add(Duration(days: 4 - d.weekday));
      final firstDayOfYear = DateTime(thursday.year, 1, 1);
      final weekNum =
          ((thursday.difference(firstDayOfYear).inDays) / 7).floor() + 1;
      return '${thursday.year}-W${weekNum.toString().padLeft(2, '0')}';
    }

    final weeks = unique.map(isoWeekKey).toSet().toList()..sort();

    // Longest streak of consecutive weeks
    int longest = 1;
    int streak = 1;
    for (int i = 1; i < weeks.length; i++) {
      final prev = _parseIsoWeek(weeks[i - 1]);
      final curr = _parseIsoWeek(weeks[i]);
      if (curr.difference(prev).inDays == 7) {
        streak++;
        if (streak > longest) longest = streak;
      } else {
        streak = 1;
      }
    }

    // Current streak: walk backwards from this week
    final thisWeek = isoWeekKey(DateTime.now());
    int current = 0;
    DateTime checkWeek = _parseIsoWeek(thisWeek);
    while (true) {
      final key = isoWeekKey(checkWeek);
      if (weeks.contains(key)) {
        current++;
        checkWeek = checkWeek.subtract(const Duration(days: 7));
      } else {
        break;
      }
    }

    // Readings this week: distinct days in the current ISO week
    final readingsThisWeek =
        unique.where((d) => isoWeekKey(d) == thisWeek).length;

    return (current, longest, readingsThisWeek);
  }

  // Returns the Monday of the ISO week encoded as "yyyy-Www"
  DateTime _parseIsoWeek(String key) {
    final parts = key.split('-W');
    final year = int.parse(parts[0]);
    final week = int.parse(parts[1]);
    // Jan 4 is always in week 1 (ISO 8601)
    final jan4 = DateTime(year, 1, 4);
    final monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return monday.add(Duration(days: (week - 1) * 7));
  }
}

final readingProgressProvider =
    StateNotifierProvider<ReadingProgressNotifier, ReadingProgressState>(
  (ref) => ReadingProgressNotifier(),
);
