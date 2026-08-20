import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/auth_view_state.dart';

/// Phase 2: OTP code entry screen.
///
/// Shows a 6-digit code entry field, a resend button with a 30-second
/// countdown enforced by the ViewModel, and maps server errors
/// (locked, expired, too-many-attempts) to user-friendly banners.
///
/// Client does NOT validate the OTP — it submits and reflects server state.
class OtpEntryView extends ConsumerStatefulWidget {
  const OtpEntryView({super.key});

  @override
  ConsumerState<OtpEntryView> createState() => _OtpEntryViewState();
}

class _OtpEntryViewState extends ConsumerState<OtpEntryView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);
    final padding = Responsive.horizontalPadding(context);

    final session = switch (authState) {
      AuthFlowOtpSent(:final session) => session,
      AuthFlowVerifyingOtp(:final session) => session,
      AuthFlowResendingOtp(:final session) => session,
      AuthFlowResendCooldown(:final session) => session,
      _ => null,
    };

    final isVerifying = authState is AuthFlowVerifyingOtp;
    final isResending = authState is AuthFlowResendingOtp;
    final isCooldown = authState is AuthFlowResendCooldown;
    final cooldownSeconds =
        authState is AuthFlowResendCooldown ? authState.remaining.inSeconds : 0;
    final errorMessage =
        authState is AuthFlowError ? authState.message : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter code'),
        leading: BackButton(
          onPressed: () =>
              ref.read(authViewModelProvider.notifier).showPhoneEntry(),
        ),
      ),
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
                    Text(
                      'Enter the 6-digit code',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Text(
                      session != null
                          ? 'We sent a code to ${_maskPhone(session.phoneE164)}'
                          : 'We sent you a code.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: OraSpacing.lg),

                    // ── 6-digit code field ────────────────────────────────
                    OraTextField(
                      controller: _controller,
                      label: 'Code',
                      hint: '123456',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: OraSpacing.md),

                    // ── Error banner ──────────────────────────────────────
                    if (errorMessage != null) ...[
                      _StatusBanner(message: errorMessage, isError: true),
                      const SizedBox(height: OraSpacing.sm),
                    ],

                    // ── Verify button ─────────────────────────────────────
                    OraButton(
                      label: 'Verify',
                      isLoading: isVerifying,
                      onPressed: (isVerifying || isResending)
                          ? null
                          : _submit,
                    ),
                    const SizedBox(height: OraSpacing.md),

                    // ── Resend button / cooldown countdown ────────────────
                    if (isCooldown)
                      _StatusBanner(
                        message: 'Resend available in ${cooldownSeconds}s',
                        isError: false,
                      )
                    else
                      OraButton(
                        label: isResending ? 'Resending…' : 'Resend code',
                        isLoading: isResending,
                        variant: OraButtonVariant.ghost,
                        onPressed:
                            (isResending || isVerifying) ? null : _resend,
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
    final code = _controller.text.trim();
    if (code.length != 6) return;
    await ref.read(authViewModelProvider.notifier).verifyOtp(code: code);
  }

  Future<void> _resend() async {
    _controller.clear();
    await ref.read(authViewModelProvider.notifier).resendOtp();
  }

  /// Masks phone for display: +92300*****67 style.
  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, phone.length - 7)}*****${phone.substring(phone.length - 2)}';
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bg = isError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final fg = isError
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, color: fg),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
