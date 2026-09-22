import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/presentation/widgets/ora_auth_chrome.dart';

/// Display-name onboarding. Completeness comes from the PATCH `/auth/profile`
/// response (`profileComplete`); the client does not forge readiness.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingViewModelProvider);
    final padding = Responsive.horizontalPadding(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return OraAuthScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                OraSpacing.xl,
                padding,
                OraSpacing.lg + bottomInset,
              ),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OraBrandMark(size: 64),
                    const SizedBox(height: OraSpacing.lg),
                    Text(
                      'What should we call you?',
                      style: OraTypography.headline(OraColors.textPrimary),
                    ),
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'This name is shown to drivers. You can change it later.',
                      style: OraTypography.body(OraColors.textMuted),
                    ),
                    const SizedBox(height: OraSpacing.xl),
                    Semantics(
                      textField: true,
                      label: 'Display name',
                      child: OraTextField(
                        controller: _controller,
                        label: 'Full name',
                        hint: 'e.g. Ayesha Khan',
                        prefixIcon: Icons.person_rounded,
                        errorText: onboarding.fieldError,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        enabled: !onboarding.isSubmitting,
                        onChanged: (value) => ref
                            .read(onboardingViewModelProvider.notifier)
                            .onNameChanged(value),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    if (onboarding.serverError != null) ...[
                      const SizedBox(height: OraSpacing.md),
                      OraAuthBanner(message: onboarding.serverError!),
                      const SizedBox(height: OraSpacing.sm),
                      OraButton(
                        label: 'Try again',
                        variant: OraButtonVariant.outline,
                        onPressed: onboarding.isSubmitting ? null : _submit,
                      ),
                    ],
                    const SizedBox(height: OraSpacing.xl),
                    OraButton(
                      label: 'Continue',
                      isLoading: onboarding.isSubmitting,
                      onPressed: onboarding.isSubmitting ? null : _submit,
                      semanticLabel: 'Save display name and continue',
                    ),
                    const SizedBox(height: OraSpacing.md),
                    OraButton(
                      label: 'Sign out',
                      variant: OraButtonVariant.ghost,
                      onPressed: onboarding.isSubmitting
                          ? null
                          : () => ref
                                .read(authViewModelProvider.notifier)
                                .logout(),
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

  Future<void> _submit() async {
    await ref
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: _controller.text);
  }
}
