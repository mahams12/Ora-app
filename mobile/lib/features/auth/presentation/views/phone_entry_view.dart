import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/pakistan_phone_number.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/auth_view_state.dart';
import '../widgets/ora_auth_chrome.dart';

/// Pakistan-only phone entry → Firebase OTP request.
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
    final errorMessage = authState is AuthFlowError ? authState.message : null;

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
                OraSpacing.lg,
                padding,
                OraSpacing.lg + bottomInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OraBrandMark(size: 64),
                  const SizedBox(height: OraSpacing.lg),
                  Text(
                    'Welcome to ${AppConstants.appName}',
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    'Sign in with your Pakistan mobile. We\'ll send a one-time code.',
                    style: OraTypography.body(OraColors.textMuted),
                  ),
                  const SizedBox(height: OraSpacing.xl),
                  OraTextField(
                    controller: _controller,
                    label: 'Phone number',
                    hint: '+92 300 1234567',
                    prefixIcon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    errorText: _fieldError,
                    enabled: !isLoading,
                    onChanged: (_) {
                      if (_fieldError != null) {
                        setState(() => _fieldError = null);
                      }
                    },
                    onSubmitted: (_) {
                      if (!isLoading) _submit();
                    },
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    'Use +92… or local 03XXXXXXXXX',
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: OraSpacing.md),
                    OraAuthBanner(message: errorMessage),
                  ],
                  const SizedBox(height: OraSpacing.lg),
                  OraButton(
                    label: 'Send code',
                    isLoading: isLoading,
                    onPressed: isLoading ? null : _submit,
                    semanticLabel: 'Send verification code',
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
