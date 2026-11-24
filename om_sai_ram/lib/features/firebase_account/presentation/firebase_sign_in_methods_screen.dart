import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/data/firebase_provider_gateway.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../providers/firebase_link_provider.dart';

class FirebaseSignInMethodsScreen extends ConsumerWidget {
  const FirebaseSignInMethodsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || ref.watch(firebaseAuthGatewayProvider).currentUser?.uid != session.user?.uid) {
      return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    }
    return _Methods(key: ValueKey(session.user!.uid), uid: session.user!.uid);
  }
}

class _Methods extends ConsumerStatefulWidget {
  final String uid;
  const _Methods({super.key, required this.uid});
  @override
  ConsumerState<_Methods> createState() => _MethodsState();
}
class _MethodsState extends ConsumerState<_Methods> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  FirebaseLinkController get _controller => ref.read(firebaseLinkProvider(widget.uid).notifier);
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted) _controller.refresh(); });
  }
  @override
  void dispose() { _phone.dispose(); _code.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseLinkProvider(widget.uid));
    return Scaffold(appBar: AppBar(title: const Text('Sign-in methods'),
      leading: IconButton(tooltip: 'Back to private profile', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/account'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Linking adds another way to sign in to this account. Accounts are never merged: '
              'a sign-in that already belongs to another account is refused.'),
          if (state.busy) const LinearProgressIndicator(),
          for (final id in state.providers)
            ListTile(leading: const Icon(Icons.check_circle_outline),
              title: Text(providerLabels[id] ?? id), subtitle: const Text('Linked')),
          if (state.message != null) Text(state.message!, key: const Key('link-message')),
          if (state.error != null) Text(state.error!, key: const Key('link-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!state.providers.contains('google.com'))
            OutlinedButton(key: const Key('link-google'),
              onPressed: state.busy ? null : () => _controller.linkOAuth(FirebaseOAuthProvider.google),
              child: const Text('Link Google')),
          if (!state.providers.contains('apple.com'))
            OutlinedButton(key: const Key('link-apple'),
              onPressed: state.busy ? null : () => _controller.linkOAuth(FirebaseOAuthProvider.apple),
              child: const Text('Link Apple')),
          if (!state.providers.contains('phone')) ...[
            TextField(key: const Key('link-phone-number'), controller: _phone,
              enabled: !state.busy && state.challenge == null, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number with country code')),
            if (state.challenge == null)
              OutlinedButton(key: const Key('link-phone-send'),
                onPressed: state.busy ? null : () => _controller.requestPhoneCode(_phone.text),
                child: const Text('Send code to link phone'))
            else ...[
              if (state.challenge!.needsCode)
                TextField(key: const Key('link-phone-code'), controller: _code, enabled: !state.busy,
                  keyboardType: TextInputType.number, maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Six-digit code')),
              FilledButton(key: const Key('link-phone-confirm'),
                onPressed: state.busy ? null : () => _controller.confirmPhoneCode(_code.text),
                child: const Text('Verify and link phone')),
              TextButton(onPressed: state.busy ? null : _controller.cancelPhone,
                child: const Text('Cancel')),
            ],
          ],
        ]))));
  }
}
