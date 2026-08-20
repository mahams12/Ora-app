import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/pakistan_phone_number.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/auth_view_state.dart';

/// Phase 2: Phone number entry screen.
///
/// Pakistan-only mobiles: E.164 `+92` + exactly 10 digits starting with `3`
/// (e.g. `+923001234567`), or local `03XXXXXXXXX`.
///
/// Dev OTP: Firebase Console → Phone → Phone numbers for testing
/// (fixed code e.g. `123456`) — free, no SMS. Real SMS later near deploy.
class PhoneEntryView extends ConsumerStatefulWidget {
  const PhoneEntryView({super.key});

  @override
  ConsumerState<PhoneEntryView> createState() => _PhoneEntryViewState();
}

class _PhoneEntryViewState extends ConsumerState<PhoneEntryView> {
  final _controller = TextEditingController();
  String? _fieldError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authViewModelProvider, (prev, next) {
      if (next is AuthFlowOtpSent && mounted) {
        context.push(AppRoutes.otpEntry);
      }
    });

    final authState = ref.watch(authViewModelProvider);
    final isLoading = authState is AuthFlowRequestingOtp;
    final errorMessage =
        authState is AuthFlowError ? authState.message : null;

    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: padding, vertical: OraSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Logo ─────────────────────────────────────────────
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: OraColors.gold500,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'O',
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: OraColors.navy900,
                                ),
                      ),
                    ),
                    const SizedBox(height: OraSpacing.xl),

                    Text(
                      'Enter your phone number',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Text(
                      "Pakistan mobile only. We'll send a one-time code.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: OraSpacing.lg),

                    // ── Phone field ───────────────────────────────────────
                    OraTextField(
                      controller: _controller,
                      label: 'Phone number',
                      hint: '+923001234567',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      errorText: _fieldError,
                      onChanged: (_) {
                        if (_fieldError != null) {
                          setState(() => _fieldError = null);
                        }
                      },
                    ),
                    const SizedBox(height: OraSpacing.md),

                    // ── Server error banner ───────────────────────────────
                    if (errorMessage != null) ...[
                      _ErrorBanner(message: errorMessage),
                      const SizedBox(height: OraSpacing.md),
                    ],

                    // ── Request OTP button ────────────────────────────────
                    OraButton(
                      label: 'Send code',
                      isLoading: isLoading,
                      onPressed: isLoading ? null : _submit,
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
    final raw = _controller.text.trim();
    final error = PakistanPhoneNumber.validationError(raw);
    if (error != null) {
      setState(() => _fieldError = error);
      return;
    }
    final phone = PakistanPhoneNumber.normalize(raw)!;
    await ref.read(authViewModelProvider.notifier).requestOtp(phoneE164: phone);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
