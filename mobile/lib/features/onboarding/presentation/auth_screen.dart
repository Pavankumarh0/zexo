import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/onboarding_controller.dart';

/// Single screen that handles both phases of the OTP flow (enter phone, enter code).
/// On successful verification the router redirects based on auth + onboarding state.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text('Zexo', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Meet people and events right around you.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
              if (state.phase == OtpPhase.enterPhone)
                ..._phoneFields(state, controller)
              else
                ..._codeFields(state, controller),
              if (state.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneFields(
    OnboardingState state,
    OnboardingController controller,
  ) {
    return [
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+1 415 555 0123',
          prefixIcon: Icon(Icons.phone),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: state.submitting
            ? null
            : () => controller.requestOtp(_phoneCtrl.text.trim()),
        child: state.submitting
            ? const _Spinner()
            : const Text('Send code'),
      ),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('or'),
          ),
          Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        // Google sign-in requires the native Google flow to obtain an ID token,
        // which is wired in via AuthRepository.signInWithGoogle.
        onPressed: state.submitting ? null : _notImplementedGoogle,
        icon: const Icon(Icons.account_circle),
        label: const Text('Continue with Google'),
      ),
    ];
  }

  List<Widget> _codeFields(
    OnboardingState state,
    OnboardingController controller,
  ) {
    return [
      Text('Enter the code sent to ${state.phone}'),
      const SizedBox(height: 16),
      TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Verification code',
          prefixIcon: Icon(Icons.sms),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: state.submitting
            ? null
            : () => controller.verifyOtp(_codeCtrl.text.trim()),
        child: state.submitting ? const _Spinner() : const Text('Verify'),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: state.submitting ? null : controller.backToPhone,
        child: const Text('Use a different number'),
      ),
    ];
  }

  void _notImplementedGoogle() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google sign-in requires the native flow on a device.'),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
