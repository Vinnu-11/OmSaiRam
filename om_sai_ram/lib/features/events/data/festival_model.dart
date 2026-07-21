// Om Sai Ram

class Festival {
  final String id;
  final String title;
  final String dateLabel;
  final DateTime? eventDate;
  final String? description;
  final String sourceUrl;
  final DateTime scrapedAt;

  const Festival({
    required this.id,
    required this.title,
    required this.dateLabel,
    this.eventDate,
    this.description,
    required this.sourceUrl,
    required this.scrapedAt,
  });

  factory Festival.fromJson(Map<String, dynamic> json) {
    return Festival(
      id: json['id'] as String,
      title: json['title'] as String,
      dateLabel: json['date_label'] as String,
      eventDate: json['event_date'] != null
          ? DateTime.parse(json['event_date'] as String)
          : null,
      description: json['description'] as String?,
      sourceUrl: json['source_url'] as String,
      scrapedAt: DateTime.parse(json['scraped_at'] as String),
    );
  }
}
