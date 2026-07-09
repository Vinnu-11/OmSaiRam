// Om Sai Ram
// Phone OTP login screen — two-step: enter mobile → enter OTP.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/services/router_service.dart';
import '../providers/auth_provider.dart';

/// Two-step screen: enter mobile number → receive OTP → enter OTP → logged in.
///
/// Designed for 40+ Indian women: large text, clear step indicators,
/// simple inputs, a prominent "Send OTP" button, and a resend timer.
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  // Which step we're on
  bool _otpSent = false;
  // Whether the backend said no account exists and we need a name
  bool _needsName = false;

  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();

  // Resend cooldown
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSecondsLeft <= 1) {
        t.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  String get _normalizedPhone {
    final raw = _phoneController.text.trim();
    // If user typed 10 digits (Indian), prepend +91
    final digitsOnly = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (RegExp(r'^\d{10}$').hasMatch(digitsOnly)) {
      return '+91$digitsOnly';
    }
    if (!digitsOnly.startsWith('+')) return '+$digitsOnly';
    return digitsOnly;
  }

  Future<void> _sendOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    try {
      final expiry = await ref
          .read(authStateProvider.notifier)
          .sendPhoneOtp(_normalizedPhone);
      setState(() => _otpSent = true);
      _startResendTimer(expiry * 60);
    } catch (_) {
      // Error already set in provider state
    }
  }

  Future<void> _verifyOtp() async {
    if (!_otpFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final name = _needsName ? _nameController.text.trim() : null;

    await ref.read(authStateProvider.notifier).verifyPhoneOtp(
      phoneNumber: _normalizedPhone,
      otp: _otpController.text.trim(),
      name: name,
    );

    // If still not authenticated after verify, check for "no account" error
    final state = ref.read(authStateProvider);
    if (!state.isAuthenticated && state.error != null) {
      if (state.error!.contains('No account found')) {
        setState(() => _needsName = true);
        ref.read(authStateProvider.notifier).clearError();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (next.error != null && !next.error!.contains('No account found')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next.error!)),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
        ref.read(authStateProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_otpSent) {
              setState(() {
                _otpSent = false;
                _needsName = false;
                _otpController.clear();
              });
            } else {
              context.go(AppRoutes.login);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Step indicator
              _StepIndicator(step: _otpSent ? 2 : 1),

              const SizedBox(height: 32),

              // Icon
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _otpSent ? Icons.sms_outlined : Icons.phone_android_outlined,
                    size: 36,
                    color: AppColors.saffron,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Heading
              Text(
                _otpSent ? 'Enter OTP' : 'Login with Mobile',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _otpSent
                    ? '${AppStrings.otpSentTo} ${_normalizedPhone}'
                    : 'We\'ll send a 6-digit OTP to your mobile number',
                style: TextStyle(color: AppColors.lightText, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 36),

              if (!_otpSent)
                _PhoneStep(
                  formKey: _phoneFormKey,
                  controller: _phoneController,
                  isLoading: authState.isLoading,
                  onSend: _sendOtp,
                )
              else
                _OtpStep(
                  formKey: _otpFormKey,
                  otpController: _otpController,
                  nameController: _nameController,
                  needsName: _needsName,
                  isLoading: authState.isLoading,
                  resendSecondsLeft: _resendSecondsLeft,
                  onVerify: _verifyOtp,
                  onResend: _resendSecondsLeft == 0 ? _sendOtp : null,
                ),

              const SizedBox(height: 32),

              // Back to email login
              Center(
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.login),
                  style: TextButton.styleFrom(foregroundColor: AppColors.lightText),
                  child: const Text('Login with Email instead',
                      style: TextStyle(fontSize: 13)),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step 1: Phone number entry ───────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;

  const _PhoneStep({
    required this.formKey,
    required this.controller,
    required this.isLoading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\-()]')),
            ],
            validator: Validators.phone,
            onFieldSubmitted: (_) => onSend(),
            style: const TextStyle(fontSize: 18, letterSpacing: 1),
            decoration: InputDecoration(
              hintText: AppStrings.mobileNumberHint,
              prefixIcon: const Icon(Icons.phone_outlined),
              helperText: 'Include country code, e.g. +91 for India',
              helperStyle: TextStyle(color: AppColors.lightText, fontSize: 12),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSend,
              child: isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(AppStrings.sendOtp,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: OTP entry ────────────────────────────────────────────────────────

class _OtpStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController otpController;
  final TextEditingController nameController;
  final bool needsName;
  final bool isLoading;
  final int resendSecondsLeft;
  final VoidCallback onVerify;
  final VoidCallback? onResend;

  const _OtpStep({
    required this.formKey,
    required this.otpController,
    required this.nameController,
    required this.needsName,
    required this.isLoading,
    required this.resendSecondsLeft,
    required this.onVerify,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // OTP field — large digits, easy to read
          TextFormField(
            controller: otpController,
            keyboardType: TextInputType.number,
            textInputAction: needsName ? TextInputAction.next : TextInputAction.done,
            autofocus: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: Validators.otp,
            onFieldSubmitted: needsName ? null : (_) => onVerify(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
              color: AppColors.darkText,
            ),
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: TextStyle(
                  fontSize: 28,
                  letterSpacing: 10,
                  color: AppColors.lightGrey,
                  fontWeight: FontWeight.w700),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              filled: true,
              fillColor: AppColors.cream,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.saffron, width: 2),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Expiry note
          Text(
            AppStrings.otpExpiry,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.lightText),
          ),

          // New account: ask for name
          if (needsName) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.saffron.withOpacity(0.2)),
              ),
              child: Text(
                'No account found. Please enter your name to create a new account.',
                style: TextStyle(
                    color: AppColors.mediumText, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              validator: (v) => Validators.required(v, 'Name'),
              onFieldSubmitted: (_) => onVerify(),
              decoration: const InputDecoration(
                hintText: AppStrings.fullName,
                prefixIcon: Icon(Icons.person_outlined),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Verify button
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : onVerify,
              child: isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(AppStrings.verifyOtp,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 16),

          // Resend button / countdown
          Center(
            child: resendSecondsLeft > 0
                ? Text(
                    'Resend OTP in ${_formatTimer(resendSecondsLeft)}',
                    style: TextStyle(color: AppColors.lightText, fontSize: 14),
                  )
                : TextButton(
                    onPressed: onResend,
                    style: TextButton.styleFrom(foregroundColor: AppColors.saffron),
                    child: const Text(AppStrings.resendOtp,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0
        ? '$m:${s.toString().padLeft(2, '0')} min'
        : '$s sec';
  }
}

// ─── Step indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int step; // 1 or 2

  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Dot(active: step >= 1, done: step > 1, label: 'Mobile'),
        _Line(filled: step > 1),
        _Dot(active: step >= 2, done: false, label: 'OTP'),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;

  const _Dot({required this.active, required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? AppColors.saffron : AppColors.lightGrey,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Icon(
                    active ? Icons.circle : Icons.circle_outlined,
                    color: active ? Colors.white : AppColors.lightText,
                    size: 10,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? AppColors.saffron : AppColors.lightText,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final bool filled;

  const _Line({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
      decoration: BoxDecoration(
        color: filled ? AppColors.saffron : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
