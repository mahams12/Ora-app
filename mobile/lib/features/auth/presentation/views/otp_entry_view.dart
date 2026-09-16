import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/auth_view_state.dart';
import '../widgets/ora_auth_chrome.dart';

/// 6-digit OTP verification. Client submits; Firebase is authoritative.
class OtpEntryView extends ConsumerStatefulWidget {
  const OtpEntryView({super.key});

  @override
  ConsumerState<OtpEntryView> createState() => _OtpEntryViewState();
}

class _OtpEntryViewState extends ConsumerState<OtpEntryView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);
    final padding = Responsive.horizontalPadding(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
    final cooldownSeconds = authState is AuthFlowResendCooldown
        ? authState.remaining.inSeconds
        : 0;
    final errorMessage = authState is AuthFlowError ? authState.message : null;
    final code = _controller.text;
    final busy = isVerifying || isResending;

    return OraAuthScaffold(
      topLeading: OraAuthBackButton(
        onPressed: () =>
            ref.read(authViewModelProvider.notifier).showPhoneEntry(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                OraSpacing.md,
                padding,
                OraSpacing.lg + bottomInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verify your number',
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    session != null
                        ? 'Code sent to ${_maskPhone(session.phoneE164)}'
                        : 'Enter the 6-digit code we sent you.',
                    style: OraTypography.body(OraColors.textMuted),
                  ),
                  const SizedBox(height: OraSpacing.xl),
                  Semantics(
                    textField: true,
                    label: 'One-time verification code',
                    child: GestureDetector(
                      onTap: () => _focusNode.requestFocus(),
                      behavior: HitTestBehavior.opaque,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: 0.01,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLength: 6,
                              enabled: !busy,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                              ),
                              onChanged: (value) {
                                if (value.length == 6 && !busy) {
                                  _submit();
                                }
                              },
                              onSubmitted: (_) {
                                if (!busy) _submit();
                              },
                            ),
                          ),
                          Row(
                            children: List.generate(6, (index) {
                              final digit = index < code.length
                                  ? code[index]
                                  : '';
                              final focused =
                                  _focusNode.hasFocus &&
                                  (index == code.length ||
                                      (code.length == 6 && index == 5));
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: index == 0 ? 0 : OraSpacing.xxs,
                                    right: index == 5 ? 0 : OraSpacing.xxs,
                                  ),
                                  child: OraPinBox(
                                    value: digit,
                                    focused: focused,
                                    hasError: errorMessage != null,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: OraSpacing.md),
                    OraAuthBanner(message: errorMessage),
                  ],
                  const SizedBox(height: OraSpacing.lg),
                  OraButton(
                    label: 'Verify & continue',
                    isLoading: isVerifying,
                    onPressed: busy ? null : _submit,
                    semanticLabel: 'Verify code and continue',
                  ),
                  const SizedBox(height: OraSpacing.md),
                  if (isCooldown)
                    OraAuthBanner(
                      message:
                          'Resend available in ${cooldownSeconds.toString().padLeft(2, '0')}s',
                      isError: false,
                    )
                  else
                    OraButton(
                      label: isResending ? 'Resending…' : 'Resend code',
                      isLoading: isResending,
                      variant: OraButtonVariant.ghost,
                      onPressed: busy ? null : _resend,
                      semanticLabel: 'Resend verification code',
                    ),
                ],
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
    if (mounted) _focusNode.requestFocus();
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, phone.length - 7)}*****${phone.substring(phone.length - 2)}';
  }
}
