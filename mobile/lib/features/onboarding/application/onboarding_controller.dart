import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Phases of the OTP sign-in flow.
enum OtpPhase { enterPhone, enterCode }

class OnboardingState {
  const OnboardingState({
    this.phase = OtpPhase.enterPhone,
    this.phone = '',
    this.submitting = false,
    this.error,
  });

  final OtpPhase phase;
  final String phone;
  final bool submitting;
  final String? error;

  OnboardingState copyWith({
    OtpPhase? phase,
    String? phone,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return OnboardingState(
      phase: phase ?? this.phase,
      phone: phone ?? this.phone,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> requestOtp(String phone) async {
    state = state.copyWith(submitting: true, clearError: true, phone: phone);
    try {
      await _auth.requestOtp(phone);
      state = state.copyWith(phase: OtpPhase.enterCode, submitting: false);
    } catch (e) {
      state = state.copyWith(submitting: false, error: _readable(e));
    }
  }

  /// Returns true when verification succeeds and a session is established.
  Future<bool> verifyOtp(String code) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final res = await _auth.verifyOtp(phone: state.phone, token: code);
      state = state.copyWith(submitting: false);
      return res.session != null;
    } catch (e) {
      state = state.copyWith(submitting: false, error: _readable(e));
      return false;
    }
  }

  void backToPhone() {
    state = state.copyWith(phase: OtpPhase.enterPhone, clearError: true);
  }

  String _readable(Object e) {
    final msg = e.toString();
    return msg.length > 160 ? 'Could not complete that step. Try again.' : msg;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
  OnboardingController.new,
);

/// A small curated catalog of interest tags for selection during onboarding.
const kInterestCatalog = <String>[
  'music',
  'jazz',
  'film',
  'climbing',
  'running',
  'coffee',
  'art',
  'gaming',
  'food',
  'travel',
  'photography',
  'tech',
  'books',
  'yoga',
  'cycling',
  'dancing',
  'startups',
  'design',
  'football',
  'hiking',
];
