import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/backend_config.dart';
import '../../../core/constants/app_strings.dart';
import '../data/firebase_provider_gateway.dart';
import '../providers/firebase_session_provider.dart';

/// Isolated experimental workspace: no AppShell, legacy auth or notifications.
class FirebaseAuthScreen extends ConsumerStatefulWidget {
  final bool signup, phone;
  const FirebaseAuthScreen({super.key, this.signup = false, this.phone = false});
  @override
  ConsumerState<FirebaseAuthScreen> createState() => _FirebaseAuthScreenState();
}

class _FirebaseAuthScreenState extends ConsumerState<FirebaseAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  FirebasePhoneChallenge? _challenge;
  bool _phoneBusy = false;
  String? _phoneError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _oauth(FirebaseOAuthProvider provider) {
    final gateway = ref.read(firebaseProviderGatewayProvider);
    return ref
        .read(firebaseSessionProvider.notifier)
        .signInWithProvider(() => gateway.oauth(provider));
  }

  Future<void> _sendCode() async {
    if (_phoneBusy) return;
    setState(() {
      _phoneBusy = true;
      _phoneError = null;
    });
    FirebasePhoneChallenge? challenge;
    String? failure;
    try {
      challenge = await ref
          .read(firebaseProviderGatewayProvider)
          .requestPhoneCode(_phone.text);
    } catch (error) {
      failure = error is FirebaseAuthException || error is FormatException
          ? friendlyFirebaseError(error)
          : 'Could not send the code. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _phoneBusy = false;
      _challenge = challenge;
      _phoneError = failure;
    });
  }

  Future<void> _confirmCode() async {
    final challenge = _challenge;
    if (challenge == null) return;
    final code = _code.text;
    if (challenge.needsCode) {
      try {
        validSmsCode(code);
      } on FormatException catch (error) {
        setState(() => _phoneError = error.message);
        return;
      }
    }
    setState(() => _phoneError = null);
    final gateway = ref.read(firebaseProviderGatewayProvider);
    await ref
        .read(firebaseSessionProvider.notifier)
        .signInWithProvider(() => gateway.confirmPhoneCode(challenge, code));
    if (!mounted) return;
    _code.clear();
    // A failed code keeps the challenge so the user can retry without a new SMS.
    if (ref.read(firebaseSessionProvider).user != null) {
      setState(() => _challenge = null);
    }
  }

  Future<void> _submit(FirebaseSession session) async {
    if (session.busy || !_form.currentState!.validate()) return;
    final controller = ref.read(firebaseSessionProvider.notifier);
    if (session.user != null) {
      await controller.retryProfile(_name.text);
    } else if (widget.signup) {
      await controller.signUp(_email.text, _password.text, _name.text);
    } else {
      await controller.signIn(_email.text, _password.text);
    }
    if (!mounted) return;
    _password.clear();
  }

  Future<void> _confirmDeactivate(String uid) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Deactivate account?'),
                content: const SingleChildScrollView(
                    child: Text(
                        'Group features become unavailable for this account until you restore it, and reminders on this device are turned off. '
                        'Transfer ownership of every group you own first. '
                        'Your sign-in, private profile, memberships and history are retained: this is not account deletion or data erasure. '
                        'You can restore the account yourself after logging in.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      key: const Key('account-deactivate-confirm'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Deactivate')),
                ]));
    if (confirmed != true || !mounted) return;
    // UID-bound: a session change while the dialog was open cancels the request.
    final session = ref.read(firebaseSessionProvider);
    if (!session.ready || session.user?.uid != uid) return;
    await ref.read(firebaseSessionProvider.notifier).setAccountDeactivated(true);
  }

  Future<void> _confirmDelete(String uid) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete account permanently?'),
                content: const SingleChildScrollView(
                    child: Text(
                        'This cannot be undone. Your sign-in, private profile and reminder preferences are deleted, and you leave every group. '
                        'Messages, highlights, reading progress and reports you already shared stay in those groups under an anonymous ID without your name. '
                        'Transfer ownership of every group you own first. '
                        'If you logged in more than five minutes ago, you will be asked to log in again before anything is removed.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      key: const Key('account-delete-confirm'),
                      style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.error,
                          foregroundColor:
                              Theme.of(context).colorScheme.onError),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete permanently')),
                ]));
    if (confirmed != true || !mounted) return;
    // UID-bound: a session change while the dialog was open cancels the request.
    if (ref.read(firebaseSessionProvider).user?.uid != uid) return;
    await ref.read(firebaseSessionProvider.notifier).deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    final controller = ref.read(firebaseSessionProvider.notifier);
    final pendingProfile =
        session.user != null && !session.ready && !session.deactivated;
    final emulator = ref.watch(backendConfigProvider).emulator;
    return Scaffold(
      appBar: AppBar(
          title: Text(session.ready
              ? 'My account'
              : session.user != null
                  ? AppStrings.appName
                  : 'Sign in'),
          leading: IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _spaced([
                if (emulator)
                  const Text(
                      'Local development workspace. Sign-in uses the Auth emulator: no real SMS is sent.',
                      textAlign: TextAlign.center),
                if (session.busy) const LinearProgressIndicator(),
                if (session.error != null)
                  Text(session.error!,
                      key: const Key('firebase-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (session.notice != null)
                  Text(session.notice!, key: const Key('firebase-notice')),
                if (session.deactivated) ...[
                  Text('Account deactivated',
                      key: const Key('account-deactivated'),
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(session.user!.email ?? session.user!.phoneNumber ?? ''),
                  const Text(
                      'Your sign-in, private profile, group memberships and reading history are retained. '
                      'Group features stay unavailable until you restore the account. '
                      'This is not account deletion or data erasure: restore the account first if you want to delete it.'),
                  FilledButton(
                      key: const Key('account-restore'),
                      onPressed: session.busy
                          ? null
                          : () => controller.setAccountDeactivated(false),
                      child: const Text('Restore account')),
                ] else if (session.ready) ...[
                  Text('Signed in as ${session.displayName}',
                      key: const Key('firebase-ready'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(session.user!.email ??
                      session.user!.phoneNumber ??
                      'No email available'),
                  OutlinedButton.icon(
                      onPressed: () => context.go('/account'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Change my name')),
                  OutlinedButton.icon(
                      onPressed: () => context.go('/reminders'),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Reminders')),
                  FilledButton(
                      onPressed: session.busy ? null : controller.signOut,
                      child: const Text('Log out')),
                  const Divider(),
                  // Admins add a member by this ID when no invitation is used.
                  Text('Your member ID, if a group admin asks for it',
                      style: Theme.of(context).textTheme.bodySmall),
                  SelectableText(session.user!.uid,
                      key: const Key('account-member-id')),
                  const Divider(),
                  OutlinedButton(
                      key: const Key('account-deactivate'),
                      onPressed: () => _confirmDeactivate(session.user!.uid),
                      child: const Text('Deactivate account')),
                  TextButton(
                      key: const Key('account-delete'),
                      onPressed: () => _confirmDelete(session.user!.uid),
                      child: const Text('Delete account')),
                ] else if (widget.phone && !pendingProfile) ...[
                  Text('Sign in with phone',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(emulator
                      ? 'A six-digit code is sent by SMS. The local Auth emulator sends no real SMS: the code appears in the emulator log.'
                      : 'A six-digit code is sent by SMS. Standard message rates may apply.'),
                  TextField(
                      key: const Key('phone-number'),
                      controller: _phone,
                      enabled:
                          !_phoneBusy && !session.busy && _challenge == null,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Phone number with country code')),
                  if (_phoneBusy) const LinearProgressIndicator(),
                  if (_challenge == null)
                    FilledButton(
                        key: const Key('phone-send'),
                        onPressed:
                            _phoneBusy || session.busy ? null : _sendCode,
                        child: const Text('Send code'))
                  else ...[
                    if (_challenge!.needsCode)
                      TextField(
                          key: const Key('phone-code'),
                          controller: _code,
                          enabled: !session.busy,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                              labelText: 'Six-digit code'))
                    else
                      const Text('Phone verified on this device.'),
                    FilledButton(
                        key: const Key('phone-confirm'),
                        onPressed: session.busy ? null : _confirmCode,
                        child: const Text('Verify and continue')),
                    TextButton(
                        onPressed: session.busy
                            ? null
                            : () => setState(() {
                                  _challenge = null;
                                  _phoneError = null;
                                  _code.clear();
                                }),
                        child: const Text('Change number or resend')),
                  ],
                  if (_phoneError != null)
                    Text(_phoneError!,
                        key: const Key('phone-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  TextButton(
                      onPressed:
                          session.busy ? null : () => context.go('/login'),
                      child: const Text('Back to email login')),
                ] else ...[
                  Text(
                      pendingProfile
                          ? 'One more step: tell us your name'
                          : widget.signup
                              ? (emulator ? 'Create emulator account' : 'Create account')
                              : (emulator ? 'Log in to emulator' : 'Log in'),
                      style: Theme.of(context).textTheme.titleLarge),
                  if (pendingProfile) ...[
                    Text(session.user!.email ?? session.user!.phoneNumber ?? ''),
                    const Text(
                        'You are signed in. Enter the name you would like to use; only you can see it.'),
                  ],
                  Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _spaced([
                      if (!pendingProfile) ...[
                        TextFormField(
                          key: const Key('signin-email'),
                          controller: _email,
                          enabled: !session.busy,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) => value == null ||
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(value.trim())
                              ? 'Enter a valid email address.'
                              : null,
                        ),
                        TextFormField(
                          key: const Key('signin-password'),
                          controller: _password,
                          enabled: !session.busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration:
                              const InputDecoration(labelText: 'Password'),
                          validator: (value) => value == null ||
                                  value.isEmpty ||
                                  (widget.signup && value.length < 6)
                              ? 'Enter a password${widget.signup ? ' of at least six characters' : ''}.'
                              : null,
                        ),
                      ],
                      if (widget.signup || pendingProfile)
                        TextFormField(
                          key: const Key('signin-name'),
                          controller: _name,
                          enabled: !session.busy,
                          maxLength: 100,
                          decoration:
                              const InputDecoration(labelText: 'Your name'),
                          validator: (value) => value == null ||
                                  value.trim().isEmpty ||
                                  value.trim().length > 100
                              ? 'Enter a name of 1–100 characters.'
                              : null,
                        ),
                      FilledButton(
                        onPressed: session.busy ? null : () => _submit(session),
                        child: Text(pendingProfile
                            ? 'Save my name'
                            : widget.signup
                                ? 'Create account'
                                : 'Log in'),
                      ),
                    ])),
                  ),
                  if (pendingProfile) ...[
                    TextButton(
                        onPressed:
                            session.busy ? null : controller.reloadProfile,
                        child: const Text('Try again')),
                    TextButton(
                        key: const Key('account-delete'),
                        onPressed: session.busy
                            ? null
                            : () => _confirmDelete(session.user!.uid),
                        child: const Text('Delete account')),
                  ],
                  if (!pendingProfile && !widget.signup)
                    TextButton(
                      onPressed: session.busy ? null : () => context.go('/forgot-password'),
                      child: const Text('Forgot password?')),
                  if (!pendingProfile)
                    TextButton(
                      onPressed: session.busy
                          ? null
                          : () =>
                              context.go(widget.signup ? '/login' : '/signup'),
                      child: Text(widget.signup
                          ? 'Already registered? Log in'
                          : 'Create an account'),
                    ),
                  if (!pendingProfile) ...[
                    const Divider(),
                    OutlinedButton.icon(
                        key: const Key('signin-google'),
                        onPressed: session.busy
                            ? null
                            : () => _oauth(FirebaseOAuthProvider.google),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google')),
                    OutlinedButton.icon(
                        key: const Key('signin-apple'),
                        onPressed: session.busy
                            ? null
                            : () => _oauth(FirebaseOAuthProvider.apple),
                        icon: const Icon(Icons.apple),
                        label: const Text('Continue with Apple')),
                    OutlinedButton.icon(
                        key: const Key('signin-phone'),
                        onPressed: session.busy
                            ? null
                            : () => context.go('/phone-login'),
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Continue with phone')),
                  ],
                ],
                if (session.user != null && !session.ready)
                  OutlinedButton(
                      onPressed: session.busy ? null : controller.signOut,
                      child: const Text('Log out')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Even vertical breathing room between stacked controls.
List<Widget> _spaced(List<Widget> children) => [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 14),
        children[i],
      ],
    ];
