import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/ride_rating_view_model.dart';

/// Passenger stars-only rating screen — Phase 2N contract only.
class RideRatingView extends ConsumerStatefulWidget {
  const RideRatingView({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideRatingView> createState() => _RideRatingViewState();
}

class _RideRatingViewState extends ConsumerState<RideRatingView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideRatingViewModelProvider(widget.rideId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final state = ref.watch(rideRatingViewModelProvider(rideId));
    final vm = ref.read(rideRatingViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Rate your ride',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: switch (state.phase) {
          RideRatingPhase.loading => const Center(
              child: OraLoadingIndicator(message: 'Loading rating…'),
            ),
          RideRatingPhase.fatalError => OraErrorState(
              title: 'Rating unavailable',
              message: state.errorMessage ?? 'Something went wrong.',
              onRetry: vm.retry,
            ),
          RideRatingPhase.ineligible => _MessagePane(
              padding: padding,
              title: 'Cannot rate this ride',
              message: state.errorMessage ??
                  'Only completed or closed rides can be rated.',
              onHome: () => context.go(AppRoutes.home),
            ),
          RideRatingPhase.readyToRate ||
          RideRatingPhase.submitting ||
          RideRatingPhase.success ||
          RideRatingPhase.alreadyRated =>
            _RatingBody(
              state: state,
              padding: padding,
              onSelect: vm.selectStars,
              onSubmit: vm.submit,
              onDone: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
            ),
        },
      ),
    );
  }
}

class _RatingBody extends StatelessWidget {
  const _RatingBody({
    required this.state,
    required this.padding,
    required this.onSelect,
    required this.onSubmit,
    required this.onDone,
  });

  final RideRatingUiState state;
  final double padding;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSubmit;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final readOnly = state.isReadOnly;
    final submitting = state.phase == RideRatingPhase.submitting;
    final success = state.phase == RideRatingPhase.success;
    final already = state.phase == RideRatingPhase.alreadyRated;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        padding,
        OraSpacing.lg,
        padding,
        OraSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OraCard(
            child: Column(
              children: [
                Text(
                  success
                      ? 'Thanks for rating'
                      : already
                          ? 'You already rated this ride'
                          : 'Rate your ride',
                  textAlign: TextAlign.center,
                  style: OraTypography.headline(OraColors.textPrimary),
                ),
                const SizedBox(height: OraSpacing.sm),
                Text(
                  success
                      ? 'Your rating has been submitted.'
                      : already
                          ? 'Ratings cannot be edited or deleted.'
                          : 'Tap a star, then submit. Ora only stores stars — '
                              'no comments or tips in this build.',
                  textAlign: TextAlign.center,
                  style: OraTypography.body(OraColors.textSecondary),
                ),
                const SizedBox(height: OraSpacing.lg),
                OraStarRating(
                  value: state.displayStars,
                  enabled: !readOnly && !submitting,
                  onChanged: readOnly || submitting ? null : onSelect,
                  size: 36,
                ),
                if (state.errorMessage != null &&
                    state.phase == RideRatingPhase.readyToRate) ...[
                  const SizedBox(height: OraSpacing.md),
                  Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: OraTypography.caption(OraColors.dangerForeground),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OraSpacing.lg),
          if (!readOnly)
            OraButton(
              label: 'Submit rating',
              isLoading: submitting,
              onPressed: state.canSubmit && !submitting ? onSubmit : null,
            ),
          if (readOnly) ...[
            OraButton(
              label: 'Done',
              onPressed: onDone,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.padding,
    required this.title,
    required this.message,
    required this.onHome,
  });

  final double padding;
  final String title;
  final String message;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          OraEmptyState(title: title, message: message, icon: Icons.star_outline),
          const Spacer(),
          OraButton(
            label: 'Back to Home',
            variant: OraButtonVariant.ghost,
            onPressed: onHome,
          ),
        ],
      ),
    );
  }
}
