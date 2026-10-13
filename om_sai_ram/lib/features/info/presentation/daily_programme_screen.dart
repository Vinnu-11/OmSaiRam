// Om Sai Ram
// Daily Programme screen — Shirdi temple schedule from sai.org.in/en/daily-programme

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

class DailyProgrammeScreen extends StatelessWidget {
  const DailyProgrammeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          'Daily Programme',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.saffron.withOpacity(0.12),
                  AppColors.saffron.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.temple_hindu_rounded,
                      color: AppColors.saffron, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Shree Saibaba Sansthan',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Shirdi, Maharashtra',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.lightText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Today\'s Schedule',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 14),

          // Timeline
          ..._schedule.asMap().entries.map((e) =>
              _TimelineItem(
                entry: e.value,
                isFirst: e.key == 0,
                isLast: e.key == _schedule.length - 1,
              )),
        ],
      ),
    );
  }
}

class _ScheduleEntry {
  final String time;
  final String activity;
  final String? detail;
  final bool isAarti;

  const _ScheduleEntry({
    required this.time,
    required this.activity,
    this.detail,
    this.isAarti = false,
  });
}

const List<_ScheduleEntry> _schedule = [
  _ScheduleEntry(
    time: '4:45 AM',
    activity: 'Temple Opens',
    detail: 'Samadhi Mandir doors open for darshan',
  ),
  _ScheduleEntry(
    time: '5:00 AM',
    activity: 'Bhupali',
    detail: 'Morning devotional songs to wake Baba',
    isAarti: true,
  ),
  _ScheduleEntry(
    time: '5:15 AM',
    activity: 'Kakad Aarti',
    detail: 'Morning aarti — first of the four daily aartis',
    isAarti: true,
  ),
  _ScheduleEntry(
    time: '5:50 AM',
    activity: 'Mangal Snaan',
    detail: 'Sacred bath of the idol in Samadhi Mandir',
  ),
  _ScheduleEntry(
    time: '6:20 AM',
    activity: 'Shirdi Majhe Pandharpur',
    detail: 'Devotional song sung after Mangal Snaan',
    isAarti: true,
  ),
  _ScheduleEntry(
    time: '6:25 AM',
    activity: 'Darshan Begins',
    detail: 'Public darshan opens in Samadhi Mandir',
  ),
  _ScheduleEntry(
    time: '11:30 AM',
    activity: 'Dhuni Pooja',
    detail: 'Pooja with rice and ghee at Dwarkamai',
  ),
  _ScheduleEntry(
    time: '12:00 PM',
    activity: 'Madhyan Aarti',
    detail: 'Mid-day aarti — second of the four daily aartis',
    isAarti: true,
  ),
  _ScheduleEntry(
    time: '4:00 PM',
    activity: 'Pothi Reading',
    detail: 'Devotional reading of Sai Satcharita in Samadhi Mandir',
  ),
  _ScheduleEntry(
    time: 'Sunset',
    activity: 'Dhup Aarti',
    detail: 'Evening aarti — third of the four daily aartis',
    isAarti: true,
  ),
  _ScheduleEntry(
    time: '8:30 – 10:00 PM',
    activity: 'Devotional Songs & Cultural Programs',
    detail: 'Bhajans and cultural programmes in Samadhi Mandir',
  ),
  _ScheduleEntry(
    time: '10:00 PM',
    activity: 'Shej Aarti',
    detail: 'Night aarti — the final aarti of the day, bidding Baba goodnight',
    isAarti: true,
  ),
];

class _TimelineItem extends StatelessWidget {
  final _ScheduleEntry entry;
  final bool isFirst;
  final bool isLast;

  const _TimelineItem({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = entry.isAarti ? AppColors.saffron : AppColors.mediumText;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Top line
                if (!isFirst)
                  Container(width: 2, height: 10, color: AppColors.lightGrey),
                // Dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: entry.isAarti ? AppColors.saffron : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: 2,
                    ),
                  ),
                ),
                // Bottom line
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AppColors.lightGrey),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: entry.isAarti
                      ? AppColors.saffron.withOpacity(0.3)
                      : AppColors.lightGrey,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (entry.isAarti) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.saffron.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Aarti',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.saffron,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.activity,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                  if (entry.detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.detail!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.lightText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
