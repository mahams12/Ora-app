import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/app_bootstrap.dart';
import '../view_models/auth_view_state.dart';
import '../widgets/ora_auth_chrome.dart';

class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: OraMotion.sheet);
    _fade = CurvedAnimation(parent: _intro, curve: OraMotion.standard);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: OraMotion.standard));
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splashViewModelProvider);
    final authStatus = ref.watch(authStateNotifierProvider);

    return OraAuthScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = Responsive.horizontalPadding(context);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: state.when(
                  initial: () =>
                      const _SplashBrandBlock(message: 'Starting Ora…'),
                  loading: () => const _SplashBrandBlock(
                    message: 'Loading configuration…',
                  ),
                  loaded: (bootstrap) => FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: _SplashContent(
                        bootstrap: bootstrap,
                        authStatus: authStatus,
                        onRetryBootstrap: () => ref
                            .read(authStateNotifierProvider.notifier)
                            .retryProfileBootstrap(),
                      ),
                    ),
                  ),
                  error: (failure) => OraErrorState(
                    title: 'Unable to start',
                    message: failure.userMessage,
                    onRetry: () =>
                        ref.read(splashViewModelProvider.notifier).retry(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SplashBrandBlock extends StatelessWidget {
  const _SplashBrandBlock({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const OraBrandMark(size: 88),
        const SizedBox(height: OraSpacing.lg),
        Text(
          AppConstants.appName,
          style: OraTypography.display(OraColors.textPrimary),
        ),
        if (message != null) ...[
          const SizedBox(height: OraSpacing.lg),
          OraLoadingIndicator(message: message, expand: false),
        ],
      ],
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent({
    required this.bootstrap,
    required this.authStatus,
    required this.onRetryBootstrap,
  });

  final AppBootstrap bootstrap;
  final AuthStatus authStatus;
  final VoidCallback onRetryBootstrap;

  @override
  Widget build(BuildContext context) {
    final waitingOnSession =
        authStatus == AuthStatus.unknown ||
        authStatus == AuthStatus.authenticated;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const OraBrandMark(size: 88),
        const SizedBox(height: OraSpacing.lg),
        Text(
          AppConstants.appName,
          style: OraTypography.display(OraColors.textPrimary),
        ),
        const SizedBox(height: OraSpacing.xs),
        Text(
          'Your city, your way',
          textAlign: TextAlign.center,
          style: OraTypography.body(OraColors.textSecondary),
        ),
        const SizedBox(height: OraSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.sm,
              vertical: OraSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: OraColors.primaryMuted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 12,
                  color: OraColors.primary,
                ),
                const SizedBox(width: OraSpacing.xxs),
                Flexible(
                  child: Text(
                    'Passenger & driver · one app',
                    textAlign: TextAlign.center,
                    style: OraTypography.caption(OraColors.goldSoft),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: OraSpacing.md),
        Text(
          bootstrap.environmentName,
          style: OraTypography.caption(OraColors.textMuted),
        ),
        if (waitingOnSession) ...[
          const SizedBox(height: OraSpacing.lg),
          const OraLoadingIndicator(message: 'Signing you in…', expand: false),
        ],
        if (authStatus == AuthStatus.authenticated) ...[
          const SizedBox(height: OraSpacing.md),
          OraButton(
            label: 'Try again',
            variant: OraButtonVariant.outline,
            onPressed: onRetryBootstrap,
          ),
        ],
      ],
    );
  }
}
