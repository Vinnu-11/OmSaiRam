import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_password_gateway.dart';
import '../providers/firebase_password_provider.dart';

class FirebaseChangePasswordScreen extends ConsumerWidget {
  const FirebaseChangePasswordScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || ref.watch(firebaseAuthGatewayProvider).currentUser?.uid != session.user?.uid) {
      return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    }
    return _PasswordForm(key: ValueKey(session.user!.uid), uid: session.user!.uid);
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  final String uid;
  const _PasswordForm({super.key, required this.uid});
  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  void _clear() { _current.clear(); _next.clear(); _confirmation.clear(); }
  Future<void> _submit() async {
    final current = _current.text, next = _next.text, confirmation = _confirmation.text;
    _clear(); // Only transient arguments cross the async boundary, never state.
    try {
      await ref.read(firebasePasswordProvider(widget.uid).notifier)
          .submit(current, next, confirmation);
    } finally { if (mounted) _clear(); }
  }
  @override
  void dispose() {
    _clear();
    _current.dispose(); _next.dispose(); _confirmation.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebasePasswordProvider(widget.uid));
    final metadata = ref.watch(firebasePasswordGatewayProvider).identity;
    final eligible = metadata.eligible && metadata.uid == widget.uid;
    final enabled = eligible && state.canSubmit;
    return Scaffold(appBar: AppBar(title: const Text('Change password'),
      leading: IconButton(tooltip: 'Back to private profile', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/account'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Re-enter your current password to change this signed-in account’s password. Use at least six characters; the server may require a stronger password. A different new password is recommended, not required.'),
          const Text('This does not guarantee or implement revocation of other sessions.'),
          if (!eligible) Text(metadata.unavailable ?? 'The signed-in account changed.'),
          if (state.busy) const LinearProgressIndicator(),
          if (state.complete) const Text('Password update acknowledged. You remain signed in.', key: Key('password-ack')),
          if (state.error != null) Text(state.error!, key: const Key('password-error')),
          for (final field in [(_current, 'Current password'), (_next, 'New password'), (_confirmation, 'Confirm new password')])
            TextField(controller: field.$1, enabled: enabled, obscureText: true,
              enableSuggestions: false, autocorrect: false,
              decoration: InputDecoration(labelText: field.$2)),
          FilledButton(onPressed: enabled ? _submit : null, child: const Text('Change password')),
          if (state.uncertain) OutlinedButton(
            onPressed: () async {
              _clear();
              await ref.read(firebaseSessionProvider.notifier).signOut();
              if (context.mounted && ref.read(firebaseSessionProvider).user == null) {
                context.go('/login');
              }
            }, child: const Text('Log out to verify or reset')),
        ]))));
  }
}