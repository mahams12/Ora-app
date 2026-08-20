import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';

/// Phase 2 onboarding foundation placeholder.
///
/// The full passenger/driver onboarding flow (profile, CNIC, vehicle docs)
/// is implemented in a later phase.  This screen simply tells the user that
/// setup is in progress and holds the route so auth guards remain consistent.
///
/// Onboarding completion status is determined by the backend
/// (`GET /v1/auth/me` → `profileComplete`), NOT by local storage.
///
/// This View does not navigate. It reports intent to [OnboardingViewModel],
/// which promotes the auth state; the router guard then decides the
/// destination. That keeps the completeness decision out of the View.
class OnboardingPlaceholderView extends ConsumerWidget {
  const OnboardingPlaceholderView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Get started')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: OraSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.rocket_launch_outlined, size: 64),
                    const SizedBox(height: OraSpacing.lg),
                    Text(
                      'Almost there',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'Full onboarding is coming in a later phase. '
                      'Tap below to proceed to the home shell.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: OraSpacing.xl),
                    OraButton(
                      label: 'Continue',
                      onPressed: () => ref
                          .read(onboardingViewModelProvider.notifier)
                          .completePlaceholder(),
                    ),
                    const SizedBox(height: OraSpacing.md),
                    OraButton(
                      label: 'Sign out',
                      variant: OraButtonVariant.ghost,
                      onPressed: () =>
                          ref.read(authViewModelProvider.notifier).logout(),
                    ),
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
