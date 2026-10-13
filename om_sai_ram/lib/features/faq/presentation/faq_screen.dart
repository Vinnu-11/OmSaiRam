// Om Sai Ram
// FAQ screen — frequently asked questions with expandable answers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/l10n/s.dart';
import '../../../core/providers/language_provider.dart';

/// FAQ screen with expandable question/answer tiles.
///
/// Topics covered:
/// - What is the app and how it works
/// - How to create and manage groups
/// - What is Parayana/Saptah
/// - How chapter assignments work
/// - Reading progress tracking
class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(tr.frequentlyAskedQuestions),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Header section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 36,
                    color: AppColors.saffron,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'How can we help?',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find answers to common questions below',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.lightText,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // FAQ items
          ..._faqItems.asMap().entries.map((entry) => _FaqTile(
                question: entry.value['question']!,
                answer: entry.value['answer']!,
                index: entry.key,
              )),

          const SizedBox(height: 32),

          // Contact hint
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.saffron.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.mail_outline, color: AppColors.saffron, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Still have questions? Reach out to us and we\'ll be happy to help.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mediumText,
                        ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A single expandable FAQ tile with polished styling.
class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  final int index;

  const _FaqTile({
    required this.question,
    required this.answer,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.saffron,
          collapsedIconColor: AppColors.lightText,
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: AppColors.saffron,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            question,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          children: [
            Text(
              answer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: AppColors.mediumText,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static FAQ content.
const List<Map<String, String>> _faqItems = [
  {
    'question': 'What is Om Sai Ram?',
    'answer':
        'Om Sai Ram is an app that helps devotees organize group readings of the Shri Sai Satcharita. You can create or join groups, get assigned chapters, and track your reading progress together.',
  },
  {
    'question': 'What is Shri Sai Satcharita?',
    'answer':
        'Shri Sai Satcharita is a devotional text written by Hemadpant (Govind Raghunath Dabholkar). It contains 53 chapters narrating the life, teachings, and miracles of Shirdi Sai Baba. It is considered the holy scripture of Sai devotees.',
  },
  {
    'question': 'What is Parayana (Saptah)?',
    'answer':
        'Parayana or Saptah is a 7-day reading of the entire Sai Satcharita. All 53 chapters are divided across 7 days, and devotees complete the reading within one week. This is a traditional practice for seeking Baba\'s blessings.',
  },
  {
    'question': 'How do I create a group?',
    'answer':
        'Tap the "+" button on the Groups screen or use the "Create Group" card on the home page. Enter a group name, optional description, and choose a reading mode (Chapter-wise or Weekly Saptah). You\'ll receive an invite code to share with others.',
  },
  {
    'question': 'How do I join a group?',
    'answer':
        'On the Groups screen, tap the group-add icon in the top right corner. Enter the invite code shared by the group admin. You\'ll immediately become a member and can see your assigned chapters.',
  },
  {
    'question': 'What is the difference between Chapter-wise and Saptah modes?',
    'answer':
        'In Chapter-wise mode, the admin manually assigns specific chapters to each member. In Saptah (weekly) mode, the app automatically distributes all 53 chapters across 7 days among group members for a complete reading in one week.',
  },
  {
    'question': 'How do I mark a chapter as read?',
    'answer':
        'Open your assigned chapter in the reader, and tap "Mark as Read" when you\'ve completed it. Your progress will be visible to all group members on the group detail screen.',
  },
  {
    'question': 'Can I read chapters that aren\'t assigned to me?',
    'answer':
        'Yes! The full Satcharita is available in the Reader tab. You can read any chapter at any time. Assignments only determine which chapters you\'re responsible for completing within the group.',
  },
  {
    'question': 'Will the app support other languages?',
    'answer':
        'Yes! The app is built with multi-language support in mind. Currently the Satcharita is available in English, but support for Hindi, Marathi, Telugu, and other languages will be added in future updates.',
  },
  {
    'question': 'Is the app free?',
    'answer':
        'Yes, Om Sai Ram is completely free to use. It is built with devotion for the Sai community.',
  },
];
