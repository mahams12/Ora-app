import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/app_bootstrap.dart';

class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView> {
  @override
  Widget build(BuildContext context) {
    // Bootstrap is started by SplashViewModel.build — not from a post-frame
    // callback — to avoid ref-after-dispose races when auth redirects off splash.
    ref.listen(splashViewModelProvider, (previous, next) {
      next.whenOrNull(
        loaded: (_) {
          if (mounted) {
            context.go(AppRoutes.home);
          }
        },
      );
    });

    final state = ref.watch(splashViewModelProvider);

    return Scaffold(
      body: SafeArea(
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
                    initial: () => const OraLoadingIndicator(
                      message: 'Starting Ora…',
                    ),
                    loading: () => const OraLoadingIndicator(
                      message: 'Loading configuration…',
                    ),
                    loaded: (bootstrap) => _SplashContent(bootstrap: bootstrap),
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
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: OraColors.gold500,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Text(
            'O',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: OraColors.navy900,
                ),
          ),
        ),
        const SizedBox(height: OraSpacing.lg),
        Text(
          AppConstants.appName,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: OraSpacing.xs),
        Text(
          bootstrap.environmentName,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
