import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';

/// Controls the "invisible mode" toggle (PUT /users/visibility). Seeds from the
/// current profile and optimistically reflects toggles.
class VisibilityController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final profile = await ref.watch(myProfileProvider.future);
    return profile.isVisible;
  }

  Future<void> setVisible(bool visible) async {
    state = AsyncData(visible);
    try {
      final result =
          await ref.read(profileRepositoryProvider).setVisibility(visible);
      state = AsyncData(result);
      ref.invalidate(myProfileProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? true;
    await setVisible(!current);
  }
}

final visibilityControllerProvider =
    AsyncNotifierProvider<VisibilityController, bool>(VisibilityController.new);
