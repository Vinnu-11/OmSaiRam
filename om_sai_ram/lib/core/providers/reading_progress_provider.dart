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
  final int currentStreak;
  final int longestStreak;
  final int? resumeChapter;
  final double resumePosition;
  final List<String> streakDates; // ISO date strings of read days

  const ReadingProgressState({
    this.completedChapters = const {},
    this.bookmarks = const {},
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.resumeChapter,
    this.resumePosition = 0.0,
    this.streakDates = const [],
  });

  ReadingProgressState copyWith({
    Set<int>? completedChapters,
    Set<int>? bookmarks,
    int? currentStreak,
    int? longestStreak,
    int? resumeChapter,
    double? resumePosition,
    List<String>? streakDates,
  }) {
    return ReadingProgressState(
      completedChapters: completedChapters ?? this.completedChapters,
      bookmarks: bookmarks ?? this.bookmarks,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
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

  (int, int) _computeStreaks(List<String> dates) {
    if (dates.isEmpty) return (0, 0);
    final sorted = List<String>.from(dates)..sort();
    final unique = sorted.toSet().toList()..sort();

    int current = 0;
    int longest = 0;
    int streak = 1;

    for (int i = 1; i < unique.length; i++) {
      final prev = DateTime.parse(unique[i - 1]);
      final curr = DateTime.parse(unique[i]);
      final diff = curr.difference(prev).inDays;
      if (diff == 1) {
        streak++;
      } else {
        if (streak > longest) longest = streak;
        streak = 1;
      }
    }
    if (streak > longest) longest = streak;

    // Current streak: count backwards from today
    final today = DateTime.now();
    current = 0;
    for (int i = unique.length - 1; i >= 0; i--) {
      final d = DateTime.parse(unique[i]);
      final expected = today.subtract(Duration(days: unique.length - 1 - i));
      final dayDiff = today.difference(d).inDays;
      if (dayDiff == unique.length - 1 - i) {
        current++;
      } else {
        break;
      }
      if (expected == d) continue;
    }
    // Simpler current streak: walk back from today
    current = 0;
    DateTime check = today;
    while (true) {
      final s =
          '${check.year}-${check.month.toString().padLeft(2, '0')}-${check.day.toString().padLeft(2, '0')}';
      if (unique.contains(s)) {
        current++;
        check = check.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return (current, longest);
  }
}

final readingProgressProvider =
    StateNotifierProvider<ReadingProgressNotifier, ReadingProgressState>(
  (ref) => ReadingProgressNotifier(),
);
