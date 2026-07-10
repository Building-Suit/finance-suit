import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';

enum OnboardingStatus {
  /// Not yet determined (loading or signed out).
  unknown,
  incomplete,
  complete,
}

/// Tracks whether the signed-in user has completed onboarding.
///
/// The router blocks the main shell until this resolves to [complete],
/// so a freshly registered user always lands in the onboarding wizard.
class OnboardingStatusNotifier extends Notifier<OnboardingStatus> {
  @override
  OnboardingStatus build() {
    final auth = ref.watch(authStateProvider);
    if (auth.phase == AuthPhase.signedIn && auth.userId != null) {
      _load(auth.userId!);
    }
    return OnboardingStatus.unknown;
  }

  Future<void> _load(String userId) async {
    try {
      final row = await ref
          .read(supabaseClientProvider)
          .from('user_preferences')
          .select('onboarding_completed_at')
          .eq('user_id', userId)
          .maybeSingle();
      state = (row != null && row['onboarding_completed_at'] != null)
          ? OnboardingStatus.complete
          : OnboardingStatus.incomplete;
    } catch (_) {
      // Network hiccup during startup: treat as incomplete so the user is
      // never stuck on the splash screen; onboarding completion is an
      // idempotent upsert, so re-entering the wizard is safe.
      state = OnboardingStatus.incomplete;
    }
  }

  /// Called by the onboarding wizard after `complete_onboarding` succeeds.
  void markComplete() => state = OnboardingStatus.complete;

  /// Forces a re-check (e.g. after a retry).
  Future<void> refresh() async {
    final auth = ref.read(authStateProvider);
    if (auth.phase == AuthPhase.signedIn && auth.userId != null) {
      await _load(auth.userId!);
    }
  }
}

final onboardingStatusProvider =
    NotifierProvider<OnboardingStatusNotifier, OnboardingStatus>(
      OnboardingStatusNotifier.new,
    );
