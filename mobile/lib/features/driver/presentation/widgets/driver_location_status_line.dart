import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../domain/location/driver_location_status.dart';
import '../location/driver_location_session.dart';

/// Isolated location status. This is the only widget that watches the
/// GPS session, so a new fix does not rebuild the rest of the job screen.
class DriverLocationStatusLine extends ConsumerWidget {
  const DriverLocationStatusLine({required this.rideId, super.key});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(driverLocationSessionProvider(rideId));
    final label = driverLocationStatusLabel(kind);
    if (label == null) return const SizedBox.shrink();

    final action = driverLocationStatusActionLabel(kind);
    final recovering =
        kind == DriverLocationStatusKind.permissionNeeded ||
        kind == DriverLocationStatusKind.permissionBlocked ||
        kind == DriverLocationStatusKind.servicesDisabled ||
        kind == DriverLocationStatusKind.unavailable;

    return Padding(
      padding: const EdgeInsets.only(top: OraSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            key: const Key('driver_location_status'),
            style: OraTypography.caption(
              recovering ? OraColors.goldSoft : OraColors.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: OraSpacing.xs),
            TextButton(
              key: const Key('driver_location_status_action'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: OraColors.primary,
              ),
              onPressed: () {
                ref
                    .read(driverLocationSessionProvider(rideId).notifier)
                    .onUserRecoveryAction();
              },
              child: Text(
                action,
                style: OraTypography.caption(OraColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
