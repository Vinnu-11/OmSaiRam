// Om Sai Ram
// Chapter model — represents a chapter of the Sai Satcharita.

import 'package:equatable/equatable.dart';

/// Represents a single chapter of the Shri Sai Satcharita.
///
/// Content is stored as plain text, loaded from bundled JSON
/// or fetched from the server for updates.
class Chapter extends Equatable {
  final int id;
  final int number;
  final String title;
  final String content;
  final String? heading;
  final String? chapterLabel;
  final String language;
  final int version;

  const Chapter({
    required this.id,
    required this.number,
    required this.title,
    required this.content,
    this.heading,
    this.chapterLabel,
    this.language = 'en',
    this.version = 1,
  });

  /// Last Marathi adhyaya covered by this entry ("16-17" -> 17).
  int get lastNumber =>
      int.tryParse((chapterLabel ?? '').split('-').last) ?? number;

  bool covers(int n) => n >= number && n <= lastNumber;

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as int,
      number: json['number'] as int,
      title: json['title'] as String,
      content: json['content'] as String,
      heading: json['heading'] as String?,
      chapterLabel: json['chapterLabel'] as String?,
      language: json['language'] as String? ?? 'en',
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'content': content,
      'language': language,
      'version': version,
    };
  }

  @override
  List<Object> get props => [id, number, title, language, version];
}
