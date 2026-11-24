import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/backend_config.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_account_models.dart';
import '../providers/firebase_account_provider.dart';

class FirebasePasswordResetScreen extends ConsumerWidget {
  const FirebasePasswordResetScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (session.user != null || session.busy || ref.watch(firebaseAuthGatewayProvider).currentUser != null) {
      return const Scaffold(body: Center(child: Text('Log out before requesting a password reset.')));
    }
    return const _ResetForm();
  }
}
class _ResetForm extends ConsumerStatefulWidget {
  const _ResetForm();
  @override
  ConsumerState<_ResetForm> createState() => _ResetFormState();
}
class _ResetFormState extends ConsumerState<_ResetForm> {
  final _email = TextEditingController();
  @override
  void dispose() { _email.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebasePasswordResetProvider);
    return Scaffold(appBar: AppBar(title: const Text('Request password reset'),
      leading: IconButton(tooltip: 'Back to login', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/login'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          if (ref.watch(backendConfigProvider).emulator)
            const Text(passwordResetEmulatorNotice),
          const Text('A request acknowledgement is not proof of email delivery.'),
          if (state.busy) const LinearProgressIndicator(),
          TextField(controller: _email, enabled: !state.busy && !state.requested,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
          if (state.error != null) Text(state.error!, key: const Key('reset-error')),
          if (state.requested) const Text(passwordResetRequested, key: Key('reset-requested')),
          FilledButton(onPressed: state.busy || state.requested ? null : () => ref
              .read(firebasePasswordResetProvider.notifier).request(_email.text),
            child: const Text('Request reset instructions')),
        ]))));
  }
}