// Om Sai Ram
// Login screen — email/password login with social sign-in options.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/services/router_service.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/social_login_button.dart';

/// Login screen with email/password form and social login options.
///
/// Design: Clean, minimalist layout with the app name at top,
/// input fields centered, and social login buttons below.
/// Includes animated transitions and proper error handling.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Shake animation for error feedback
  late AnimationController _shakeController;

  // Retry tracking
  static const _maxAttempts = 5;
  static const _lockoutSeconds = 30;
  int _attemptCount = 0;
  DateTime? _lockedUntil;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isLockedOut {
    if (_lockedUntil == null) return false;
    if (DateTime.now().isBefore(_lockedUntil!)) return true;
    _lockedUntil = null;
    _attemptCount = 0;
    return false;
  }

  int get _lockoutRemaining =>
      _lockedUntil?.difference(DateTime.now()).inSeconds ?? 0;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _inlineError = null);

    // Check lockout
    if (_isLockedOut) {
      setState(() => _inlineError =
          'Too many failed attempts. Please wait $_lockoutRemaining seconds.');
      _shakeController.forward(from: 0);
      return;
    }

    FocusScope.of(context).unfocus();

    await ref.read(authStateProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _onLoginError(String error) {
    _attemptCount++;
    if (_attemptCount >= _maxAttempts) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: _lockoutSeconds));
      setState(() => _inlineError =
          'Too many failed attempts. Please wait $_lockoutSeconds seconds before trying again.');
    } else {
      final remaining = _maxAttempts - _attemptCount;
      setState(() => _inlineError =
          '$error\n$remaining attempt${remaining == 1 ? '' : 's'} remaining.');
    }
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    final authState = ref.watch(authStateProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    // Show inline error + snackbar if auth failed
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (next.error != null) {
        _onLoginError(next.error!);
        ref.read(authStateProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: screenHeight - MediaQuery.of(context).padding.top - 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: screenHeight * 0.08),

                    // App branding with decorative circle
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.saffron,
                                  AppColors.deepOrange,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.saffron.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.auto_stories_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            tr.appName,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr.appTagline,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.lightText,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Login form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Email field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            validator: Validators.email,
                            decoration: InputDecoration(
                              hintText: tr.email,
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            validator: Validators.password,
                            onFieldSubmitted: (_) => _handleLogin(),
                            decoration: InputDecoration(
                              hintText: tr.password,
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.lightText,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                          ),

                          // Forgot password link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                // TODO: Navigate to forgot password screen
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.saffron,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              child: Text(
                                tr.forgotPassword,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Inline error banner
                          AnimatedBuilder(
                            animation: _shakeController,
                            builder: (context, child) {
                              final sineValue = sin(4 * pi * _shakeController.value);
                              return Transform.translate(
                                offset: Offset(sineValue * 8, 0),
                                child: child,
                              );
                            },
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _inlineError != null
                                  ? Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 14),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.error.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.error_outline_rounded,
                                              color: AppColors.error, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _inlineError!,
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),

                          // Login button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: authState.isLoading ? null : _handleLogin,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(tr.login),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Divider with "Or continue with"
                    Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.lightGrey)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            tr.orContinueWith,
                            style: TextStyle(
                              color: AppColors.lightText,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.lightGrey)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Mobile OTP login — most prominent for Indian users
                    SocialLoginButton(
                      label: tr.signInWithPhone,
                      icon: Icons.phone_android_outlined,
                      onPressed: () => context.go(AppRoutes.phoneLogin),
                    ),
                    const SizedBox(height: 10),
                    SocialLoginButton(
                      label: tr.signInWithGoogle,
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: () {
                        // TODO: Implement Google Sign-In
                      },
                    ),
                    const SizedBox(height: 10),
                    SocialLoginButton(
                      label: tr.signInWithApple,
                      icon: Icons.apple_rounded,
                      onPressed: () {
                        // TODO: Implement Apple Sign-In
                      },
                    ),

                    const SizedBox(height: 28),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tr.dontHaveAccount,
                          style: TextStyle(
                            color: AppColors.mediumText,
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.signup),
                          child: Text(
                            tr.signup,
                            style: TextStyle(
                              color: AppColors.saffron,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
