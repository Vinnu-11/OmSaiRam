// Om Sai Ram
// Upcoming Events screen — shows festivals scraped from sai.org.in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/events_provider.dart';
import '../data/festival_model.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final festivalsAsync = ref.watch(festivalsProvider);

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
          'Upcoming Events',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      body: festivalsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.saffron),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 48, color: AppColors.lightText),
                const SizedBox(height: 16),
                Text(
                  'Unable to load events',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your connection and try again.',
                  style: TextStyle(fontSize: 13, color: AppColors.lightText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(festivalsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.saffron,
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (festivals) {
          if (festivals.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.celebration_outlined,
                        size: 48, color: AppColors.saffron.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'No upcoming events',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check back later for festival announcements.',
                      style: TextStyle(fontSize: 13, color: AppColors.lightText),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.saffron,
            onRefresh: () async => ref.invalidate(festivalsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              itemCount: festivals.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(context);
                return _FestivalCard(festival: festivals[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
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
              child: Icon(Icons.celebration_rounded,
                  color: AppColors.saffron, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shirdi Festivals',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'From sai.org.in · Updated daily',
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
    );
  }
}

class _FestivalCard extends StatelessWidget {
  final Festival festival;

  const _FestivalCard({required this.festival});

  @override
  Widget build(BuildContext context) {
    final isUpcoming = festival.eventDate != null &&
        festival.eventDate!.isAfter(DateTime.now());

    String formattedDate = festival.dateLabel;
    if (festival.eventDate != null) {
      formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(festival.eventDate!);
    }

    // Days until event
    String? daysUntil;
    if (festival.eventDate != null) {
      final diff = festival.eventDate!.difference(DateTime.now()).inDays;
      if (diff == 0) {
        daysUntil = 'Today';
      } else if (diff == 1) {
        daysUntil = 'Tomorrow';
      } else if (diff > 1 && diff <= 60) {
        daysUntil = 'In $diff days';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUpcoming
              ? AppColors.saffron.withOpacity(0.3)
              : AppColors.lightGrey,
        ),
        boxShadow: isUpcoming
            ? [
                BoxShadow(
                  color: AppColors.saffron.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isUpcoming
                      ? AppColors.saffron.withOpacity(0.12)
                      : AppColors.lightGrey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_rounded,
                  color: isUpcoming ? AppColors.saffron : AppColors.mediumText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      festival.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 13,
                        color: isUpcoming
                            ? AppColors.saffron
                            : AppColors.lightText,
                        fontWeight:
                            isUpcoming ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (daysUntil != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    daysUntil,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.saffron,
                    ),
                  ),
                ),
            ],
          ),
          if (festival.description != null &&
              festival.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              festival.description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.lightText,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
