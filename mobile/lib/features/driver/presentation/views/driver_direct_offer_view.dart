import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/driver_direct_offer_view_model.dart';

/// Direct offer by known rideId — lab/tooling, not marketplace discovery.
class DriverDirectOfferView extends ConsumerWidget {
  const DriverDirectOfferView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverDirectOfferViewModelProvider);
    final vm = ref.read(driverDirectOfferViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.md,
          padding,
          OraSpacing.xxl,
        ),
        children: [
          Text(
            'Direct offer',
            style: OraTypography.headline(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'Submit an offer for a rideId you already know. This is not a '
            'marketplace browse — Ora will not invent nearby jobs.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.lg),
          OraTextField(
            label: 'Ride ID',
            hint: 'Server rideId',
            onChanged: vm.setRideId,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            label: 'Expected request version',
            hint: 'Positive integer',
            keyboardType: TextInputType.number,
            onChanged: vm.setExpectedRequestVersion,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OraSpacing.md),
          Text(
            'Offer type',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Wrap(
            spacing: OraSpacing.xs,
            runSpacing: OraSpacing.xs,
            children: [
              for (final type in driverOfferTypes)
                OraChip(
                  label: type == 'PASSENGER_PRICE_ACCEPTED'
                      ? 'Accept passenger price'
                      : 'Counteroffer',
                  selected: state.type == type,
                  onTap: () => vm.setType(type),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            label: 'Amount (minor units)',
            hint: 'e.g. 25000 for Rs 250',
            keyboardType: TextInputType.number,
            onChanged: vm.setAmountMinor,
            textInputAction: TextInputAction.done,
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              state.errorMessage!,
              style: OraTypography.caption(OraColors.dangerForeground),
            ),
          ],
          if (state.infoMessage != null) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              state.infoMessage!,
              style: OraTypography.caption(OraColors.goldSoft),
            ),
          ],
          if (state.lastCreatedOffer != null) ...[
            const SizedBox(height: OraSpacing.md),
            OraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last offer from server',
                    style: OraTypography.label(OraColors.textSecondary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    'offerId ${state.lastCreatedOffer!.offerId}',
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                  Text(
                    'status ${state.lastCreatedOffer!.status} · '
                    'amount ${state.lastCreatedOffer!.amountMinor} '
                    '${state.lastCreatedOffer!.currency}',
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'Create offer',
            isLoading: state.phase == DriverDirectOfferPhase.creating,
            onPressed: state.canCreate ? vm.createOffer : null,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Withdraw last offer',
            variant: OraButtonVariant.outline,
            isLoading: state.phase == DriverDirectOfferPhase.withdrawing,
            onPressed: state.canWithdraw ? vm.withdrawOffer : null,
          ),
        ],
      ),
    );
  }
}
