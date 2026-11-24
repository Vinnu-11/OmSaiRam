import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../providers/firebase_account_provider.dart';

class FirebaseAccountScreen extends ConsumerWidget {
  const FirebaseAccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || ref.watch(firebaseAuthGatewayProvider).currentUser?.uid != session.user?.uid) {
      return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    }
    return _AccountForm(key: ValueKey(session.user!.uid), uid: session.user!.uid);
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  final String uid;
  const _AccountForm({super.key, required this.uid});
  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}
class _AccountFormState extends ConsumerState<_AccountForm> {
  final _name = TextEditingController();
  FirebaseAccountController get _controller => ref.read(firebaseAccountProvider(widget.uid).notifier);
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted) _controller.load(); });
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseAccountProvider(widget.uid));
    final draft = state.draft ?? '';
    if (_name.text != draft) {
      _name.value = TextEditingValue(
        text: draft, selection: TextSelection.collapsed(offset: draft.length));
    }
    return Scaffold(appBar: AppBar(title: const Text('Private profile'),
      leading: IconButton(tooltip: 'Back to my account', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/me'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('This name is private. Saving does not change your Auth name, email, or any published group names.'),
          if (state.busy) const LinearProgressIndicator(),
          if (state.profile != null) Text('Confirmed private name: ${state.profile!.displayName}', key: const Key('account-confirmed')),
          if (state.acknowledged) Text(state.profile == null
              ? 'Save acknowledged; server values unavailable.' : 'Private profile saved and reloaded from server.',
              key: const Key('account-ack')),
          if (state.error != null) Text(state.error!, key: const Key('account-error')),
          if (state.verifyBeforeSave && state.draft != null)
            const Text('Retained draft is unverified, not a confirmed saved name.'),
          OutlinedButton(onPressed: state.busy ? null : _controller.load,
            child: Text(state.error == null ? 'Reload from server' : 'Retry server read')),
          TextField(controller: _name, enabled: state.canEdit,
            maxLength: 100, decoration: const InputDecoration(labelText: 'Private display name'),
            onChanged: _controller.edit),
          FilledButton(onPressed: state.canEdit && !state.acknowledged ? _controller.save : null,
            child: const Text('Save private name')),
          OutlinedButton(onPressed: () => context.go('/account/change-password'),
            child: const Text('Change password')),
          OutlinedButton(onPressed: () => context.go('/account/sign-in-methods'),
            child: const Text('Sign-in methods')),
        ]))));
  }
}