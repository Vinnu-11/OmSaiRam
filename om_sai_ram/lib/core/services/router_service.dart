// Om Sai Ram
// Router service — declarative navigation using GoRouter.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../features/audio/presentation/audio_hub_screen.dart';
import '../../features/audio/presentation/aarti_screen.dart';
import '../../features/audio/presentation/satcharitra_audio_screen.dart';
import '../../features/audio/presentation/live_darshan_screen.dart';
import '../../features/info/presentation/daily_programme_screen.dart';
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
  static const String audio = '/audio';
  static const String aarti = '/audio/aarti';
  static const String satcharitaAudio = '/audio/satcharitra';
  static const String liveDarshan = '/live';
  static const String dailyProgramme = '/daily-programme';

  /// Routes that require authentication.
  static const _authRequired = ['/groups', '/profile'];

  /// Whether a given route requires login.
  static bool requiresAuth(String location) {
    return _authRequired.any((r) => location.startsWith(r));
  }
}

/// GoRouter provider — rebuilds when auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,

    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final location = state.matchedLocation;
      final isOnAuthPage = location == AppRoutes.login ||
          location == AppRoutes.signup;

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
                  final extra = state.extra as Map<String, dynamic>?;
                  return ChapterReaderScreen(
                    chapterId: int.parse(state.pathParameters['chapterId']!),
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
        ],
      ),
    ],
  );
});
