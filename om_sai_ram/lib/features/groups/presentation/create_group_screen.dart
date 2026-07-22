// Om Sai Ram
// Create group screen — form to create a new reading group.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/services/router_service.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';
import '../data/group_model.dart';
import '../providers/groups_provider.dart';

/// Screen for creating a new reading group.
///
/// Collects:
/// - Group name (required)
/// - Description (optional)
/// - Reading mode: Chapter-wise or Weekly Saptah
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  ReadingMode _selectedMode = ReadingMode.chapterWise;
  int _chaptersPerWeek = 2;
  final _chaptersController = TextEditingController(text: '2');

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _chaptersController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(groupsProvider.notifier).createGroup(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          mode: _selectedMode,
          chaptersPerWeek: _chaptersPerWeek,
        );

    if (mounted && success) {
      context.go(AppRoutes.groups);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    final groupsState = ref.watch(groupsProvider);

    // Show error snackbar when group creation fails
    ref.listen<GroupsState>(groupsProvider, (prev, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next.error!)),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
        ref.read(groupsProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.createGroup),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group name
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: Validators.groupName,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: tr.groupName,
                  prefixIcon: const Icon(Icons.group_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: tr.groupDescription,
                  prefixIcon: const Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),

              // Reading mode selection
              Text(
                'Reading Mode',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Chapter-wise option
              _ModeOption(
                title: tr.chapterWise,
                description:
                    'Assign individual chapters (1-53) to each member.',
                icon: Icons.menu_book_outlined,
                isSelected: _selectedMode == ReadingMode.chapterWise,
                onTap: () {
                  setState(() => _selectedMode = ReadingMode.chapterWise);
                },
              ),
              const SizedBox(height: 12),

              // Saptah option
              _ModeOption(
                title: tr.weeklySaptah,
                description:
                    'Complete all chapters in 7 days with automatic daily assignments.',
                icon: Icons.calendar_today_outlined,
                isSelected: _selectedMode == ReadingMode.saptah,
                onTap: () {
                  setState(() => _selectedMode = ReadingMode.saptah);
                },
              ),

              const SizedBox(height: 28),

              // Chapters per week
              Text('Chapters per Week',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'How many chapters each member reads per week (1–53)',
                style: TextStyle(color: AppColors.lightText, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Decrement button
                  _StepperButton(
                    icon: Icons.remove,
                    onTap: _chaptersPerWeek > 1
                        ? () => setState(() {
                              _chaptersPerWeek--;
                              _chaptersController.text = '$_chaptersPerWeek';
                            })
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // Editable number field
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      controller: _chaptersController,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.saffron),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AppColors.saffron, width: 2),
                        ),
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 1 && n <= 53) {
                          setState(() => _chaptersPerWeek = n);
                        }
                      },
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 53) {
                          return '1–53';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Increment button
                  _StepperButton(
                    icon: Icons.add,
                    onTap: _chaptersPerWeek < 53
                        ? () => setState(() {
                              _chaptersPerWeek++;
                              _chaptersController.text = '$_chaptersPerWeek';
                            })
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'chapter${_chaptersPerWeek == 1 ? '' : 's'}/week',
                    style: TextStyle(
                      color: AppColors.lightText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Create button
              ElevatedButton(
                onPressed: groupsState.isLoading ? null : _handleCreate,
                child: groupsState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(tr.createGroup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// +/- stepper button used in the chapters-per-week input.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.saffron : AppColors.lightGrey,
          ),
          color: enabled
              ? AppColors.saffron.withOpacity(0.08)
              : AppColors.lightGrey.withOpacity(0.3),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.saffron : AppColors.lightText,
        ),
      ),
    );
  }
}

/// Selectable card for reading mode options.
class _ModeOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.saffron : AppColors.lightGrey,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? AppColors.saffron.withOpacity(0.05)
              : AppColors.white,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.saffron : AppColors.lightText,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.saffron : AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.saffron),
          ],
        ),
      ),
    );
  }
}
