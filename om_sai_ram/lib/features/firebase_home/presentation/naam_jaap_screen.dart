import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../data/home_text.dart';
import '../providers/naam_jaap_provider.dart';

/// One large button: each tap counts one chant and fills a bead of the mala.
class NaamJaapScreen extends ConsumerWidget {
  const NaamJaapScreen({super.key});

  Future<void> _confirmReset(BuildContext context, WidgetRef ref, String code) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(homeText(code, 'startAgain')),
                content: const Text("Today's count goes back to zero."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      key: const Key('jaap-reset-confirm'),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(homeText(code, 'startAgain'))),
                ]));
    if (confirmed == true) ref.read(naamJaapProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(languageProvider).appLanguage.code;
    final state = ref.watch(naamJaapProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(homeText(code, 'jaap')),
          leading: IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(homeText(code, 'tapToCount'),
                  textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              LayoutBuilder(builder: (context, constraints) {
                final size = math.min(constraints.maxWidth, 340.0);
                return Semantics(
                  button: true,
                  label: 'Om Sai Ram. ${state.count} of ${NaamJaapState.beads}',
                  child: SizedBox.square(
                    dimension: size,
                    child: CustomPaint(
                      painter: _MalaPainter(state.count, theme.colorScheme.outline),
                      child: Padding(
                        padding: EdgeInsets.all(size * 0.14),
                        child: Material(
                          color: AppColors.kumkum,
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const Key('jaap-chant'),
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final completed = ref.read(naamJaapProvider.notifier).chant();
                              if (completed) {
                                HapticFeedback.heavyImpact();
                              } else {
                                HapticFeedback.lightImpact();
                              }
                            },
                            child: Center(
                              child: ExcludeSemantics(
                                // Very large text shrinks to stay inside the circle.
                                child: Padding(
                                  padding: EdgeInsets.all(size * 0.08),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Text('ॐ साई राम',
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(color: AppColors.white)),
                                      Text('${state.count}',
                                          key: const Key('jaap-count'),
                                          style: theme.textTheme.displayLarge?.copyWith(
                                              color: AppColors.marigold, fontSize: 56)),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              Text('${state.count} / ${NaamJaapState.beads}',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('${homeText(code, 'malasToday')}: ${state.malas}',
                  key: const Key('jaap-malas'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: state.count == 0 && state.malas == 0
                      ? null
                      : () => _confirmReset(context, ref, code),
                  child: Text(homeText(code, 'startAgain'))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 108 beads around the button; chanted beads turn saffron.
class _MalaPainter extends CustomPainter {
  final int count;
  final Color empty;
  _MalaPainter(this.count, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - size.width * 0.045;
    final bead = size.width * 0.017;
    for (var i = 0; i < NaamJaapState.beads; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / NaamJaapState.beads;
      canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * radius,
          i < count ? bead * 1.25 : bead,
          Paint()..color = i < count ? AppColors.kesari : empty);
    }
  }

  @override
  bool shouldRepaint(_MalaPainter old) => old.count != count || old.empty != empty;
}
