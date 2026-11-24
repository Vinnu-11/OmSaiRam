// Om Sai Ram
// Router service — declarative navigation using GoRouter.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/backend_config.dart';
import '../../features/firebase_reading/presentation/bundled_reading_screen.dart';
import '../../features/firebase_auth/presentation/firebase_auth_screen.dart';
import '../../features/firebase_home/presentation/firebase_home_screen.dart';
import '../../features/firebase_home/presentation/naam_jaap_screen.dart';
import '../../features/firebase_auth/providers/firebase_session_provider.dart';
import '../../features/firebase_account/presentation/firebase_account_screen.dart';
import '../../features/firebase_account/presentation/firebase_change_password_screen.dart';
import '../../features/firebase_account/presentation/firebase_password_reset_screen.dart';
import '../../features/firebase_account/presentation/firebase_sign_in_methods_screen.dart';
import '../../features/firebase_groups/presentation/firebase_groups_screen.dart';
import '../../features/firebase_groups/presentation/group_home_screen.dart';
import '../../features/firebase_groups/presentation/group_list_screens.dart';
import '../../features/firebase_groups/presentation/group_manage_screen.dart';
import '../../features/firebase_group_admin/presentation/firebase_group_settings_screen.dart';
import '../../features/firebase_scheduling/presentation/firebase_scheduling_screen.dart';
import '../../features/firebase_member_display/presentation/firebase_member_display_screen.dart';
import '../../features/firebase_reminders/presentation/firebase_reminders_screen.dart';
import '../../features/firebase_reminders/presentation/firebase_group_reminders_screen.dart';
import '../../features/firebase_reminders/providers/firebase_device_reminders_provider.dart';
import '../../features/firebase_assignments/presentation/firebase_assignments_screen.dart';
import '../../features/firebase_assignments/presentation/firebase_assignment_reader_screen.dart';
import '../../features/firebase_tasks/presentation/firebase_tasks_screen.dart';
import '../../features/firebase_group_progress/presentation/firebase_group_progress_screen.dart';
import '../../features/firebase_chat/presentation/firebase_chat_screen.dart';
import '../../features/firebase_highlights/presentation/firebase_highlights_screen.dart';
import '../../features/firebase_moderation/presentation/firebase_moderation_screen.dart';
import '../../features/firebase_moderation/data/firebase_moderation_models.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/phone_login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/group_detail_screen.dart';
import '../../features/groups/presentation/create_group_screen.dart';
import '../../features/reader/presentation/chapters_screen.dart';
import '../../features/reader/presentation/chapter_reader_screen.dart';
import '../../features/faq/presentation/faq_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/audio/presentation/audio_hub_screen.dart';
import '../../features/audio/presentation/aarti_screen.dart';
import '../../features/audio/presentation/satcharitra_audio_screen.dart';
import '../../features/audio/presentation/live_darshan_screen.dart';
import '../../features/info/presentation/daily_programme_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../shared/widgets/app_shell.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String phoneLogin = '/phone-login';
  static const String groups = '/groups';
  static const String groupDetail = '/groups/:id';
  static const String createGroup = '/groups/create';
  static const String reader = '/reader';
  static const String chapterReader = '/reader/:chapterId';
  static const String faq = '/faq';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String changePassword = '/profile/change-password';
  static const String audio = '/audio';
  static const String aarti = '/audio/aarti';
  static const String satcharitaAudio = '/audio/satcharitra';
  static const String liveDarshan = '/live';
  static const String dailyProgramme = '/daily-programme';
  static const String events = '/events';

  /// Routes that require authentication.
  static const _authRequired = ['/groups', '/profile'];

  /// Whether a given route requires login.
  static bool requiresAuth(String location) {
    return _authRequired.any((r) => location.startsWith(r));
  }
}

/// GoRouter provider — rebuilds when auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  // Return before watching legacy auth: no JWT restoration, AppShell or APIs.
  if (ref.watch(backendConfigProvider).mode == BackendMode.firebase) {
    final refresh = ValueNotifier(0);
    var sessionObserved = false;
    ref.onDispose(refresh.dispose);
    final router = GoRouter(
      initialLocation: '/',
      refreshListenable: refresh,
      routes: [
        GoRoute(path: '/live', builder: (context, state) => const LiveDarshanScreen(firebase: true)),
        GoRoute(path: '/events', builder: (context, state) => const EventsScreen(firebase: true)),
        GoRoute(path: '/audio', builder: (context, state) => const AudioHubScreen()),
        GoRoute(path: '/audio/aarti', builder: (context, state) => const AartiScreen()),
        GoRoute(path: '/audio/satcharitra', builder: (context, state) => const SatcharitaAudioScreen()),
        GoRoute(path: '/daily-programme', builder: (context, state) => const DailyProgrammeScreen()),
        GoRoute(path: '/faq', builder: (context, state) => const FaqScreen(firebase: true)),
        GoRoute(path: '/reader',
          builder: (context, state) => const BundledReadingScreen()),
        GoRoute(path: '/reader/:chapterNumber',
          builder: (context, state) => BundledReadingScreen(
            chapterNumber: state.pathParameters['chapterNumber']!)),
        GoRoute(path: '/jaap', builder: (context, state) => const NaamJaapScreen()),
        GoRoute(
            path: '/', builder: (context, state) => const FirebaseHomeScreen()),
        GoRoute(
            path: '/me', builder: (context, state) => const FirebaseAuthScreen()),
        GoRoute(
            path: '/login',
            builder: (context, state) => const FirebaseAuthScreen()),
        GoRoute(
            path: '/signup',
            builder: (context, state) =>
                const FirebaseAuthScreen(signup: true)),
        GoRoute(
            path: '/tasks',
            builder: (context, state) => const FirebaseTasksScreen()),
        GoRoute(path: '/account', builder: (context, state) => const FirebaseAccountScreen()),
        GoRoute(path: '/account/change-password', builder: (context, state) => const FirebaseChangePasswordScreen()),
        GoRoute(path: '/account/sign-in-methods', builder: (context, state) => const FirebaseSignInMethodsScreen()),
        GoRoute(path: '/phone-login', builder: (context, state) => const FirebaseAuthScreen(phone: true)),
        GoRoute(path: '/forgot-password', builder: (context, state) => const FirebasePasswordResetScreen()),
        GoRoute(
          path: '/reminders',
          builder: (context, state) => const FirebaseRemindersScreen()),
        GoRoute(
            path: '/groups',
            builder: (context, state) => const FirebaseGroupListScreen(),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const FirebaseCreateGroupScreen()),
              GoRoute(path: 'join', builder: (context, state) =>
                FirebaseJoinGroupScreen(initialCode: state.uri.queryParameters['code'])),
              GoRoute(
                  path: ':id',
                  builder: (context, state) => FirebaseGroupHomeScreen(
                      groupId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(path: 'members', builder: (context, state) => FirebaseGroupsScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'manage', builder: (context, state) => FirebaseGroupManageScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'scheduling', builder: (context, state) => FirebaseSchedulingScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'member-names', builder: (context, state) => FirebaseMemberDisplayScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'reminder-schedule', builder: (context, state) => FirebaseGroupRemindersScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'settings', builder: (context, state) => FirebaseGroupSettingsScreen(
                      groupId: state.pathParameters['id']!)),
                    GoRoute(path: 'progress', builder: (context, state) => FirebaseGroupProgressScreen(
                      groupId: state.pathParameters['id']!, initialWeek: state.uri.queryParameters['week'])),
                    GoRoute(
                      path: 'highlights',
                      builder: (context, state) => FirebaseHighlightsScreen(
                        groupId: state.pathParameters['id']!),
                      routes: [GoRoute(
                        path: ':highlightId/moderation',
                        builder: (context, state) => FirebaseModerationScreen(
                          groupId: state.pathParameters['id']!,
                          messageId: state.pathParameters['highlightId']!,
                          kind: FirebaseModerationTargetKind.highlights))]),
                    GoRoute(
                      path: 'moderation/:messageId',
                      builder: (context, state) => FirebaseModerationScreen(
                        groupId: state.pathParameters['id']!,
                        messageId: state.pathParameters['messageId']!)),
                    GoRoute(
                      path: 'chat',
                      builder: (context, state) => FirebaseChatScreen(
                        groupId: state.pathParameters['id']!)),
                    GoRoute(
                        path: 'assignments',
                        builder: (context, state) => FirebaseAssignmentsScreen(
                            groupId: state.pathParameters['id']!,
                            initialMember: state.uri.queryParameters['member'],
                            initialWeek: int.tryParse(
                                    state.uri.queryParameters['week'] ?? '')
                                ?.clamp(1, 10000)),
                        routes: [
                          GoRoute(
                              path: 'read/:memberUid/:week/:unitKey',
                              builder: (context, state) =>
                                  FirebaseAssignmentReaderScreen(
                                      groupId: state.pathParameters['id']!,
                                      memberUid:
                                          state.pathParameters['memberUid']!,
                                      week: state.pathParameters['week']!,
                                      unitKey:
                                          state.pathParameters['unitKey']!))
                        ])
                  ])
            ]),
      ],
      redirect: (context, state) {
        final path = state.uri.path;
        // Public local reading does not initialize Auth or read a profile.
        if (path == '/reader' ||
          (path.startsWith('/reader/') && path.split('/').length == 3) ||
            const ['/audio', '/audio/aarti', '/audio/satcharitra', '/daily-programme', '/faq', '/live', '/events', '/jaap'].contains(path)) {
          return null;
        }
        if (!sessionObserved) {
          sessionObserved = true;
          ref.listen(firebaseSessionProvider, (_, next) {
            refresh.value++;
            if (firebaseNativeReminderPlatform) {
              ref.read(firebaseDeviceRemindersProvider.notifier).sessionChanged(next.ready ? next.user!.uid : null,
                signedOut: !next.busy && (next.user == null || next.deactivated));
            }
          });
        }
        if (path == '/account' || path == '/account/change-password' || path == '/account/sign-in-methods' ||
            path == '/reminders' || path == '/tasks' ||
            path == '/groups' ||
            path.startsWith('/groups/')) {
          return ref.read(firebaseSessionProvider).ready ? null : '/';
        }
        // Once signed in with a name, the sign-in pages have nothing left to do.
        if (const ['/login', '/signup', '/phone-login'].contains(path)) {
          return ref.read(firebaseSessionProvider).ready ? '/' : null;
        }
        return const ['/', '/me', '/forgot-password'].contains(path) ? null : '/';
      },
    );
    ref.onDispose(router.dispose);
    return router;
  }
  // Only login/logout should rebuild the router; loading/error changes would reset navigation.
  final isLoggedIn =
      ref.watch(authStateProvider.select((s) => s.isAuthenticated));

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isOnAuthPage = location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.phoneLogin;

      // If accessing a protected route without login → redirect to login
      if (!isLoggedIn && AppRoutes.requiresAuth(location)) {
        return AppRoutes.login;
      }

      // If logged in and on auth page → go to home
      if (isLoggedIn && isOnAuthPage) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // Auth routes (no shell)
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.phoneLogin,
        builder: (context, state) => const PhoneLoginScreen(),
      ),

      // Main app routes wrapped in bottom navigation shell
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.groups,
            builder: (context, state) => const GroupsScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const CreateGroupScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => GroupDetailScreen(
                  groupId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.reader,
            builder: (context, state) => const ChaptersScreen(),
            routes: [
              GoRoute(
                path: ':chapterId',
                builder: (context, state) {
                  final chapterId =
                      int.tryParse(state.pathParameters['chapterId']!);
                  if (chapterId == null) return const ChaptersScreen();
                  final extra = state.extra as Map<String, dynamic>?;
                  return ChapterReaderScreen(
                    chapterId: chapterId,
                    assignmentId: extra?['assignmentId'] as String?,
                    groupId: extra?['groupId'] as String?,
                    chapterTitle: extra?['chapterTitle'] as String?,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.faq,
            builder: (context, state) => const FaqScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => const EditProfileScreen(),
              ),
              GoRoute(
                path: 'change-password',
                builder: (context, state) => const ChangePasswordScreen(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.audio,
            builder: (context, state) => const AudioHubScreen(),
            routes: [
              GoRoute(
                path: 'aarti',
                builder: (context, state) => const AartiScreen(),
              ),
              GoRoute(
                path: 'satcharitra',
                builder: (context, state) => const SatcharitaAudioScreen(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.liveDarshan,
            builder: (context, state) => const LiveDarshanScreen(),
          ),
          GoRoute(
            path: AppRoutes.dailyProgramme,
            builder: (context, state) => const DailyProgrammeScreen(),
          ),
          GoRoute(
            path: AppRoutes.events,
            builder: (context, state) => const EventsScreen(),
          ),
        ],
      ),
    ],
  );
});
