import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_member_display/data/firestore_member_display_gateway.dart';
import '../data/firebase_group_models.dart';
import 'group_text.dart';

/// Builds [builder] for the signed-in account. Keyed by UID so forms and
/// invite codes are dropped when the account changes.
class GroupSessionGate extends ConsumerWidget {
  final Widget Function(String uid) builder;
  const GroupSessionGate({super.key, required this.builder});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || session.user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in to use groups.')));
    }
    return KeyedSubtree(key: ValueKey(session.user!.uid), child: builder(session.user!.uid));
  }
}

/// A problem message with a large retry button.
class GroupErrorRetry extends ConsumerWidget {
  final String message;
  final VoidCallback? onRetry;
  const GroupErrorRetry({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(color: scheme.errorContainer, child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh),
            label: Text(ref.gt('tryAgain'))),
        ],
      ])));
  }
}

/// A full-width button with a large tap target.
class GroupBigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  const GroupBigButton({super.key, required this.icon, required this.label,
    required this.onPressed, this.primary = false});
  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(56)),
      alignment: Alignment.centerLeft);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: primary
      ? FilledButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label))
      : OutlinedButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label)));
  }
}

Future<bool> confirmGroupAction(BuildContext context, WidgetRef ref, String message) async =>
  await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    content: Text(message),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ref.gtr('cancel'))),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(ref.gtr('confirm'))),
    ])) ?? false;

String groupRoleText(WidgetRef ref, FirebaseGroupRole role) => switch (role) {
  FirebaseGroupRole.admin => ref.gt('roleAdmin'),
  FirebaseGroupRole.groupLead => ref.gt('roleLead'),
  FirebaseGroupRole.member => ref.gt('roleMember'),
};

/// Shared name, or "You" / "Member N" when someone has not shared a name.
String groupMemberName(WidgetRef ref, Map<String, String> names, String uid, int index, String selfUid) =>
  names[uid] ?? (uid == selfUid ? ref.gt('you') : ref.gt('memberN', {'n': index + 1}));

typedef GroupNamesKey = ({String viewer, String groupId, String uids});

/// Up to 20 distinct authors on one page; [GroupNamesKey.viewer] keeps accounts apart.
GroupNamesKey groupNamesKey(String viewer, String groupId, Iterable<String> uids) =>
  (viewer: viewer, groupId: groupId, uids: (uids.toSet().toList()..sort()).take(20).join(','));

/// Names members chose to share. Missing or failed lookups fall back to "A member".
final groupMemberNamesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, GroupNamesKey>((ref, key) async {
  if (key.uids.isEmpty) return const {};
  final uids = key.uids.split(',');
  final rows = await ref.read(firebaseMemberDisplayGatewayProvider).readMembers(key.groupId, uids);
  return {for (final row in rows) if (row.groupId == key.groupId && uids.contains(row.uid)) row.uid: row.displayName};
});

String groupAuthorName(WidgetRef ref, GroupNamesKey key, String uid) {
  final names = ref.watch(groupMemberNamesProvider(key)).asData?.value ?? const {};
  return names[uid] ?? (uid == key.viewer ? ref.gt('you') : ref.gt('someMember'));
}
